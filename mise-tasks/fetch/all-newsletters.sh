#!/usr/bin/env bash
#MISE description="Fetch all newsletters and save content as Markdown"

set -euo pipefail

NEWSLETTER_LINKS="$(
  page=1
  while true; do
    content=$(curl -s -L -A "Mozilla/5.0" "https://www.digitale-gesellschaft.ch/feed/?tag=newsletter&paged=$page")
    [[ "$content" != *"<item>"* ]] && break

    echo "$content" | \
      xee xpath "string-join(//item/link, ' ')" | \
      tr -d '"'

    ((page++))
  done
)"

if [[ -n "$NEWSLETTER_LINKS" ]]; then
  exec env OUTPUT_DIR=input/newsletters mise run fetch:pages "${NEWSLETTER_LINKS}"
else
  echo "No newsletter links found. This likely means this task needs debugging."
  exit 1
fi
