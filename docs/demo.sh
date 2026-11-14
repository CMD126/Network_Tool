#!/usr/bin/env bash
# docs/demo.sh — record the README demo from real runs of networktool.sh.
#
# Every command targets this machine only (127.0.0.1 and a throwaway local
# HTTP server), except the last one, which shows the tool *refusing* to scan
# a public address; that refusal happens before any packet is sent.
#
# Usage:  bash docs/demo.sh > docs/demo.txt
#         python3 docs/render_svg.py docs/demo.txt docs/demo.svg
# Needs:  nmap, ping, curl, python3 (for the local HTTP server), jq
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill "$SERVER_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
export XDG_CONFIG_HOME="$WORK/xdg"   # don't touch the real config/history

PORT=8080
echo "hello" > "$WORK/index.html"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1

# run "<command line>": print it like a prompt, then run it from the repo
# root. The command lines are fixed strings in this file (some contain a
# pipe), hence eval on a single string.
run() {
    printf '$ %s\n' "$1"
    (cd "$ROOT" && eval "$1") 2>&1
    echo
}

run "./networktool.sh --ping 127.0.0.1 --count 3 --quiet"
run "./networktool.sh --port-scan 127.0.0.1 --ports 22,80,443,8000-8100 --quiet"
run "./networktool.sh --http http://127.0.0.1:$PORT --json | jq ."
run "./networktool.sh --ping 'example.com;id'"
run "./networktool.sh --port-scan 8.8.8.8"
