#!/usr/bin/env bash
#MISE description="Generate newsletter draft and write it to Confluence"
#USAGE flag "--article-links <urls>" {
#USAGE   env "ARTICLE_LINKS"
#USAGE   default ""
#USAGE   help "URLs to the blog articles to be covered by the newsletter, separated by space, tab or newline"
#USAGE }
#USAGE flag "--newsletter-links <urls>" {
#USAGE   env "NEWSLETTER_LINKS"
#USAGE   default ""
#USAGE   help "URLs to past newsletters that shall serve as examples, separated by space, tab or newline"
#USAGE }
#USAGE flag "--confluence-space-key <id>" {
#USAGE   env "CONFLUENCE_SPACE_KEY"
#USAGE   help "Key identifying the space in the Confluence wiki to place the new page in"
#USAGE }
#USAGE flag "--confluence-ancestor-id <id>" {
#USAGE   env "CONFLUENCE_ANCESTOR_ID"
#USAGE   help "Identifier of the Confluence wiki page under which the new page is to be created"
#USAGE }
#USAGE flag "--confluence-host <origin>" {
#USAGE   env "CONFLUENCE_HOST"
#USAGE   help "Scheme (protocol) plus hostname (domain) locating the Confluence instance"
#USAGE }
#USAGE flag "--confluence-pat <secret>" {
#USAGE   env "CONFLUENCE_PAT"
#USAGE   help "Personal Access Token (PAT) to authenticate with the Confluence host"
#USAGE }

set -euo pipefail

# Get relevant Blog post links
ARTICLE_LINKS="${usage_article_links:-$(
  (
    echo '<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wfw="http://wellformedweb.org/CommentAPI/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:sy="http://purl.org/rss/1.0/modules/syndication/" xmlns:slash="http://purl.org/rss/1.0/modules/slash/"><channel>'
    page=1
    found=0
    while [ $found -eq 0 ]; do
      content=$(curl -s -L -A "Mozilla/5.0" "https://www.digitale-gesellschaft.ch/feed/?paged=$page")
      [[ "$content" != *"<item>"* ]] && break
      echo "$content" | sed -n '/<item>/,/<\/item>/p'
      [[ "$content" =~ category.*Newsletter.*category ]] && found=1
      ((page++))
      [ $page -gt 10 ] && break
    done
    echo '</channel></rss>'
  ) | \
    xee xpath "string-join(//item[category='Newsletter'][1]/preceding-sibling::item[not(category='Zmittag')]/link, ' ')" | \
    xargs -d '"' echo | \
    xargs -n1
)}"
## NOTE: `read -d ''` returns exit 1 since it never reaches the expected NUL byte, thus we need to short-circuit
IFS=$' \t\n' read -r -d '' -a article_urls <<< "$ARTICLE_LINKS" || true

NEWSLETTER_LINKS="${usage_newsletter_links:-$(
  curl -s -L -A "Mozilla/5.0" https://www.digitale-gesellschaft.ch/feed/?tag=newsletter | \
    xee xpath "string-join(//item/link, ' ')" | \
    xargs -d '"' echo | \
    xargs -n1
)}"
## NOTE: `read -d ''` returns exit 1 since it never reaches the expected NUL byte, thus we need to short-circuit
IFS=$' \t\n' read -r -d '' -a newsletter_urls <<< "$NEWSLETTER_LINKS" || true

# Fetch content from all links and save as Markdown
rm -rf input && mkdir --parents input/newsletters/ input/blog_posts/
for i in "${!article_urls[@]}"; do
  URL="${article_urls[$i]}"
  FILE_PATH="input/blog_posts/$((i+1)).md"
  spider --url="$URL" --depth=1 --budget='*,1' --headless --wait-for-idle-dom=body scrape --output-html \
    | jq --raw-output '.html' \
    | htmd --ignored-tags="head,script,style,header" --heading-style=setex \
    > "${FILE_PATH}" \
    && sed --in-place '/^### Newsletter$/,$d' "${FILE_PATH}" \
    && sed --in-place "1i ---\nurl: ${URL}/\n---\n"
  # alternative: html-to-markdown --preprocess --preset=aggressive --with-metadata --extract-document --extract-structured-data | yq '.markdown'
done
for i in "${!newsletter_urls[@]}"; do
  URL="${newsletter_urls[$i]}"
  FILE_PATH="input/newsletters/$((i+1)).md"
  spider --url="$URL" --depth=1 --budget='*,1' --headless --wait-for-idle-dom=body scrape --output-html \
    | jq --raw-output '.html' \
    | htmd --ignored-tags="head,script,style,header" --heading-style=setex \
    > "${FILE_PATH}" \
    && sed --in-place '/^### Newsletter$/,$d' "${FILE_PATH}" \
    && sed --in-place "1i ---\nurl: ${URL}/\n---\n"
done

# Run Goose recipe
## inside Distrobox, use host's Goose executable
if [[ -z "${CONTAINER_ID:-}" ]]; then
  GOOSE_CLI="goose"
else
  GOOSE_CLI="$(distrobox-host-exec which goose)"
fi

CONTENT=$(
  "${GOOSE_CLI}" run --no-session --quiet \
    --recipe newsletter_draft \
    | tail -n 1 \
    | jq --raw-output '.newsletter_draft'
)

# Normalize Confluence host trailing slash
: "${usage_confluence_host:?}"
CONFLUENCE_HOST="${usage_confluence_host%/}"

# Prepare Confluence page title
## Calculate the 3rd Wednesday of the current month (always between the 15th and 21st)
YEAR_MONTH=$(date +"%Y-%m")
for d in {15..21}; do
  if [ "$(date -d "$YEAR_MONTH-$d" +%u)" -eq 3 ]; then
    DATE="$YEAR_MONTH-$d"
    break
  fi
done

BASE_TITLE="«Update» $DATE"
TITLE="$BASE_TITLE"
COUNTER=1

## Add serial nr to title if a page wth the title already exists
echo "Checking if page with title '$TITLE' already exists..."
while true; do
  CHECK_RESPONSE=$(curl \
    --silent \
    --location \
    --header "Authorization: Bearer ${usage_confluence_pat:?}" \
    --request GET \
    "${CONFLUENCE_HOST}/rest/api/content?title=$(echo -n "$TITLE" | jq -sRr @uri)&spaceKey=${usage_confluence_space_key:?}"
  )

  if [[ $(echo "$CHECK_RESPONSE" | jq '.size') -gt 0 ]]; then
    TITLE="$BASE_TITLE ($COUNTER)"
    echo "Title already exists. Trying '$TITLE'..."
    COUNTER=$((COUNTER + 1))
  else
    break
  fi
done

# Convert result to HTML and write to new Confluence page
BODY_HTML=$(echo "$CONTENT" | pandoc --from=markdown --to=html --wrap=none)

echo "Creating new Confluence wiki page: $TITLE"

CONFLUENCE_PAYLOAD=$(jq -n \
  --arg title "$TITLE" \
  --arg space_key "${usage_confluence_space_key:?}" \
  --arg ancestor_id "${usage_confluence_ancestor_id:?}" \
  --arg val "$BODY_HTML" \
  '{
     type: "page",
     title: $title,
     space: {
       key: $space_key
     },
     ancestors: [{id: $ancestor_id}],
     body: {
       storage: {
         value: $val,
         representation: "storage"
       }
     }
   }')

CONFLUENCE_RESPONSE=$(curl -s -L -X POST "${CONFLUENCE_HOST}/rest/api/content" \
  -H "Authorization: Bearer ${usage_confluence_pat:?}" \
  -H "Content-Type: application/json" \
  -d "$CONFLUENCE_PAYLOAD")

CONFLUENCE_PAGE_LINK=$(echo "$CONFLUENCE_RESPONSE" | jq --raw-output '._links.base + ._links.webui')

if [[ "$CONFLUENCE_PAGE_LINK" == *"null"* ]]; then
  echo "Error: Failed to create Confluence page"
  echo "Response: $CONFLUENCE_RESPONSE"
  exit 1
fi

echo "Confluence wiki page created successfully: $CONFLUENCE_PAGE_LINK"

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "Erstellte Wiki-Seite: [**$TITLE**]($CONFLUENCE_PAGE_LINK)" >> "$GITHUB_STEP_SUMMARY"
fi
