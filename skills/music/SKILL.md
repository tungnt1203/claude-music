---
name: music
description: Play background music from YouTube (audio only, via mpv) while working. Use when the user types /music, asks to play/put on/queue a song, skip, pause, stop the music, change the volume, asks what's playing, or asks Claude to pick music for a mood or for focus.
argument-hint: "[song | stop | pause | next | vol N | now | add <song>]"
---

# Music

Control playback with `scripts/music.sh` in this skill's base directory. Every command returns immediately; mpv keeps playing in the background.

| User wants | Command |
|---|---|
| play X (replaces current) | `scripts/music.sh play "X"` |
| queue X after the current track | `scripts/music.sh add "X"` |
| pause / resume | `scripts/music.sh pause` |
| skip | `scripts/music.sh next` |
| volume | `scripts/music.sh vol 50` (no number prints the current volume) |
| what's playing | `scripts/music.sh now` |
| stop | `scripts/music.sh stop` |
| check setup | `scripts/music.sh doctor` |
| install mpv / yt-dlp | `scripts/music.sh install` |

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
- Exit code 2 means mpv or yt-dlp is missing. Say in one line that you're installing them, run `scripts/music.sh install` (it can take a minute or two), then retry the original command. Don't ask first: the user asked for music, and Claude Code's permission prompt already gates the install.
- `install` exit code 3 means the user has to act (usually a sudo password on Linux, or Homebrew missing on macOS). Show the exact command from the output and suggest running it with the `!` prefix, e.g. `! sudo apt-get install -y mpv`, then retry.
- On failure, the error output points to the mpv log file.
