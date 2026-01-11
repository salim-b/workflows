#!/bin/bash
#
# Generate newsletter draft and write it to Confluence
#
# Required environment variables:
#
# - OPENROUTER_API_KEY
# - OPENROUTER_MODEL (optional)
# - OPENROUTER_PROMPT
# - CONFLUENCE_ANCESTOR_ID 
# - CONFLUENCE_HOST
# - CONFLUENCE_PAT

set -euo pipefail

# Get relevant Blog article links
ARTICLE_LINKS="$(
  (
    echo '<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wfw="http://wellformedweb.org/CommentAPI/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:sy="http://purl.org/rss/1.0/modules/syndication/" xmlns:slash="http://purl.org/rss/1.0/modules/slash/"><channel>'
    page=1
    found=0
    while [ $found -eq 0 ]; do
      content=$(curl -s -L -A "Mozilla/5.0" "https://www.digitale-gesellschaft.ch/feed/?paged=$page")
      if ! echo "$content" | grep -qF "<item>"; then break; fi
      echo "$content" | sed -n '/<item>/,/<\/item>/p'
      if echo "$content" | grep -qF "<category>Newsletter<category>"; then found=1; fi
      ((page++))
      if [ $page -gt 10 ]; then break; fi
    done
    echo '</channel></rss>'
  ) | \
    xee xpath "string-join(//item[category='Newsletter'][1]/preceding-sibling::item[not(category='Zmittag')]/link, ' ')" | \
    xargs -d '"' echo | \
    xargs -n1
)"
NEWSLETTER_LINKS="$(
  curl -s -L -A "Mozilla/5.0" https://www.digitale-gesellschaft.ch/feed/?tag=newsletter | \
    xee xpath "string-join(//item/link, ' ')" | \
    xargs -d '"' echo | \
    xargs -n1
)"

# Call OpenRouter API
OPENROUTER_MODEL="${OPENROUTER_MODEL:-"google/gemini-2.0-flash-exp:free"}"
OPENROUTER_PROMPT="${OPENROUTER_PROMPT:-"Du unterstützt die Redaktion der Digitalen Gesellschaft Schweiz bei der Erstellung ihres monatlichen Newsletters. Du erhälst eine Liste von Artikellinks und rufst diese selbständig auf, um deren Inhalt zu erfassen. Für jeden Link erstellst du genau einen Abschnitt mit 1–2 (maximal 3) Absätzen aus insgesamt 3–6 Sätzen. Jeder Abschnitt fasst den Inhalt zusammen, erklärt den Kontext und lädt zur weiteren Lektüre ein. Am Ende jedes Abschnitts wird der jeweilige Artikellink angefügt. Du fasst Artikel nur dann thematisch zusammen, wenn du ausdrücklich dazu aufgefordert wirst. Der Stil orientiert sich an den bestehenden Newslettern der Digitalen Gesellschaft (siehe *Bisherige Newsletter*): sachlich, verständlich und engagiert, mit einem zivilgesellschaftlichen, grundrechtsorientierten Ton. Du schreibst in Markdown-Syntax (ohne Emojis). Du achtest auf sprachliche Klarheit, vermeidest Werbesprache und übertriebene Zuspitzungen und bleibst kritisch gegenüber Machtmissbrauch, Überwachung und Datenschutzverletzungen. Wenn ein Artikel nicht abrufbar ist, fügst du einen Platzhalter-Abschnitt mit Fehlermeldung ein. Du nutzt direkten Webzugriff, um Inhalte zu prüfen und korrekt wiederzugeben."}"
OPENROUTER_PROMPT+=$'\n\n# Artikellinks\n\n'"$ARTICLE_LINKS"$'\n\n# Letzte 10 Newsletter\n\n'"$NEWSLETTER_LINKS"

echo "Fetching response from OpenRouter..."

RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"$OPENROUTER_MODEL"'",
    "messages": [
      {"role": "user", "content": "'"$OPENROUTER_PROMPT"'"}
    ]
  }')

# Extract content using jq
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')

if [ -z "$CONTENT" ] || [ "$CONTENT" == "null" ]; then
  echo "Error: Failed to get content from OpenRouter"
  echo "Response: $RESPONSE"
  exit 1
fi

echo "Successfully received content from OpenRouter."

# Prepare Confluence page
DATE=$(date +"%Y-%m-%d")
TITLE="«Update» $DATE"
BODY_HTML=$(echo "$CONTENT" | pandoc -f markdown -t html --wrap=none)

echo "Creating Confluence page: $TITLE"

# Call Confluence API
CREATE_PAGE_RESPONSE=$(curl -s -X POST "${CONFLUENCE_HOST%/}/rest/api/content" \
  -H "Authorization: Bearer $CONFLUENCE_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "page",
    "title": '"$TITLE"',
    "ancestors": [{"id": "'"$CONFLUENCE_ANCESTOR_ID"'"}],
    "body": {
      "storage": {
        "value": '"$BODY_HTML"',
        "representation": "storage"
      }
    }
  }')

PAGE_LINK=$(echo "$CREATE_PAGE_RESPONSE" | jq -r '._links.base + ._links.webui')

if [[ "$PAGE_LINK" == *"null"* ]]; then
  echo "Error: Failed to create Confluence page"
  echo "Response: $CREATE_PAGE_RESPONSE"
  exit 1
fi

echo "Confluence page created successfully: $PAGE_LINK"
