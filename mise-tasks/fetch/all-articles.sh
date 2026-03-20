#!/usr/bin/env bash
#MISE description="Fetch all blog articles and save content as Markdown"

set -euo pipefail

ARTICLE_LINKS="$(
  page=1
  while true; do
    content=$(curl -s -L -A "Mozilla/5.0" "https://www.digitale-gesellschaft.ch/feed/?paged=$page")
    [[ "$content" != *"<item>"* ]] && break

    echo "$content" | \
      xee xpath "string-join(//item[not(category = ('Newsletter', 'Veranstaltungen'))]/link, ' ')" | \
      tr -d '"'

    ((page++))
  done
)"

if [[ -n "$ARTICLE_LINKS" ]]; then
  exec env OUTPUT_DIR=input/articles mise run fetch:pages "${ARTICLE_LINKS}"
else
  echo "No blog article links found. This likely means this task needs debugging."
  exit 1
fi
