#!/usr/bin/env bash
#MISE description="Fetch pages and save content as Markdown"
#USAGE arg "<urls>" help "URLs of the pages to fetch" env "URLS_TO_FETCH"
#USAGE flag "-o --output-dir <path>" {
#USAGE   env "OUTPUT_DIR"
#USAGE   default "input/pages"
#USAGE   help "Directory to write the resulting Markdown files to"
#USAGE }
#USAGE flag "-j --jobs <n>" {
#USAGE   env "N_JOBS"
#USAGE   default "4"
#USAGE   help "Number of jobs to run in parallel to speed up fetching multiple pages"
#USAGE }

set -euo pipefail

## NOTE: `read -d ''` returns exit 1 since it never reaches the expected NUL byte, thus we need to short-circuit
IFS=$' \t\n' read -r -d '' -a urls <<< "${usage_urls:?}" || true

if ! (command -v chromium >/dev/null || command -v google-chrome >/dev/null); then
  echo "No Chromium browser detected." >&2
  exit 1
fi

OUTPUT_DIR="${usage_output_dir:?}"
export OUTPUT_DIR="${OUTPUT_DIR%/}"
rm -rf "${OUTPUT_DIR}" && mkdir --parents "${OUTPUT_DIR}"

# 1. Define the worker logic as a function
process_url() {
  # Subshells do not inherit parent flags natively; re-apply them for safety
  set -euo pipefail
  
  local i="$1"
  local url="$2"
  local file_path="${OUTPUT_DIR}/$((i+1)).md"

  spider --url="$url" --depth=1 --budget='*,1' --headless --wait-for-idle-dom=body scrape --output-html \
    | jq --raw-output '.html' \
    | htmd --ignored-tags="head,script,style,header" --heading-style=setex \
    > "${file_path}"

  sed --in-place '/^### Newsletter$/,$d' "${file_path}"
  sed --in-place "1i ---\nurl: ${url}\n---\n" "${file_path}"
  
  echo "✓ Fetched: $url"
}

# 2. Export the function so xargs' child shells can use it
export -f process_url

echo "Starting fetch for ${#urls[@]} URLs..."

# 3. Stream indices and URLs safely to xargs
# -P n     : Run exactly n jobs in parallel
# -n 2     : Pass 2 arguments (index, url) to each job
# -0       : Use NUL bytes to prevent spaces/quotes in URLs from breaking things
# shellcheck disable=SC2016
for i in "${!urls[@]}"; do
  printf "%s\0%s\0" "$i" "${urls[$i]}"
done | xargs -0 -n 2 -P "${usage_jobs:?}" bash -c 'process_url "$1" "$2"' _

echo "Finished fetch for ${#urls[@]} URLs!"
