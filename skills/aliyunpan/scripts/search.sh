#!/usr/bin/env bash
# Search acoooder/aliyunpanshare for resources with Aliyun Drive share links.
# Usage: search.sh <keyword>

set -euo pipefail

REPO="acoooder/aliyunpanshare"
KEYWORD="${1:-}"

if [[ -z "$KEYWORD" ]]; then
  echo "Usage: search.sh <keyword>"
  exit 1
fi

# Step 1: Search for files containing the keyword via GitHub Code Search
paths=$(gh search code --repo "$REPO" "$KEYWORD" --json path --jq '.[].path' 2>/dev/null | sort -u)

if [[ -z "$paths" ]]; then
  echo "No results found for '$KEYWORD'."
  exit 0
fi

header_printed=false
count=0
# Track seen links for deduplication
declare -A seen_links

while IFS= read -r filepath; do
  # Step 2: Fetch raw file content
  content=$(gh api "repos/$REPO/contents/$filepath" \
    -H "Accept: application/vnd.github.raw+json" 2>/dev/null) || continue

  # Step 3: Filter lines that match keyword AND contain an Aliyun Drive link
  while IFS= read -r line; do
    # Skip header/separator lines
    [[ "$line" == *"---"* && "$line" != *"http"* ]] && continue
    [[ "$line" != *"|"* ]] && continue

    # Must contain alipan.com or aliyundrive.com
    if ! echo "$line" | grep -qE '(alipan\.com|aliyundrive\.com)'; then
      continue
    fi

    # Must match keyword (case-insensitive)
    if ! echo "$line" | grep -qi "$KEYWORD"; then
      continue
    fi

    # Extract fields from the Markdown table row
    # Supports both 3-col (name|link|time) and 4-col (name|type|link|time) formats
    name=""
    link=""
    pub_time=""

    # Split by | and iterate to find relevant columns
    IFS='|' read -ra cols <<< "$line"
    for col in "${cols[@]}"; do
      trimmed=$(echo "$col" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$trimmed" ]] && continue

      if echo "$trimmed" | grep -qE 'https://(www\.)?(alipan\.com|aliyundrive\.com)/'; then
        link="$trimmed"
      elif echo "$trimmed" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
        pub_time="$trimmed"
      elif [[ -z "$name" ]]; then
        name="$trimmed"
      fi
    done

    [[ -z "$link" ]] && continue

    # Deduplicate by link URL
    if [[ -n "${seen_links[$link]:-}" ]]; then
      continue
    fi
    seen_links[$link]=1

    # Print table header once
    if [[ "$header_printed" == false ]]; then
      echo "| Resource | Link | Published |"
      echo "| --- | --- | --- |"
      header_printed=true
    fi

    echo "| $name | $link | $pub_time |"
    count=$((count + 1))
  done <<< "$content"
done <<< "$paths"

if [[ "$header_printed" == false ]]; then
  echo "No Aliyun Drive links found for '$KEYWORD'."
else
  echo ""
  echo "Found $count result(s)."
fi
