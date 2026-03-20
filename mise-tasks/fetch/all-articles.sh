#!/usr/bin/env bash
#MISE description="Fetch all blog articles and save content as Markdown"
#USAGE flag "-j --jobs <n>" {
#USAGE   env "N_JOBS"
#USAGE   default "8"
#USAGE   help "Number of jobs to run in parallel to speed up fetching"
#USAGE }

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
  exec env OUTPUT_DIR=input/articles N_JOBS="${usage_jobs:?}" mise run fetch:pages "${ARTICLE_LINKS}"
else
  echo "No blog article links found. This likely means this task needs debugging." >&2
  exit 1
fi
