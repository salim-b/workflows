#!/bin/bash
#
# Generate newsletter draft and write it to Confluence
#
# Required environment variables:
#
# - OPENROUTER_API_KEY
# - OPENROUTER_MODEL (optional)
# - OPENROUTER_PROMPT
# - CONFLUENCE_API_TOKEN
# - CONFLUENCE_DOMAIN
# - CONFLUENCE_EMAIL
# - CONFLUENCE_SPACE_KEY

set -euo pipefail

OPENROUTER_MODEL="${OPENROUTER_MODEL:-"google/gemini-2.0-flash-exp:free"}"
OPENROUTER_PROMPT="${OPENROUTER_PROMPT:-"Du unterstützt die Redaktion der Digitalen Gesellschaft Schweiz bei der Erstellung ihres monatlichen Newsletters. Du erhälst eine Liste von Artikellinks und rufst diese selbständig auf, um deren Inhalt zu erfassen. Für jeden Link erstellst du genau einen Abschnitt mit 1–2 Absätzen und insgesamt 3–6 Sätzen. Jeder Abschnitt fasst den Inhalt zusammen, erklärt den Kontext und lädt zur weiteren Lektüre ein. Am Ende jedes Abschnitts wird der jeweilige Link im Stil der bestehenden Newsletter der Digitalen Gesellschaft eingefügt (z. B. „Mehr dazu: [Link]“). Du fasst Artikel nur dann thematisch zusammen, wenn du ausdrücklich dazu aufgefordert wirst. Der Stil orientiert sich an den bestehenden Newslettern der Digitalen Gesellschaft: sachlich, verständlich und engagiert, mit einem zivilgesellschaftlichen, grundrechtsorientierten Ton. Du schreibst in Markdown-Syntax (ohne Emojis). Du achtest auf sprachliche Klarheit, vermeidest Werbesprache und übertriebene Zuspitzungen und bleibst kritisch gegenüber Machtmissbrauch, Überwachung und Datenschutzverletzungen. Wenn ein Artikel nicht abrufbar ist, fragst du nach weiteren Informationen. Du nutzt direkten Webzugriff, um Inhalte zu prüfen und korrekt wiederzugeben."}"

echo "Fetching response from OpenRouter..."

# Call OpenRouter API
RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": '"$OPENROUTER_MODEL"',
    "messages": [
      {"role": "user", "content": '"$OPENROUTER_PROMPT"'}
    ]
  }')

# Extract content using jq
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')

if [ -z "$CONTENT" ] || [ "$CONTENT" == "null" ]; then
  echo "Error: Failed to get content from OpenRouter"
  echo "Response: $RESPONSE"
  exit 1
fi

echo "Successfully received content from AI."

# Prepare Confluence Page
DATE=$(date +"%Y-%m-%d")
TITLE="«Update» $DATE"

# Convert markdown to HTML for Confluence using Pandoc
BODY_HTML=$(echo "$CONTENT" | pandoc -f markdown -t html --wrap=none)

echo "Creating Confluence page: $TITLE"

# Call Confluence API
# Note: Using Basic Auth with Email:API_TOKEN
AUTH=$(echo -n "$CONFLUENCE_EMAIL:$CONFLUENCE_API_TOKEN" | base64)

CREATE_PAGE_RESPONSE=$(curl -s -X POST "https://${CONFLUENCE_DOMAIN}/rest/api/content" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "page",
    "title": '"$TITLE"',
    "space": {"key": '"$CONFLUENCE_SPACE_KEY"'},
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
