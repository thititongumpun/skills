#!/usr/bin/env bash
# Safety net for whiteboard's excalidraw canvas.
#
# The canvas is spawned detached with no idle timeout and no owner watchdog,
# so it outlives Claude Code. If a session ends before whiteboard reaches its
# Phase 6 shutdown — interrupted, out of context, Ctrl-C — an unauthenticated
# server with wildcard CORS keeps listening indefinitely. This closes that.
#
# ponytail: stops the shared canvas, so a second concurrent session loses it.
# Upstream has no multi-session isolation anyway (#80); revisit if that lands.
set -u

URL=${EXPRESS_SERVER_URL:-http://127.0.0.1:3000}

# Fast path: nothing listening, nothing to do (~10ms, the usual case).
curl -s --max-time 1 -o /dev/null "$URL/health" 2>/dev/null || exit 0

npx -y mcp-excalidraw-server stop >/dev/null 2>&1 || true
exit 0
