#!/usr/bin/env bash
#MISE description="Fetch latest newsletters and save content as Markdown"

set -euo pipefail

NEWSLETTER_LINKS="$(
  curl -s -L -A "Mozilla/5.0" https://www.digitale-gesellschaft.ch/feed/?tag=newsletter | \
    xee xpath "string-join(//item/link, ' ')" | \
    tr -d '"'
)"

if [[ -n "$NEWSLETTER_LINKS" ]]; then
  exec env OUTPUT_DIR=input/newsletters mise run fetch:pages "${NEWSLETTER_LINKS}"
else
  exec env echo "No newsletter links found. This likely means this task needs debugging."
  exit 1
fi
