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
  install            install missing dependencies (mpv, yt-dlp)
EOF
}

# --- dependencies -------------------------------------------------------------

# `install` may put a current yt-dlp here without root; prefer it over an older distro package.
BIN_DIR="$HOME/.local/bin"
export PATH="$BIN_DIR:$PATH"

missing_deps() {
  command -v mpv >/dev/null || echo mpv
  command -v yt-dlp >/dev/null || echo yt-dlp
}

need_deps() {
  local missing; missing=$(missing_deps | xargs)
  if [ -n "$missing" ]; then
    echo "✗ missing: $missing" >&2
    echo "  run: $0 install" >&2
    exit 2
  fi
}

# True when we can run as root without prompting (sudo would otherwise ask for a password).
can_root() { [ "$(id -u)" = 0 ] || { command -v sudo >/dev/null && sudo -n true 2>/dev/null; }; }
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi; }

pkg_install_cmd() {
  if command -v apt-get >/dev/null; then echo "apt-get install -y -qq $*"
  elif command -v dnf >/dev/null; then echo "dnf install -y $*"
  elif command -v pacman >/dev/null; then echo "pacman -S --noconfirm $*"
  elif command -v zypper >/dev/null; then echo "zypper install -y $*"
  elif command -v apk >/dev/null; then echo "apk add $*"
  fi
}

# Standalone yt-dlp release binary into ~/.local/bin (no root, always current).
install_ytdlp_binary() {
  local asset
  case "$(uname -s)-$(uname -m)" in
    Darwin-*) asset=yt-dlp_macos ;;
    Linux-x86_64) asset=yt-dlp_linux ;;
    Linux-aarch64|Linux-arm64) asset=yt-dlp_linux_aarch64 ;;
    *) command -v python3 >/dev/null && asset=yt-dlp || return 1 ;;
  esac
  local url="https://github.com/yt-dlp/yt-dlp/releases/latest/download/$asset" tmp="$BIN_DIR/yt-dlp.tmp"
  mkdir -p "$BIN_DIR"
  echo "→ downloading $asset to $BIN_DIR/yt-dlp"
  if command -v curl >/dev/null; then curl -fsSL "$url" -o "$tmp" 2>/dev/null
  elif command -v wget >/dev/null; then wget -qO "$tmp" "$url"
  else return 1; fi || { rm -f "$tmp"; return 1; }
  chmod +x "$tmp" && mv "$tmp" "$BIN_DIR/yt-dlp" && "$BIN_DIR/yt-dlp" --version >/dev/null 2>&1 \
    || { rm -f "$BIN_DIR/yt-dlp"; return 1; }
}

# Exit 0 when everything is installed; exit 3 with the exact command when the user must act.
install_deps() {
  local missing; missing=$(missing_deps | xargs)
  [ -z "$missing" ] && { echo "✓ already installed"; return 0; }

  if command -v brew >/dev/null; then
    echo "→ brew install $missing"
    brew install $missing
  else
    if [[ " $missing " == *" yt-dlp "* ]]; then
      { command -v pipx >/dev/null && pipx install yt-dlp; } || install_ytdlp_binary \
        || echo "  (download failed, falling back to the package manager)"
    fi
    missing=$(missing_deps | xargs)
    if [ -n "$missing" ]; then
      local cmd; cmd=$(pkg_install_cmd $missing)
      if [ "$(uname -s)" = Darwin ]; then
        echo "✗ $missing needs Homebrew: install it from https://brew.sh, then run: brew install $missing" >&2; exit 3
      elif [ -z "$cmd" ]; then
        echo "✗ no supported package manager; install manually: $missing (https://mpv.io/installation/)" >&2; exit 3
      fi
      can_root || { echo "✗ needs your password, run: sudo $cmd" >&2; exit 3; }
      echo "→ $cmd"
      [ "${cmd%% *}" = apt-get ] && { as_root apt-get update -qq >"$LOG" 2>&1 || true; }
      # shellcheck disable=SC2086
      as_root env DEBIAN_FRONTEND=noninteractive $cmd >>"$LOG" 2>&1 \
        || { echo "✗ '$cmd' failed:" >&2; tail -5 "$LOG" >&2; exit 3; }
    fi
  fi

  missing=$(missing_deps | xargs)
  [ -z "$missing" ] || { echo "✗ still missing: $missing" >&2; exit 3; }
  echo "✓ installed: mpv, yt-dlp"
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

# URLs pass through. Queries resolve to the first *video* result: the top hit is often a
# channel (e.g. an artist name), which mpv would expand into hundreds of queued videos.
source_for() {
  case "$1" in http://*|https://*) echo "$1"; return ;; esac
  local url
  url=$(yt-dlp --no-warnings --flat-playlist --print "%(ie_key)s %(url)s" "ytsearch5:$1" 2>/dev/null \
    | awk '$1 == "Youtube" { print $2; exit }') || true
  echo "${url:-ytdl://ytsearch1:$1}"
}

title() { ipc '{"command":["get_property","media-title"]}' | data_str; }

# Wait until mpv has real metadata (media-title falls back to the filename until then).
wait_title() {
  local t f
  for _ in $(seq 1 40); do
    t=$(title); f=$(ipc '{"command":["get_property","filename"]}' | data_str)
    if [ -n "$t" ] && [ "$t" != "$f" ] && [[ "$t" != ytsearch* ]]; then echo "$t"; return 0; fi
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
  install)
    install_deps ;;
  *) usage; exit 1 ;;
esac
