#!/usr/bin/env bash
# cmusic — play YouTube audio in the background via mpv, controlled over mpv's IPC socket.
# https://github.com/tungnt1203/cmusic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCK="${CMUSIC_SOCKET:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/cmusic-$(id -u).sock}"
LOG="${SOCK%.sock}.log"

usage() {
  cat <<'EOF'
usage: music.sh <command> [args]
  play <query|url>   replace current playback with a YouTube search result or URL
  add  <query|url>   append to the queue (starts playback if idle)
  queue              list the queue (alias: list)
  remove <n>         remove track n from the queue
  clear              clear the queue, keeping the current track
  pause              toggle pause / resume
  next               skip to the next track in the queue
  prev               previous track (restarts the current one if past 5s)
  seek <+s|-s|m:ss>  seek relative (+30, -10) or absolute (1:30, 90)
  replay             restart the current track
  vol [0-100]        set volume, or print it
  now [--line]       print the current track (--line: one instant line for a statusline)
  statusline         print the statusLine setting that shows the current track
  stop               stop playback and quit mpv
  doctor             check dependencies
  install            install missing dependencies (mpv, yt-dlp)
EOF
}

# --- dependencies -------------------------------------------------------------

# pipx installs here; prefer it over an older distro package.
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

# Exit 0 when everything is installed; exit 3 with the exact command when the user must act.
install_deps() {
  local missing; missing=$(missing_deps | xargs)
  [ -z "$missing" ] && { echo "✓ already installed"; return 0; }

  if command -v brew >/dev/null; then
    echo "→ brew install $missing"
    brew install $missing
  else
    # pipx tracks upstream yt-dlp; distro packages can lag behind YouTube changes.
    if [[ " $missing " == *" yt-dlp "* ]] && command -v pipx >/dev/null; then
      echo "→ pipx install yt-dlp"
      pipx install yt-dlp >"$LOG" 2>&1 || true
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

# Check the process, not the socket: mpv can be slow to answer IPC while it opens a stream.
running() {
  if command -v pgrep >/dev/null; then pgrep -f -- "--input-ipc-server=$SOCK" >/dev/null 2>&1
  else ipc '{"command":["get_property","pid"]}' | grep -q '"error":"success"'; fi
}

# Extract the "data" string from an mpv reply and undo JSON escapes (\\ first, via a placeholder).
data_str() {
  sed -n 's/.*"data":"\(.*\)","request_id".*/\1/p' | awk '{
    gsub(/\\\\/, "\001"); gsub(/\\"/, "\""); gsub(/\\n/, "\n"); gsub(/\\t/, "\t"); gsub(/\\\//, "/")
    gsub(/\001/, "\\"); print }'
}

# Expand an mpv property template (e.g. '${pause}|${=time-pos}') in one round trip.
expand() { ipc "{\"command\":[\"expand-text\",\"$(json_escape "$1")\"]}" | data_str; }

# seconds -> m:ss (h:mm:ss past an hour)
mmss() { awk -v t="${1:-0}" 'BEGIN { t = int(t); h = int(t / 3600); m = int(t % 3600 / 60)
  if (h) printf "%d:%02d:%02d", h, m, t % 60; else printf "%d:%02d", m, t % 60 }'; }

# m:ss / h:mm:ss / plain seconds -> seconds
to_secs() { awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }' <<<"$1"; }

json_escape() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; printf '%s' "${s//$'\t'/\\t}"; }

# Print "<url>\t<title>". URLs pass through (titled by the URL itself). Queries resolve to the
# first *video* result: the top hit is often a channel (e.g. an artist name), which mpv would
# expand into hundreds of queued videos.
source_for() {
  case "$1" in http://*|https://*) printf '%s\t%s\n' "$1" "$1"; return ;; esac
  local hit
  hit=$(yt-dlp --no-warnings --flat-playlist --print "%(ie_key)s %(url)s %(title)s" "ytsearch5:$1" 2>/dev/null \
    | awk '$1 == "Youtube" { url = $2; sub(/^[^ ]+ [^ ]+ /, ""); print url "\t" $0; exit }') || true
  if [ -n "$hit" ]; then echo "$hit"; else printf 'ytdl://ytsearch1:%s\t%s\n' "$1" "$1"; fi
}

# Queue a source with its title, so `queue` can name tracks before they load.
append() {
  local src; src=$(source_for "$1")
  ipc "{\"command\":[\"loadlist\",\"$(json_escape "memory://#EXTM3U
#EXTINF:0,${src#*$'\t'}
${src%%$'\t'*}")\",\"append-play\"]}" >/dev/null
  echo "${src#*$'\t'}"
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

# True once cmusic.lua is running inside mpv (needs Lua and mpv >= 0.36 for user-data).
lua_ready() { [ "$(expand '${user-data/cmusic/ready:no}')" = yes ]; }

# Replace any running player with a new one playing <source>, keeping the volume.
# usage: start <label> <source> [extra mpv args...]
start() {
  local label=$1 src=$2 vol=100; shift 2
  if running; then
    vol=$(expand '${user-data/cmusic/level:${volume}}'); vol=${vol%%.*}
    ipc '{"command":["quit"]}' >/dev/null; sleep 0.5
  fi
  rm -f "$SOCK"
  nohup mpv --no-video --no-terminal --input-ipc-server="$SOCK" --script="$SCRIPT_DIR/cmusic.lua" \
    --volume="${vol:-100}" --ytdl-format=bestaudio/best "$@" "$src" >"$LOG" 2>&1 &
  local t
  if t=$(wait_title); then echo "▶ $t"
  elif running; then echo "▶ loading: $label (run 'now' in a few seconds)"
  else echo "✗ playback failed — see $LOG" >&2; tail -5 "$LOG" >&2; exit 1; fi
}

# --- commands -----------------------------------------------------------------

cmd="${1:-}"; shift || true
case "$cmd" in
  play)
    [ $# -gt 0 ] || { usage; exit 1; }
    need_deps
    start "$*" "$(source_for "$*" | cut -f1)" ;;
  add)
    [ $# -gt 0 ] || { usage; exit 1; }
    running || exec "$0" play "$@"
    echo "+ queued: $(append "$*")" ;;
  queue|list)
    [ $# -gt 0 ] && exec "$0" add "$@"
    running || { echo "⏹ nothing playing"; exit 0; }
    n=$(expand '${playlist-count}|${playlist-pos}'); count=${n%|*}; pos=${n#*|}
    # Long playlists: show from the current track on, 20 at most.
    first=0; [ "$count" -gt 20 ] && first=$pos
    last=$(( first + 20 < count ? first + 20 : count ))
    tpl=""
    for (( i = first; i < last; i++ )); do tpl+="\${playlist/$i/title:\${playlist/$i/filename}}"$'\n'; done
    i=$first
    while IFS= read -r line; do
      [ "$i" = "$pos" ] && line=$(title)
      if [ "$i" = "$pos" ]; then printf '▶ %d. %s\n' $(( i + 1 )) "$line"; else printf '  %d. %s\n' $(( i + 1 )) "$line"; fi
      i=$(( i + 1 ))
    done < <(expand "${tpl%$'\n'}" | sed 's|^ytdl://ytsearch1:||')
    [ "$last" -lt "$count" ] && echo "  … $(( count - last )) more"
    true ;;
  remove|rm)
    running || { echo "⏹ nothing playing"; exit 0; }
    [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] || { echo "usage: remove <n>   (n from 'queue')" >&2; exit 1; }
    t=$(expand "\${playlist/$(( $1 - 1 ))/title:\${playlist/$(( $1 - 1 ))/filename}}")
    if ipc "{\"command\":[\"playlist-remove\",$(( $1 - 1 ))]}" | grep -q '"error":"success"'; then echo "− removed: $t"
    else echo "✗ no track $1 in the queue" >&2; exit 1; fi ;;
  clear)
    running || { echo "⏹ nothing playing"; exit 0; }
    ipc '{"command":["playlist-clear"]}' >/dev/null; echo "✓ queue cleared (current track keeps playing)" ;;
  pause|resume|toggle)
    running || { echo "⏹ nothing playing"; exit 0; }
    ipc '{"command":["cycle","pause"]}' >/dev/null
    if ipc '{"command":["get_property","pause"]}' | grep -q '"data":true'; then echo "⏸ paused"; else echo "▶ resumed"; fi ;;
  next|skip)
    running || { echo "⏹ nothing playing"; exit 0; }
    # On the last track mpv quits (no --idle), which ends playback.
    ipc '{"command":["playlist-next","force"]}' >/dev/null
    sleep 1
    if running; then t=$(wait_title) && echo "⏭ $t" || echo "⏭ loading…"; else rm -f "$SOCK"; echo "⏹ queue ended"; fi ;;
  prev|previous|back)
    running || { echo "⏹ nothing playing"; exit 0; }
    pos=$(expand '${=time-pos:0}|${=playlist-pos:0}')
    if [ "${pos#*|}" -gt 0 ] && awk -v t="${pos%|*}" 'BEGIN { exit !(t < 5) }'; then
      ipc '{"command":["playlist-prev","force"]}' >/dev/null; sleep 1
      t=$(wait_title) && echo "⏮ $t" || echo "⏮ loading…"
    else
      ipc '{"command":["seek",0,"absolute"]}' >/dev/null; echo "⏮ $(title)"
    fi ;;
  seek)
    running || { echo "⏹ nothing playing"; exit 0; }
    case "${1:-}" in
      [+-][0-9]*) mode=relative; secs="${1:0:1}$(to_secs "${1:1}")" ;;
      [0-9]*) mode=absolute; secs=$(to_secs "$1") ;;
      *) echo "usage: seek +30 | -10 | 1:30" >&2; exit 1 ;;
    esac
    # A track that is still opening rejects seeks, so retry for a few seconds.
    for _ in $(seq 1 20); do
      ipc "{\"command\":[\"seek\",\"$secs\",\"$mode\"]}" | grep -q '"error":"success"' && break
      sleep 0.3
    done
    t=$(expand '${=time-pos:0}|${=duration:0}'); echo "⏩ $(mmss "${t%|*}")/$(mmss "${t#*|}")" ;;
  replay|restart)
    running || { echo "⏹ nothing playing"; exit 0; }
    ipc '{"command":["seek",0,"absolute"]}' >/dev/null; echo "🔁 $(title)" ;;
  vol|volume)
    running || { echo "⏹ nothing playing"; exit 0; }
    if [ $# -gt 0 ]; then
      v=$(( ${1%%.*} + 0 ))
      # cmusic.lua owns the volume during fades; set it directly too in case Lua isn't there.
      ipc "{\"command\":[\"script-message\",\"cmusic-volume\",\"$v\"]}" >/dev/null
      ipc "{\"command\":[\"set_property\",\"volume\",$v]}" >/dev/null
    fi
    v=$(expand '${user-data/cmusic/level:${volume}}'); echo "🔊 ${v%%.*}" ;;
  now|status)
    if [ "${1:-}" = --line ]; then
      # Statusline: one IPC round trip, no waiting, and silence when nothing plays.
      IFS=$'\t' read -r t f p pos dur < <(expand $'${media-title}\t${filename}\t${pause}\t${=time-pos:0}\t${=duration:}') || exit 0
      [ -n "${t:-}" ] || exit 0
      icon="♪"; [ "$p" = yes ] && icon="⏸"
      if [ "$t" = "$f" ] || [[ "$t" == ytsearch* ]]; then echo "$icon loading…"; exit 0; fi
      [ "${#t}" -gt 40 ] && t="${t:0:39}…"
      if [ -n "$dur" ]; then echo "$icon $t · $(mmss "$pos")/$(mmss "$dur")"; else echo "$icon $t · $(mmss "$pos")"; fi
      exit 0
    fi
    running || { echo "⏹ nothing playing"; exit 0; }
    t=$(wait_title) && echo "▶ $t" || echo "▶ loading…" ;;
  stop)
    if running && lua_ready; then
      # cmusic.lua fades out and quits; wait for it, then make sure.
      ipc '{"command":["script-message","cmusic-stop"]}' >/dev/null
      for _ in $(seq 1 15); do running || break; sleep 0.1; done
    fi
    running && ipc '{"command":["quit"]}' >/dev/null
    rm -f "$SOCK"; echo "⏹ stopped" ;;
  statusline)
    # Plugin installs live under a versioned cache dir, so resolve the newest one at run time.
    case "$SCRIPT_DIR" in
      */plugins/cache/*) cmd='"$(ls -td ~/.claude/plugins/cache/cmusic/cmusic/*/ | head -1)bin/cmusic" now --line' ;;
      *) cmd="\"$SCRIPT_DIR/music.sh\" now --line" ;;
    esac
    cat <<EOF
Add to ~/.claude/settings.json:
  "statusLine": { "type": "command", "command": "$(json_escape "$cmd")" }
Already have a statusline? Append the output of: $cmd
EOF
    ;;
  doctor)
    need_deps; echo "✓ mpv $(mpv --version | head -1 | awk '{print $2}'), yt-dlp $(yt-dlp --version)" ;;
  install)
    install_deps ;;
  *) usage; exit 1 ;;
esac
