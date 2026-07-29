#!/usr/bin/env bash
# Rung 1 of the fetch-403 skill: curl, retry with a browser UA, render to markdown.
# Usage: fetch403.sh URL [OUTFILE.md]   (default outfile: /tmp/page.md)
set -euo pipefail

url=${1:?usage: fetch403.sh URL [OUTFILE.md]}
out=${2:-/tmp/page.md}
html=$(mktemp)
jar=$(mktemp)
trap 'rm -f "$html" "$jar"' EXIT

UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

# --retry covers transient failures (5xx, timeouts, dropped connections) only;
# a 403 is a decision, not a hiccup, so it falls through to the UA retry below.
# The cookie jar is shared across both attempts so set-cookie-then-redirect
# flows land on the real page instead of bouncing.
fetch() {
  curl -sL --compressed -w '%{http_code}' \
    --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 60 \
    -c "$jar" -b "$jar" "$@" "$url" -o "$html"
}

code=$(fetch) || true
if [ "$code" != 200 ]; then
  echo "[$code] bare curl refused, retrying with browser UA" >&2
  code=$(fetch -A "$UA") || true
fi

if [ "$code" != 200 ]; then
  echo "[$code] blocked — try the machine-readable endpoint (llms.txt, raw.githubusercontent, JSON/RSS) or search. Do not answer from memory." >&2
  exit 1
fi

if grep -qi 'Just a moment\|cf-browser-verification' "$html"; then
  echo "bot-check interstitial, not content — this site does not want automated reads; ask the user to paste the page." >&2
  exit 1
fi

# Only the Python html2text is accepted — the GNU binary of the same name takes
# entirely different flags and would fail on --ignore-images.
if python3 -c 'import html2text' 2>/dev/null; then
  python3 -m html2text --ignore-images --ignore-links "$html" > "$out"
elif command -v uvx >/dev/null; then
  uvx --from html2text html2text --ignore-images --ignore-links "$html" > "$out"
else
  echo "no html2text and no uvx to fetch one — writing raw HTML instead" >&2
  cp "$html" "$out"
fi
echo "$out ($(wc -l < "$out") lines)" >&2
grep -n '^#\{1,3\} ' "$out" || true
