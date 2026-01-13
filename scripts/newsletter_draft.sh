#!/bin/bash
#
# Generate newsletter draft and write it to Confluence
#
# Required environment variables:
#
# - ARTICLE_LINKS (optional, auto-fetched by default)
# - NEWSLETTER_LINKS (optional, auto-fetched by default)
# - OPENROUTER_API_KEY
# - OPENROUTER_MODEL (optional)
# - OPENROUTER_PROMPT (optional)
# - CONFLUENCE_SPACE_KEY
# - CONFLUENCE_ANCESTOR_ID
# - CONFLUENCE_HOST
# - CONFLUENCE_PAT

set -euo pipefail

# Load static defaults from config.env (if it exists)
# WARNING: Multiline values (with quoted newlines) are not supported
CONFIG_PATH="$(dirname "$0")/../config.env"
if [ -f "$CONFIG_PATH" ]; then
  while read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)= ]]; then
      key="${BASH_REMATCH[1]}"      
      [ -z "${!key+x}" ] && eval "$line"
    fi
  done < "$CONFIG_PATH"
fi

# Get relevant Blog post links and append them to `OPENROUTER_PROMPT`
ARTICLE_LINKS="${ARTICLE_LINKS:-$(
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
NEWSLETTER_LINKS="${NEWSLETTER_LINKS:-$(
  curl -s -L -A "Mozilla/5.0" https://www.digitale-gesellschaft.ch/feed/?tag=newsletter | \
    xee xpath "string-join(//item/link, ' ')" | \
    xargs -d '"' echo | \
    xargs -n1
)}"
OPENROUTER_PROMPT+=$'\n\n# Artikellinks\n\n'"$ARTICLE_LINKS"$'\n\n# Letzte 10 Newsletter\n\n'"$NEWSLETTER_LINKS"

# Call OpenRouter API
echo "Fetching response from OpenRouter..."

OPENROUTER_PAYLOAD=$(jq -n \
  --arg model "$OPENROUTER_MODEL" \
  --arg prompt "$OPENROUTER_PROMPT" \
  '{
     model: $model,
     messages: [{role: "user", content: $prompt}]
   }')

OPENROUTER_RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$OPENROUTER_PAYLOAD")

# Extract content using jq
CONTENT=$(echo "$OPENROUTER_RESPONSE" | jq -r '.choices[0].message.content')

if [ -z "$CONTENT" ] || [ "$CONTENT" == "null" ]; then
  echo "Error: Failed to get content from OpenRouter"
  echo "Response: $OPENROUTER_RESPONSE"
  exit 1
fi

echo "Successfully received content from OpenRouter."

# Prepare Confluence page
DATE=$(date +"%Y-%m-%d")
TITLE="«Update» $DATE"
BODY_HTML=$(echo "$CONTENT" | pandoc --from=markdown --to=html --wrap=none)

echo "Creating new Confluence wiki page: $TITLE"

# Call Confluence API
CONFLUENCE_PAYLOAD=$(jq -n \
  --arg title "$TITLE" \
  --arg space_key "$CONFLUENCE_SPACE_KEY" \
  --arg ancestor_id "$CONFLUENCE_ANCESTOR_ID" \
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
CONFLUENCE_HOST="${CONFLUENCE_HOST%/}"
CONFLUENCE_RESPONSE=$(curl -s -X POST "${CONFLUENCE_HOST}/rest/api/content" \
  -H "Authorization: Bearer $CONFLUENCE_PAT" \
  -H "Content-Type: application/json" \
  -d "$CONFLUENCE_PAYLOAD")

CONFLUENCE_PAGE_LINK=$(echo "$CONFLUENCE_RESPONSE" | jq -r '._links.base + ._links.webui')

if [[ "$CONFLUENCE_PAGE_LINK" == *"null"* ]]; then
  echo "Error: Failed to create Confluence page"
  echo "Response: $CONFLUENCE_RESPONSE"
  exit 1
fi

echo "Confluence wiki page created successfully: $CONFLUENCE_PAGE_LINK"
