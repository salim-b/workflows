#!/bin/bash
#
# Generate newsletter draft and write it to Confluence
#
# Required environment variables:
#
# - OPENROUTER_API_KEY
# - CONFLUENCE_DOMAIN
# - CONFLUENCE_EMAIL
# - CONFLUENCE_API_TOKEN
# - CONFLUENCE_SPACE_KEY
# - AI_MODEL (optional)
# - AI_PROMPT (optional)

set -euo pipefail

AI_MODEL="${AI_MODEL:-"google/gemini-2.0-flash-exp:free"}"
AI_PROMPT="${AI_PROMPT:-"Provide a brief summary of the importance of documentation in software development."}"

echo "Fetching response from OpenRouter..."

# Call OpenRouter API
RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    "model": "$AI_MODEL",
    "messages": [
      {"role": "user", "content": "$AI_PROMPT"}
    ]
  }")

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

# Convert markdown to basic HTML for Confluence (Storage format)
# This is a very simple conversion for the sake of the script.
# For better results, a dedicated tool like pandoc would be better, but we'll stick to simple wrapper.
BODY_HTML="<p>$(echo "$CONTENT" | sed ':a;N;$!ba;s/
/<br\/>/g' | sed 's/"/"/g')</p>"

echo "Creating Confluence page: $TITLE"

# Call Confluence API
# Note: Using Basic Auth with Email:API_TOKEN
AUTH=$(echo -n "$CONFLUENCE_EMAIL:$CONFLUENCE_API_TOKEN" | base64)

CREATE_PAGE_RESPONSE=$(curl -s -X POST "https://${CONFLUENCE_DOMAIN}/rest/api/content" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d "{
    "type": "page",
    "title": "$TITLE",
    "space": {"key": "$CONFLUENCE_SPACE_KEY"},
    "body": {
      "storage": {
        "value": "$BODY_HTML",
        "representation": "storage"
      }
    }
  }")

PAGE_LINK=$(echo "$CREATE_PAGE_RESPONSE" | jq -r '._links.base + ._links.webui')

if [[ "$PAGE_LINK" == *"null"* ]]; then
  echo "Error: Failed to create Confluence page"
  echo "Response: $CREATE_PAGE_RESPONSE"
  exit 1
fi

echo "Confluence page created successfully: $PAGE_LINK"
