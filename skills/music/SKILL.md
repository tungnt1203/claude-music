---
name: music
description: Play background music from YouTube (audio only, via mpv) while working. Use when the user types /music, asks to play/put on/queue a song, skip, go back, seek, pause, stop the music (now or on a timer), change the volume, asks what's playing or for the lyrics, wants a radio of similar songs, a Pomodoro/focus session, to favorite or save songs and playlists, or asks Claude to pick music for a mood or for focus.
argument-hint: "[song | add <song> | queue | next | prev | pause | stop [in 30m] | vol N | now | lyrics | radio <song> | focus 25 | fav]"
---

# Music

Control playback with the `cmusic` command. It is on PATH when cmusic is installed as a plugin. If `cmusic` isn't found (installed as a personal skill), run `scripts/music.sh` from this skill's base directory instead: same arguments, same output. Every command returns immediately, and mpv keeps playing in the background.

| User wants | Command |
|---|---|
| play X (replaces current) | `cmusic play "X"` |
| queue X after the current track | `cmusic add "X"` |
| songs like X, non-stop / radio | `cmusic radio "X"` |
| keep going after the queue ends / turn that off | `cmusic radio on` · `radio off` |
| show the queue | `cmusic queue` |
| remove track n from the queue / clear it | `cmusic remove 2` · `cmusic clear` |
| pause / resume | `cmusic pause` |
| skip | `cmusic next` |
| previous track (restarts the current one if past 5s) | `cmusic prev` |
| jump forward / back / to a time | `cmusic seek +30` · `seek -10` · `seek 1:30` |
| play this one again from the start | `cmusic replay` |
| volume | `cmusic vol 50` (no number prints the current volume) |
| what's playing | `cmusic now` |
| lyrics / what are they singing | `cmusic lyrics` · `lyrics --line` (just the current line) |
| stop | `cmusic stop` |
| sleep timer / stop when this song ends / cancel it | `cmusic stop in 30m` · `stop after this` · `stop cancel` |
| show the track in Claude Code's statusline | `cmusic statusline` (see Notes) |
| Pomodoro / focus session | `cmusic focus` (25 min + 5 min break) · `focus 50 break 10` · `focus 25 break 0 "jazz piano"` |
| favorite this song / unfavorite / play my favorites | `cmusic fav` · `unfav` · `favs` |
| save the queue as a playlist / play one / list them | `cmusic save "name"` · `load "name"` · `playlists` |
| what did I listen to | `cmusic history` (opt-in) |
| delete everything cmusic saved | `cmusic forget` |
| check setup | `cmusic doctor` |
| install mpv / yt-dlp | `cmusic install` |

`play` and `add` accept a search query (first YouTube result) or a YouTube video/playlist URL.

## When Claude picks the music

For `/music` with no argument, or requests like "put something on", "music to focus", "I'm sad", pick from the signals you already have. Don't run extra commands to sense context, except `date +%H` for the time of day.

1. **An explicit mood or genre wins.** "I'm sad" or "play some jazz" decides it.
2. **What the session is doing** (from the conversation so far):
   - debugging: failing tests, stack traces, "why is this broken" → steady, lyric-free lo-fi or chillhop
   - a big refactor or long build: long instrumental mixes (post-rock, ambient, video game OSTs)
   - writing docs, a README or a PR description: soft piano, acoustic, light jazz
   - shipping or celebrating: tests just passed, a PR merged → something upbeat
   - a new project or brainstorming: energetic electronic or synthwave
3. **Time of day** (`date +%H`): late night (22–05) → calm and ambient; morning (06–10) → bright and upbeat; afternoon slump → something with energy.
4. **Language and locale.** If the user writes in Vietnamese, V-pop (e.g. Sơn Tùng M-TP, Đen, Hoàng Dũng, Vũ.) is a good option, or a Vietnamese lo-fi mix. Same idea for other languages. Still favor instrumental music while they code.

Then:
- Use specific queries (song + artist). For long listening, a mix works, e.g. `"lofi hip hop mix 1 hour"`. For non-stop music in one vibe, `cmusic radio "<seed song>"`.
- Optionally `play` one track and `add` 2–3 with the same vibe.
- Say in one short line why you picked it, naming the signal: "Late night and you're chasing a flaky test, so calm lo-fi."

## Notes
- Keep replies short: relay the command's output line (▶ title) and little else. Reply in the user's language.
- `play` takes ~3–5s to resolve. If it prints "loading", run `now` a few seconds later.
- Exit code 2 means mpv or yt-dlp is missing. Say in one line that you're installing them, run `cmusic install` (it can take a minute or two), then retry the original command. Don't ask first: the user asked for music, and Claude Code's permission prompt already gates the install.
- `install` exit code 3 means the user has to act (usually a sudo password on Linux, or Homebrew missing on macOS). Show the exact command from the output and suggest running it with the `!` prefix, e.g. `! sudo apt-get install -y mpv`, then retry.
- On failure, the error output points to the mpv log file.
- `focus` plays focus music, fades out when time is up, sends a desktop notification and plays upbeat music for the break, then stops. `now` shows the time left (🍅 focus, ☕ break). `stop` ends it early.
- Audio cues (plugin hooks, opt-in): to dip the music while Claude waits for the user, set `"CMUSIC_DUCK": "1"`; for a short swell when a long task (60s+) finishes, set `"CMUSIC_CELEBRATE": "1"`. Both go in the `env` object of `~/.claude/settings.json` (merge with any existing `env`) and apply after a restart.
- `lyrics` output can be long: show it as is, without commentary. If none are found, say so in one line.
- Saved data: `fav` and `save` write to `~/.local/share/cmusic/` only because the user asked; the first write prints where. `history` is off unless `CMUSIC_HISTORY=1` is set in the `env` of `~/.claude/settings.json`: offer that if they ask for history, and mention it stores titles on disk. Run `forget` only when the user explicitly asks to delete their data.
- Statusline: `cmusic statusline` prints the `statusLine` setting to add to `~/.claude/settings.json`: the track plus the lyric line being sung, refreshed every second (drop `--lyrics` for the track only). If the user already has a `statusLine`, don't replace it: append the output of the `now --line` command to their existing script, or ask.
