---
name: aliyunpan
description: "Search Chinese movie/TV show resources with Aliyun Drive share links from GitHub repo acoooder/aliyunpanshare. Use when: user asks to find movies, TV shows, dramas, anime, or other video resources on aliyun drive (alipan). NOT for: direct file downloads, non-Chinese content, or other cloud drive services."
metadata: { "openclaw": { "emoji": "🎬", "requires": { "bins": ["gh"] } } }
---

# Aliyun Drive Resource Search

Search Chinese movie/TV show resources with Aliyun Drive (alipan) share links from the GitHub repository `acoooder/aliyunpanshare`.

## When to Use

- User asks to search for movies, TV shows, dramas, anime, or video resources
- User mentions aliyun drive, alipan, or Chinese cloud drive resources
- User wants share links for specific titles

## How to Search

Run the search script with the user's keyword:

```bash
bash skills/aliyunpan/scripts/search.sh "keyword"
```

The script will:
1. Use GitHub Code Search to find matching files in `acoooder/aliyunpanshare`
2. Fetch file contents and parse Markdown tables
3. Filter to only show Aliyun Drive links (`alipan.com` and `aliyundrive.com`)
4. Output results as a formatted table

## Output Format

Results are displayed as a Markdown table with columns:
- Resource name
- Share link (Aliyun Drive only)
- Publish time

## Notes

- Requires `gh` CLI to be installed and authenticated
- Only returns Aliyun Drive links (filters out Quark and other cloud drives)
- Search is case-insensitive for the keyword matching
- If no results are found, suggest the user try different keywords or check the repo directly
- The source repo is updated frequently with new resources
