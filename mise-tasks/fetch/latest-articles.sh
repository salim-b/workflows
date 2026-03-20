#!/usr/bin/env bash
#MISE description="Fetch latest blog articles and save content as Markdown"

set -euo pipefail

ARTICLE_LINKS="$(
  (
    echo '<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wfw="http://wellformedweb.org/CommentAPI/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:sy="http://purl.org/rss/1.0/modules/syndication/" xmlns:slash="http://purl.org/rss/1.0/modules/slash/"><channel>'
    page=1
    found=0
    while [ $found -eq 0 ]; do
      content=$(curl -s -L -A "Mozilla/5.0" "https://www.digitale-gesellschaft.ch/feed/?paged=$page")
      [[ "$content" != *"<item>"* ]] && break
      echo "$content" | sed -n '/<item>/,/<\/item>/p'
      [[ "$content" =~ category.*Newsletter.*category ]] && found=1
      ((page++))
      [ $page -gt 10 ] && break
    done
    echo '</channel></rss>'
  ) | \
    xee xpath "string-join(//item[category = 'Newsletter'][1]/preceding-sibling::item[not(category = ('Veranstaltungen'))]/link, ' ')" | \
    tr -d '"'
)"

if [[ -n "$ARTICLE_LINKS" ]]; then
  exec env OUTPUT_DIR=input/articles mise run fetch:pages "${ARTICLE_LINKS}"
else
  echo "No blog articles published since last newsletter."
  exit 1
fi
