#!/usr/bin/env bash
#MISE description="Fetch pages and save content as Markdown"
#USAGE arg "<urls>" help "URLs of the pages to fetch" env "URLS_TO_FETCH"
#USAGE flag "-o --output-dir <path>" {
#USAGE   env "OUTPUT_DIR"
#USAGE   default "input/pages"
#USAGE   help "Directory to write the resulting Markdown files to"
#USAGE }

set -euo pipefail

## NOTE: `read -d ''` returns exit 1 since it never reaches the expected NUL byte, thus we need to short-circuit
IFS=$' \t\n' read -r -d '' -a urls <<< "${usage_urls:?}" || true

# Fetch content from all links and save as Markdown
if (command -v chromium >/dev/null || command -v google-chrome >/dev/null); then

  OUTPUT_DIR="${usage_output_dir:?}"
  OUTPUT_DIR="${usage_output_dir%/}"
  rm -rf "${OUTPUT_DIR}" && mkdir --parents "${OUTPUT_DIR}"

  for i in "${!urls[@]}"; do
    URL="${urls[$i]}"
    FILE_PATH="${OUTPUT_DIR}/$((i+1)).md"
    spider --url="$URL" --depth=1 --budget='*,1' --headless --wait-for-idle-dom=body scrape --output-html \
      | jq --raw-output '.html' \
      | htmd --ignored-tags="head,script,style,header" --heading-style=setex \
      > "${FILE_PATH}" \
      && sed --in-place '/^### Newsletter$/,$d' "${FILE_PATH}" \
      && sed --in-place "1i ---\nurl: ${URL}\n---\n" "${FILE_PATH}"
    # alternative: html-to-markdown --preprocess --preset=aggressive --with-metadata --extract-document --extract-structured-data | yq '.markdown'
  done
else
  echo "No Chromium browser detected."
  exit 1
fi
