#!/usr/bin/env bash
# Upload a recording or screenshot to GitHub and add it to a PR description.
# Usage: attach-to-pr.sh FILE [PR-number-or-URL] [caption]
# PR defaults to the current branch's PR. The media goes under the PR's
# "## Recording" heading (replacing its placeholder comment), or is appended.
set -euo pipefail

FILE="${1:?usage: attach-to-pr.sh FILE [PR] [caption]}"
PR="${2:-}"
CAPTION="${3:-Simulator recording}"
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 1; }

NAME="$(basename -- "$FILE")"
case "$NAME" in
*.gif) MIME=image/gif ;;
*.png) MIME=image/png ;;
*.mp4) MIME=video/mp4 ;;
*.mov) MIME=video/quicktime ;;
*) echo "unsupported type: $NAME" >&2; exit 1 ;;
esac

if [ -n "$PR" ]; then
	TARGET="$(gh pr view "$PR" --json url -q .url)"
else
	TARGET="$(gh pr view --json url -q .url)"
fi
case "$TARGET" in https://*/pull/*) ;; *) echo "could not resolve PR: $TARGET" >&2; exit 1 ;; esac
REPO="$(printf '%s' "$TARGET" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')"

REPO_ID="$(gh api "repos/$REPO" --jq .id)" || { echo "repo lookup failed" >&2; exit 1; }
case "$REPO_ID" in '' | *[!0-9]*) echo "no repository_id for $REPO" >&2; exit 1 ;; esac

URL="$(curl --fail-with-body -sS -X POST \
	"https://uploads.github.com/user-attachments/assets" \
	--url-query "name=$NAME" \
	--url-query "content_type=$MIME" \
	--url-query "repository_id=$REPO_ID" \
	-H "Content-Type: application/octet-stream" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	-H "Authorization: Bearer $(gh auth token)" \
	--data-binary "@$FILE" | jq -r .url)"
case "$URL" in https://*) ;; *) echo "upload failed: $URL" >&2; exit 1 ;; esac

case "$MIME" in
image/*) EMBED="![$CAPTION]($URL)" ;;
*) EMBED="$CAPTION:"$'\n\n'"$URL" ;;
esac

BODY="$(gh pr view "$TARGET" --json body -q .body)"
NEW="$(EMBED="$EMBED" python3 -c '
import os, re, sys
body, embed = sys.stdin.read(), os.environ["EMBED"]
placeholder = re.compile(r"<!--[^>]*[Rr]ecording[^>]*-->")
m = re.search(r"^## Recording[^\n]*\n", body, re.M)
if m:
    rest = body[m.end():]
    nxt = re.search(r"^## ", rest, re.M)
    end = m.end() + (nxt.start() if nxt else len(rest))
    section = placeholder.sub("", body[m.end():end]).strip()
    section = (section + "\n\n" if section else "") + embed
    body = body[:m.end()] + "\n" + section + "\n\n" + body[end:].lstrip("\n")
else:
    body = body.rstrip() + "\n\n## Recording\n\n" + embed + "\n"
sys.stdout.write(body)
' <<<"$BODY")"
printf '%s\n' "$NEW" | gh pr edit "$TARGET" --body-file - >/dev/null
echo "attached $URL to $TARGET"
