---
name: music
description: Play background music from YouTube (audio only, via mpv) while working. Use when the user types /music, asks to play/put on/queue a song, skip, pause, stop the music, change the volume, asks what's playing, or asks Claude to pick music for a mood or for focus.
argument-hint: "[song | stop | pause | next | prev | seek +30 | vol N | now | add <song>]"
---

# Music

Control playback with the `cmusic` command. It is on PATH when cmusic is installed as a plugin. If `cmusic` isn't found (installed as a personal skill), run `scripts/music.sh` from this skill's base directory instead: same arguments, same output. Every command returns immediately, and mpv keeps playing in the background.

| User wants | Command |
|---|---|
| play X (replaces current) | `cmusic play "X"` |
| queue X after the current track | `cmusic add "X"` |
| pause / resume | `cmusic pause` |
| skip | `cmusic next` |
| previous track (restarts the current one if past 5s) | `cmusic prev` |
| jump forward / back / to a time | `cmusic seek +30` · `seek -10` · `seek 1:30` |
| play this one again from the start | `cmusic replay` |
| volume | `cmusic vol 50` (no number prints the current volume) |
| what's playing | `cmusic now` |
| stop | `cmusic stop` |
| check setup | `cmusic doctor` |
| install mpv / yt-dlp | `cmusic install` |

`play` and `add` accept a search query (first YouTube result) or a YouTube video/playlist URL.

## When Claude picks the music

For `/music` with no argument, or requests like "put something on", "music to focus", "I'm sad":
- Choose from the mood and context: long coding or debugging sessions get lo-fi, instrumental or ambient; late night gets something calm; an explicit mood wins.
- Use specific queries (song + artist). For long listening, a mix works, e.g. `"lofi hip hop mix 1 hour"`.
- Optionally `play` one track and `add` 2–3 with the same vibe.
- Say in one short line why you picked it.

## Notes
- Keep replies short: relay the command's output line (▶ title) and little else. Reply in the user's language.
- `play` takes ~3–5s to resolve. If it prints "loading", run `now` a few seconds later.
- Exit code 2 means mpv or yt-dlp is missing. Say in one line that you're installing them, run `cmusic install` (it can take a minute or two), then retry the original command. Don't ask first: the user asked for music, and Claude Code's permission prompt already gates the install.
- `install` exit code 3 means the user has to act (usually a sudo password on Linux, or Homebrew missing on macOS). Show the exact command from the output and suggest running it with the `!` prefix, e.g. `! sudo apt-get install -y mpv`, then retry.
- On failure, the error output points to the mpv log file.
