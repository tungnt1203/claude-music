# claude-music 🎵

[Tiếng Việt](README.vi.md)

Background music for [Claude Code](https://claude.com/claude-code). Ask Claude to play a song and it streams the audio from YouTube in the background while you keep working. You can also let Claude pick something for your mood.

```
> /music Nơi này có anh
▶ NƠI NÀY CÓ ANH | OFFICIAL MUSIC VIDEO | SƠN TÙNG M-TP

> /music
Long debugging session, here's some lo-fi to keep you focused.
▶ lofi hip hop radio 📚 beats to relax/study to

> skip this one, and turn it down a bit
⏭ ...
🔊 40
```

No API keys or accounts needed. Audio only, and no browser tab.

## Requirements

- macOS or Linux (on Windows, use WSL)
- [`mpv`](https://mpv.io) and [`yt-dlp`](https://github.com/yt-dlp/yt-dlp). **These install automatically** the first time you play something. Claude runs `music.sh install` for you:
  - **macOS**: `brew install mpv yt-dlp` (needs [Homebrew](https://brew.sh))
  - **Linux**: yt-dlp is downloaded as the latest standalone binary into `~/.local/bin`, which needs no root. mpv comes from your package manager (apt, dnf, pacman, zypper or apk). If sudo needs a password, Claude shows you the one command to run yourself with `! sudo …`

On Linux, [`socat`](http://www.dest-unreach.org/socat/) or `python3` is used to talk to mpv. Most systems already have one of them.

## Install

**As a Claude Code plugin**

```
/plugin marketplace add tungnt1203/claude-music
/plugin install claude-music@claude-music
```

Plugin skills are namespaced, so the command is `/claude-music:music`. You can also just ask in plain words ("play some jazz").

**As a personal skill** (gives you the short `/music` command)

```bash
git clone https://github.com/tungnt1203/claude-music
cp -r claude-music/skills/music ~/.claude/skills/music
```

Restart Claude Code after installing.

## Usage

| Command | What it does |
|---|---|
| `/music <song or URL>` | Play now (replaces the current track) |
| `/music` | Claude picks something based on your mood and what you're doing |
| `/music add <song>` | Queue after the current track |
| `/music pause` | Pause / resume |
| `/music next` | Skip |
| `/music vol 40` | Set volume (0–100) |
| `/music now` | Show what's playing |
| `/music stop` | Stop |

Plain language works too: *"put on something chill"*, *"turn it down"*, *"what's this song?"*, *"stop the music"*.

To avoid a permission prompt on every command, allow the script in `~/.claude/settings.json`:

```json
{ "permissions": { "allow": ["Bash(*/skills/music/scripts/music.sh:*)"] } }
```

## How it works

`scripts/music.sh` starts `mpv --no-video` with a `ytdl://ytsearch1:<query>` source, so yt-dlp resolves the first YouTube result. The script then controls mpv through its [JSON IPC socket](https://mpv.io/manual/master/#json-ipc). The script is plain bash and works without Claude:

```bash
skills/music/scripts/music.sh play "daft punk get lucky"
skills/music/scripts/music.sh doctor
```

Environment variable: `CLAUDE_MUSIC_SOCKET` overrides the IPC socket path.

## Troubleshooting

- **`missing: mpv yt-dlp`**: install them (see Requirements).
- **Playback fails or a song won't load**: YouTube changes often. Update yt-dlp first (`brew upgrade yt-dlp` or `pipx upgrade yt-dlp`). The error message gives the path to the mpv log.
- **No sound**: check that `mpv "ytdl://ytsearch1:test"` plays in a normal terminal.

## License

MIT
