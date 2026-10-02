#!/usr/bin/env bash
# cmusic — play YouTube audio in the background via mpv, controlled over mpv's IPC socket.
# https://github.com/tungnt1203/cmusic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Only favorites, saved playlists and opt-in history (CMUSIC_HISTORY=1) are written here.
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cmusic"
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
  now --json [--lrc] track state as JSON, for the lyrics pane
  now [--line [--lyrics]]
                     print the current track (--line: instant, for a statusline;
                     --lyrics: add the line being sung, fetched from lrclib.net)
  statusline         print the statusLine setting that shows the current track
  stop               stop playback and quit mpv (fades out)
  stop in <30m|1h>   sleep timer; also: stop after this (end of track), stop cancel
  radio [on|off]     keep playing related songs when the queue runs out
  radio <query|url>  start a radio from a song
  lyrics [--line]    lyrics of the current track from lrclib.net (--line: the line being sung)
  focus [min] [break <min>] [query]
                     Pomodoro: focus music for 25 min, then a 5 min break
  fav / unfav        save / remove the current track in your favorites
  favs               play your favorites, shuffled
  save <name>        save the queue as a named playlist
  load <name>        play a saved playlist; playlists lists them
  history [n]        recently played (opt-in: CMUSIC_HISTORY=1)
  forget             delete favorites, playlists and history
  hook <event>       for Claude Code hooks (notify, prompt, tool, stop);
                     opt-in via CMUSIC_DUCK=1 and CMUSIC_CELEBRATE=1
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
    gsub(/\\\\/, "\001"); gsub(/\\"/, "\""); gsub(/\\n/, "\n"); gsub(/\\t/, "\t"); gsub(/\\\//, "/"); gsub(/\\u001f/, "\037")
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

# Print "<url>\t<title>". URLs pass through untitled (mpv names them once they load). Queries resolve to the
# first *video* result: the top hit is often a channel (e.g. an artist name), which mpv would
# expand into hundreds of queued videos.
source_for() {
  case "$1" in http://*|https://*) printf '%s\t\n' "$1"; return ;; esac
  local hit
  hit=$(yt-dlp --no-warnings --flat-playlist --print "%(ie_key)s %(url)s %(title)s" "ytsearch5:$1" 2>/dev/null \
    | awk '$1 == "Youtube" { url = $2; sub(/^[^ ]+ [^ ]+ /, ""); print url "\t" $0; exit }') || true
  if [ -n "$hit" ]; then echo "$hit"; else printf 'ytdl://ytsearch1:%s\t%s\n' "$1" "$1"; fi
}

# Queue a source with its title, so `queue` can name tracks before they load. Prints the title.
append() {
  local src; src=$(source_for "$1")
  if [ -z "${src#*$'\t'}" ]; then
    ipc "{\"command\":[\"loadfile\",\"$(json_escape "${src%%$'\t'*}")\",\"append-play\"]}" >/dev/null
    echo "$1"; return
  fi
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

# 30m / 1h30m / 90s / 45 (minutes) -> seconds
dur_secs() {
  local s=$1 total=0
  [[ $s =~ ^[0-9]+$ ]] && { echo $(( s * 60 )); return 0; }
  while [[ $s =~ ^([0-9]+)(h|m|s|min)(.*)$ ]]; do
    case ${BASH_REMATCH[2]} in h) total=$(( total + BASH_REMATCH[1] * 3600 )) ;; s) total=$(( total + BASH_REMATCH[1] )) ;;
      *) total=$(( total + BASH_REMATCH[1] * 60 )) ;; esac
    s=${BASH_REMATCH[3]}
  done
  [ -z "$s" ] && [ "$total" -gt 0 ] && echo "$total"
}

# The running timer as " · ⏲ 12:34 left", or nothing.
timer_text() {
  local t; t=$(expand '${user-data/cmusic/timer:}')
  case "$t" in
    "") ;;
    *"|track") printf ' · %s after this track' "${t%%|*}" ;;
    *) printf ' · %s %s left' "${t%%|*}" "$(mmss $(( ${t#*|} - $(date +%s) )))" ;;
  esac
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
  if [ "${CMUSIC_HISTORY:-0}" = 1 ]; then
    mkdir -p "$DATA_DIR"; set -- "$@" --script-opts-append=cmusic-history="$DATA_DIR/history.tsv"
  fi
  nohup mpv --no-video --no-terminal --input-ipc-server="$SOCK" --script="$SCRIPT_DIR/cmusic.lua" \
    --volume="${vol:-100}" --ytdl-format=bestaudio/best "$@" "$src" >"$LOG" 2>&1 &
  local t
  if t=$(wait_title); then echo "▶ $t"
  elif running; then echo "▶ loading: $label (run 'now' in a few seconds)"
  else echo "✗ playback failed — see $LOG" >&2; tail -5 "$LOG" >&2; exit 1; fi
}

# Write the queue as "<url>\t<title>" lines (the current track by its loaded title).
queue_tsv() {
  local n count pos tpl="" i
  n=$(expand '${playlist-count}|${playlist-pos}'); count=${n%|*}; pos=${n#*|}
  for (( i = 0; i < count; i++ )); do tpl+="\${playlist/$i/filename}"$'\t'"\${playlist/$i/title:}"$'\n'; done
  i=0
  expand "${tpl%$'\n'}" | while IFS=$'\t' read -r url t; do
    [ "$i" = "$pos" ] && t=$(title)
    printf '%s\t%s\n' "$url" "${t:-$url}"; i=$(( i + 1 ))
  done
}

# "<url>\t<title>" lines -> m3u
to_m3u() { echo "#EXTM3U"; while IFS=$'\t' read -r url t; do printf '#EXTINF:0,%s\n%s\n' "$t" "$url"; done; }

# Tell the user once where their data lives.
first_write() { [ -e "$DATA_DIR" ] || { mkdir -p "$DATA_DIR"; echo "  (saved on disk in $DATA_DIR; 'forget' deletes it)"; }; }

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
    if [ "${1:-}" = --json ]; then
      # For the lyrics pane: one object per call, {} when nothing plays. --lrc adds the
      # synced lyrics. Like --line --lyrics, it starts a lyrics lookup for a new track.
      fields='${media-title}\x1f${filename}\x1f${pause}\x1f${=time-pos:0}\x1f${=duration:0}\x1f${path}\x1f${user-data/cmusic/lyrics-status:}'
      [ "${2:-}" = --lrc ] && fields+='\x1f${user-data/cmusic/lyrics-lrc:}'
      IFS=$'\x1f' read -r -d '' t f p pos dur path lst lrc < <(expand "$(printf "$fields")") || true
      [ -n "${t:-}" ] || { echo "{}"; exit 0; }
      lst=${lst%$'\n'} lrc=${lrc%$'\n'}
      [ -z "$lst" ] && ipc '{"command":["script-message","cmusic-lyrics"]}' >/dev/null
      loading=false; { [ "$t" = "$f" ] || [[ "$t" == ytsearch* ]]; } && loading=true
      printf '{"title":"%s","loading":%s,"paused":%s,"pos":%s,"duration":%s,"path":"%s","lyrics":"%s"' \
        "$(json_escape "$t")" "$loading" "$([ "$p" = yes ] && echo true || echo false)" "${pos:-0}" "${dur:-0}" \
        "$(json_escape "$path")" "${lst:-loading}"
      [ "${2:-}" = --lrc ] && printf ',"lrc":"%s"' "$(json_escape "$lrc")"
      echo "}"; exit 0
    fi
    if [ "${1:-}" = --line ]; then
      # Statusline: one IPC round trip, no waiting, and silence when nothing plays.
      # Fields are split on \x1f: a tab separator would merge empty fields.
      IFS=$'\x1f' read -r t f p pos dur lst lline < <(expand $'${media-title}\x1f${filename}\x1f${pause}\x1f${=time-pos:0}\x1f${=duration:}\x1f${user-data/cmusic/lyrics-status:}\x1f${user-data/cmusic/lyrics-line:}') || exit 0
      [ -n "${t:-}" ] || exit 0
      icon="♪"; [ "$p" = yes ] && icon="⏸"
      if [ "$t" = "$f" ] || [[ "$t" == ytsearch* ]]; then echo "$icon loading…"; exit 0; fi
      [ "${#t}" -gt 40 ] && t="${t:0:39}…"
      if [ -n "$dur" ]; then echo "$icon $t · $(mmss "$pos")/$(mmss "$dur")$(timer_text)"; else echo "$icon $t · $(mmss "$pos")$(timer_text)"; fi
      if [ "${2:-}" = --lyrics ]; then
        # No lyrics for this track yet: start fetching in the background, show them next refresh.
        [ -z "$lst" ] && ipc '{"command":["script-message","cmusic-lyrics"]}' >/dev/null
        [ "${#lline}" -gt 70 ] && lline="${lline:0:69}…"
        [ "$lst" = ok ] && [ -n "$lline" ] && echo "🎤 $lline"
      fi
      exit 0
    fi
    running || { echo "⏹ nothing playing"; exit 0; }
    t=$(wait_title) && echo "▶ $t$(timer_text)" || echo "▶ loading…" ;;
  stop)
    if [ $# -gt 0 ]; then
      running || { echo "⏹ nothing playing"; exit 0; }
      lua_ready || { echo "✗ timers need mpv >= 0.36 with Lua (see: doctor)" >&2; exit 1; }
      [ "$1" = in ] && shift
      case "${1:-}" in
        after|this|track) ipc '{"command":["script-message","cmusic-sleep-after-track"]}' >/dev/null
          echo "⏲ stopping after this track" ;;
        cancel|off) ipc '{"command":["script-message","cmusic-timer-off"]}' >/dev/null; echo "⏲ timer off" ;;
        *) secs=$(dur_secs "$1") || { echo "usage: stop in 30m | stop after this | stop cancel" >&2; exit 1; }
          ipc "{\"command\":[\"script-message\",\"cmusic-sleep\",\"$secs\"]}" >/dev/null
          echo "⏲ stopping in $(mmss "$secs")" ;;
      esac
      exit 0
    fi
    if running && lua_ready; then
      # cmusic.lua fades out and quits; wait for it, then make sure.
      ipc '{"command":["script-message","cmusic-stop"]}' >/dev/null
      for _ in $(seq 1 15); do running || break; sleep 0.1; done
    fi
    running && ipc '{"command":["quit"]}' >/dev/null
    rm -f "$SOCK"; echo "⏹ stopped" ;;
  radio)
    case "${1:-}" in
      "") running || { echo "⏹ nothing playing"; exit 0; }
        echo "📻 radio $(expand '${user-data/cmusic/radio:off}')" ;;
      on|off) running || { echo "⏹ nothing playing"; exit 0; }
        lua_ready || { echo "✗ radio needs mpv >= 0.36 with Lua (see: doctor)" >&2; exit 1; }
        ipc "{\"command\":[\"script-message\",\"cmusic-radio\",\"$1\"]}" >/dev/null; echo "📻 radio $1" ;;
      *) need_deps
        start "$*" "$(source_for "$*" | cut -f1)" --script-opts-append=cmusic-radio=yes
        echo "📻 radio on: related songs will keep playing" ;;
    esac ;;
  lyrics)
    running || { echo "⏹ nothing playing"; exit 0; }
    lua_ready || { echo "✗ lyrics need mpv >= 0.36 with Lua (see: doctor)" >&2; exit 1; }
    wait_title >/dev/null || { echo "▶ still loading, try again in a few seconds"; exit 0; }
    ipc '{"command":["script-message","cmusic-lyrics"]}' >/dev/null
    for _ in $(seq 1 60); do
      st=$(expand '${user-data/cmusic/lyrics-status:}')
      case "$st" in ok|none|error) break ;; esac
      sleep 0.25
    done
    case "$st" in
      ok) if [ "${1:-}" = --line ]; then
            l=$(expand '${user-data/cmusic/lyrics-line:}'); echo "🎤 ${l:-…}"
          else echo "🎤 $(expand '${user-data/cmusic/lyrics}')"; fi ;;
      none) echo "✗ no lyrics found on lrclib.net for: $(expand '${user-data/cmusic/lyrics}')" ;;
      error) echo "✗ couldn't reach lrclib.net" >&2; exit 1 ;;
      *) echo "✗ lrclib.net is slow to answer, try again" >&2; exit 1 ;;
    esac ;;
  focus|pomodoro)
    need_deps
    focus=1500 brk=300
    if [ $# -gt 0 ] && secs=$(dur_secs "$1"); then focus=$secs; shift; fi
    if [ "${1:-}" = break ] && [ $# -gt 1 ]; then
      if [ "$2" = 0 ] || [ "$2" = off ]; then brk=0; else brk=$(dur_secs "$2") || { echo "✗ bad break length: $2" >&2; exit 1; }; fi
      shift 2
    fi
    query="${*:-${CMUSIC_FOCUS_QUERY:-lofi hip hop instrumental focus mix}}"
    start "$query" "$(source_for "$query" | cut -f1)"
    for _ in $(seq 1 20); do lua_ready && break; sleep 0.25; done
    lua_ready || { echo "✗ focus mode needs mpv >= 0.36 with Lua (see: doctor)" >&2; exit 1; }
    ipc "{\"command\":[\"script-message\",\"cmusic-focus\",\"$focus\",\"$brk\",\"$(json_escape "${CMUSIC_BREAK_QUERY:-upbeat feel good songs mix}")\"]}" >/dev/null
    if [ "$brk" -gt 0 ]; then echo "🍅 focus for $(mmss "$focus"), then a $(mmss "$brk") break"; else echo "🍅 focus for $(mmss "$focus")"; fi ;;
  statusline)
    # Plugin installs live under a versioned cache dir, so resolve the newest one at run time.
    case "$SCRIPT_DIR" in
      */plugins/cache/*) cmd='"$(ls -td ~/.claude/plugins/cache/cmusic/cmusic/*/ | head -1)bin/cmusic" now --line --lyrics' ;;
      *) cmd="\"$SCRIPT_DIR/music.sh\" now --line --lyrics" ;;
    esac
    cat <<EOF
Add to ~/.claude/settings.json (refreshInterval keeps the time and lyrics moving):
  "statusLine": { "type": "command", "command": "$(json_escape "$cmd")", "refreshInterval": 1 }
Drop --lyrics to show only the track. Already have a statusline? Append the output of: $cmd
EOF
    ;;
  fav|favorite|like)
    running || { echo "⏹ nothing playing"; exit 0; }
    t=$(wait_title) || { echo "▶ still loading, try again in a few seconds"; exit 0; }
    url=$(expand '${path}'); f="$DATA_DIR/favorites.m3u"
    if [ -f "$f" ] && grep -qxF -- "$url" "$f"; then echo "♥ already a favorite: $t"; exit 0; fi
    note=$(first_write)
    [ -f "$f" ] || echo "#EXTM3U" >"$f"
    printf '#EXTINF:0,%s\n%s\n' "$t" "$url" >>"$f"
    echo "♥ $t"; [ -z "$note" ] || echo "$note" ;;
  unfav|unlike)
    running || { echo "⏹ nothing playing"; exit 0; }
    url=$(expand '${path}'); f="$DATA_DIR/favorites.m3u"
    [ -f "$f" ] && grep -qxF -- "$url" "$f" || { echo "not a favorite"; exit 0; }
    # Drop the URL line and the #EXTINF line just before it.
    awk -v u="$url" '{ l[NR] = $0 } $0 == u { drop[NR] = drop[NR - 1] = 1 } END { for (i = 1; i <= NR; i++) if (!drop[i]) print l[i] }' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
    echo "♡ removed: $(title)" ;;
  favs|favorites)
    f="$DATA_DIR/favorites.m3u"
    [ -f "$f" ] && grep -qv '^#' "$f" || { echo "no favorites yet: say 'fav' while a song you like is playing"; exit 0; }
    need_deps
    start "favorites" "$f" --shuffle
    echo "♥ $(grep -cv '^#' "$f") favorites, shuffled" ;;
  save)
    running || { echo "⏹ nothing playing"; exit 0; }
    name=$(printf '%s' "$*" | tr -c 'A-Za-z0-9 _-' '_'); [ -n "$name" ] || { echo "usage: save <name>" >&2; exit 1; }
    note=$(first_write); mkdir -p "$DATA_DIR/playlists"
    queue_tsv | to_m3u >"$DATA_DIR/playlists/$name.m3u"
    echo "💾 saved \"$name\" ($(grep -cv '^#' "$DATA_DIR/playlists/$name.m3u") tracks)"; [ -z "$note" ] || echo "$note" ;;
  load)
    name=$(printf '%s' "$*" | tr -c 'A-Za-z0-9 _-' '_'); f="$DATA_DIR/playlists/$name.m3u"
    [ -f "$f" ] || { echo "✗ no playlist \"$*\". Saved: $(ls "$DATA_DIR/playlists" 2>/dev/null | sed 's/\.m3u$//' | paste -sd, - | sed 's/,/, /g')" >&2; exit 1; }
    need_deps
    start "$name" "$f" ;;
  playlists)
    ls "$DATA_DIR/playlists"/*.m3u >/dev/null 2>&1 || { echo "no saved playlists: 'save <name>' saves the queue"; exit 0; }
    for f in "$DATA_DIR/playlists"/*.m3u; do n=$(basename "$f" .m3u); echo "  $n ($(grep -cv '^#' "$f") tracks)"; done ;;
  history)
    f="$DATA_DIR/history.tsv"
    if [ ! -s "$f" ]; then
      if [ "${CMUSIC_HISTORY:-0}" = 1 ]; then echo "nothing played yet"
      else echo "history is off; to turn it on, set CMUSIC_HISTORY=1 (it's saved in $DATA_DIR)"; fi
      exit 0
    fi
    # Keep the file bounded.
    [ "$(wc -l <"$f")" -gt 1000 ] && { tail -500 "$f" >"$f.tmp" && mv "$f.tmp" "$f"; }
    tail -"${1:-20}" "$f" | awk -F'\t' '{ l[NR] = "  " $1 "  " $2 } END { for (i = NR; i >= 1; i--) print l[i] }' ;;
  forget)
    if [ -e "$DATA_DIR" ]; then rm -rf "$DATA_DIR"; echo "🗑 deleted $DATA_DIR (favorites, playlists, history)"
    else echo "nothing saved"; fi ;;
  hook)
    # Runs on every Notification / UserPromptSubmit / PostToolUse / Stop, so bail out fast.
    duck=${CMUSIC_DUCK:-0} cheer=${CMUSIC_CELEBRATE:-0}
    { [ "$duck" = 1 ] || [ "$cheer" = 1 ]; } && [ -S "$SOCK" ] || exit 0
    msg() { ipc "{\"command\":[\"script-message\",$1]}" >/dev/null; }
    case "${1:-}" in
      notify) [ "$duck" = 1 ] && msg "\"cmusic-duck\",\"${CMUSIC_DUCK_LEVEL:-30}\"" ;;
      prompt) [ "$duck" = 1 ] && msg '"cmusic-unduck"'
              [ "$cheer" = 1 ] && msg '"cmusic-turn-start"' ;;
      tool)   [ "$duck" = 1 ] && msg '"cmusic-unduck"' ;;
      stop)   [ "$cheer" = 1 ] && msg "\"cmusic-celebrate\",\"${CMUSIC_CELEBRATE_AFTER:-60}\"" ;;
    esac
    exit 0 ;;
  doctor)
    need_deps; v=$(mpv --version | head -1 | awk '{print $2}')
    echo "✓ mpv $v, yt-dlp $(yt-dlp --version)"
    # Fades, timers, radio, ducking and lyrics run in cmusic.lua: they need Lua and user-data (0.36+).
    if ! mpv -v --no-config --idle=no 2>&1 | grep -i 'enabled features' | grep -qE '(: | )lua'; then
      echo "! this mpv has no Lua: fades, timers, focus, radio, ducking and lyrics won't work"
    elif ! awk -v v="${v#v}" 'BEGIN { split(v, p, "."); exit !(p[1] > 0 || p[2] >= 36) }'; then
      echo "! mpv $v is older than 0.36: fades, timers, focus, radio, ducking and lyrics need 0.36+"
    else echo "✓ Lua scripting (fades, timers, radio, lyrics)"; fi ;;
  install)
    install_deps ;;
  *) usage; exit 1 ;;
esac
