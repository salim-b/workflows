#!/usr/bin/env bash
#MISE description="Fetch all newsletters and save content as Markdown"
#USAGE flag "-j --jobs <n>" {
#USAGE   env "N_JOBS"
#USAGE   default "8"
#USAGE   help "Number of jobs to run in parallel to speed up fetching"
#USAGE }

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
  exec env OUTPUT_DIR=input/newsletters N_JOBS="${usage_jobs:?}" mise run fetch:pages "${NEWSLETTER_LINKS}"
else
  echo "No newsletter links found. This likely means this task needs debugging." >&2
  exit 1
fi
