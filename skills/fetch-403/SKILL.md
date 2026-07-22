---
name: fetch-403
description: Recover a web page after the built-in fetcher (WebFetch) is refused — 403 Forbidden, empty body, or a "Just a moment…" bot-check interstitial instead of content. Use when a documentation page, blog post, or reference URL won't load through the normal fetch tool and the content is still needed. Covers the curl fallback, machine-readable endpoints, and the rule against silently answering from memory when a source stays blocked.
---

# Fetching a page that returned 403

A 403 from the built-in fetcher usually means *that fetcher* is unwelcome, not
that the site blocks automation. `debezium.io` is the reference case: WebFetch
gets 403, bare `curl` gets 200. WebFetch's 403 message may suggest the page
needs authentication — try rung 1 before believing that; public docs pages
403 the fetcher's UA all the time.

Work down this list. Stop at the first rung that returns content.

## 1. curl

```bash
curl -sL -w '\n[%{http_code}]\n' URL -o /tmp/page.html
```

If that 403s, retry once with a browser User-Agent — it fixes plain UA
filtering:

```bash
curl -sL -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36' URL -o /tmp/page.html
```

Read it as markdown rather than raw HTML:

```bash
uvx --from html2text html2text --ignore-images --ignore-links /tmp/page.html > /tmp/page.md
grep -n '^#\{1,3\} ' /tmp/page.md   # headings first, then read only the sections you need
```

A docs page is often 3-4k lines of markdown. Pull the sections you need with
`sed -n 'START,ENDp'`; don't read the whole file into context.

## 2. The machine-readable endpoint

Many sites publish something built for programmatic reads. Prefer it — it is
smaller, stabler, and never fights you:

- `llms.txt` at the doc root (Confluent, Cloudflare, and a growing set)
- `raw.githubusercontent.com` for anything in a repo; `gh api` for private ones
- a JSON API, an RSS feed, or the `.md` source behind a rendered page

## 3. Search instead of fetch

Search snippets, a mirror, or the project's own repo often carry the answer.
The goal is the content, not that specific URL.

## 4. Still blocked? Say so.

Report that the source was blocked and name what you tried. **Never quietly
answer from training memory instead** — on a retrieval-first task that is the
exact failure the retrieval was there to prevent, and it is invisible to the
user. An unavailable source is a fact worth one sentence; a fabricated answer
that looks sourced is not recoverable.

## What not to reach for

Headless-browser scraping (Playwright/Puppeteer) does **not** clear this bar.
Tested 2026-07 against a live Cloudflare challenge: vanilla Playwright returns
an empty body, headless *and* headed, and costs ~646MB of browser download to
do it. Worse, it exits 0 with empty output — a silent failure that reads as
"the page was empty." Passing a real bot check needs stealth/fingerprint
evasion, which is out of scope here. If a site fights that hard, it does not
want automated reads: ask the user to paste the page.
