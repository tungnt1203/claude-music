#!/usr/bin/env bash
# claude-music — play YouTube audio in the background via mpv, controlled over mpv's IPC socket.
# https://github.com/tungnt1203/claude-music
set -euo pipefail

SOCK="${CLAUDE_MUSIC_SOCKET:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/claude-music-$(id -u).sock}"
LOG="${SOCK%.sock}.log"

usage() {
  cat <<'EOF'
usage: music.sh <command> [args]
  play <query|url>   replace current playback with a YouTube search result or URL
  add  <query|url>   append to the queue (starts playback if idle)
  pause              toggle pause / resume
  next               skip to the next track in the queue
  vol [0-100]        set volume, or print it
  now                print the current track
  stop               stop playback and quit mpv
  doctor             check dependencies
EOF
}

# --- dependencies -------------------------------------------------------------

install_hint() {
  if command -v brew >/dev/null; then echo "brew install $*"
  elif command -v apt-get >/dev/null; then echo "sudo apt-get install -y $*"
  elif command -v dnf >/dev/null; then echo "sudo dnf install -y $*"
  elif command -v pacman >/dev/null; then echo "sudo pacman -S $*"
  else echo "install: $*"; fi
}

need_deps() {
  local missing=()
  command -v mpv >/dev/null || missing+=(mpv)
  command -v yt-dlp >/dev/null || missing+=(yt-dlp)
  if [ ${#missing[@]} -gt 0 ]; then
    echo "✗ missing: ${missing[*]}" >&2
    echo "  run: $(install_hint "${missing[@]}")" >&2
    exit 2
  fi
}

# --- IPC ----------------------------------------------------------------------

# Send one JSON command to mpv and print the reply. Never fails (returns empty on error).
ipc() {
  [ -S "$SOCK" ] || return 0
  if command -v socat >/dev/null; then
    printf '%s\n' "$1" | socat -t1 - "UNIX-CONNECT:$SOCK" 2>/dev/null || true
  elif [ "$(uname)" = Darwin ]; then
    printf '%s\n' "$1" | nc -U -w 1 "$SOCK" 2>/dev/null || true
  elif command -v python3 >/dev/null; then
    python3 - "$SOCK" "$1" <<'PY' 2>/dev/null || true
import socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect(sys.argv[1])
s.sendall(sys.argv[2].encode() + b"\n")
try: print(s.recv(65536).decode().splitlines()[0])
except Exception: pass
PY
  else
    printf '%s\n' "$1" | nc -U -w 1 "$SOCK" 2>/dev/null || true
  fi
}

running() { ipc '{"command":["get_property","pid"]}' | grep -q '"error":"success"'; }

# Extract the "data" string from an mpv reply (titles may contain escaped quotes).
data_str() { sed -n 's/.*"data":"\(.*\)","request_id".*/\1/p' | sed 's/\\"/"/g; s/\\\\/\\/g'; }

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

source_for() { case "$1" in http://*|https://*) echo "$1" ;; *) echo "ytdl://ytsearch1:$1" ;; esac; }

title() { ipc '{"command":["get_property","media-title"]}' | data_str; }

# Wait until mpv resolves the search into a real title.
wait_title() {
  local t
  for _ in $(seq 1 40); do
    t=$(title)
    if [ -n "$t" ] && [[ "$t" != ytsearch* ]] && [[ "$t" != http* ]]; then echo "$t"; return 0; fi
    sleep 0.5
  done
  return 1
}

# --- commands -----------------------------------------------------------------

cmd="${1:-}"; shift || true
case "$cmd" in
  play)
    [ $# -gt 0 ] || { usage; exit 1; }
    need_deps
    running && ipc '{"command":["quit"]}' >/dev/null && sleep 0.5
    rm -f "$SOCK"
    nohup mpv --no-video --no-terminal --input-ipc-server="$SOCK" \
      --ytdl-format=bestaudio/best "$(source_for "$*")" >"$LOG" 2>&1 &
    if t=$(wait_title); then echo "▶ $t"
    elif running; then echo "▶ loading: $* (run 'now' in a few seconds)"
    else echo "✗ playback failed — see $LOG" >&2; tail -5 "$LOG" >&2; exit 1; fi ;;
  add|queue)
    [ $# -gt 0 ] || { usage; exit 1; }
    running || exec "$0" play "$@"
    ipc "{\"command\":[\"loadfile\",\"$(json_escape "$(source_for "$*")")\",\"append-play\"]}" >/dev/null
    echo "+ queued: $*" ;;
  pause|resume|toggle)
    running || { echo "⏹ nothing playing"; exit 0; }
    ipc '{"command":["cycle","pause"]}' >/dev/null
    if ipc '{"command":["get_property","pause"]}' | grep -q '"data":true'; then echo "⏸ paused"; else echo "▶ resumed"; fi ;;
  next|skip)
    running || { echo "⏹ nothing playing"; exit 0; }
    if ipc '{"command":["playlist-next","force"]}' | grep -q '"error":"success"'; then
      sleep 1; t=$(wait_title) && echo "⏭ $t" || echo "⏭"
    else echo "⏹ queue ended"; fi ;;
  vol|volume)
    running || { echo "⏹ nothing playing"; exit 0; }
    [ $# -gt 0 ] && ipc "{\"command\":[\"set_property\",\"volume\",$(( ${1%%.*} + 0 ))]}" >/dev/null
    ipc '{"command":["get_property","volume"]}' | sed -n 's/.*"data":\([0-9]*\).*/🔊 \1/p' ;;
  now|status)
    running || { echo "⏹ nothing playing"; exit 0; }
    echo "▶ $(title)" ;;
  stop)
    running && ipc '{"command":["quit"]}' >/dev/null
    rm -f "$SOCK"; echo "⏹ stopped" ;;
  doctor)
    need_deps; echo "✓ mpv $(mpv --version | head -1 | awk '{print $2}'), yt-dlp $(yt-dlp --version)" ;;
  *) usage; exit 1 ;;
esac
