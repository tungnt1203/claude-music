# claude-music 🎵

[Tiếng Việt](README.vi.md)

Listen to music while you code with [Claude Code](https://claude.com/claude-code). It plays audio from YouTube in the background. No accounts, no API keys.

```
> /music Nơi này có anh
▶ NƠI NÀY CÓ ANH | OFFICIAL MUSIC VIDEO | SƠN TÙNG M-TP
```

## Install

```
/plugin marketplace add tungnt1203/claude-music
/plugin install claude-music@claude-music
```

Restart Claude Code. On first play, Claude installs `mpv` and `yt-dlp` for you.

Works on macOS and Linux (Windows via WSL).

## Use

| Command | |
|---|---|
| `/music <song>` | Play a song, or paste a YouTube or SoundCloud link |
| `/music` | Let Claude pick for your mood |
| `/music add <song>` | Add to the queue |
| `/music pause` · `next` · `stop` | Control playback |
| `/music vol 40` | Set the volume |
| `/music now` | Show what's playing |

As a plugin, the full command name is `/claude-music:music`. You can also just say *"play some lo-fi"* or *"stop the music"*.

Want the short `/music`? Install as a personal skill instead:

```bash
git clone https://github.com/tungnt1203/claude-music
cp -r claude-music/skills/music ~/.claude/skills/
```

## What it runs

Everything happens on your machine through one shell script, [`skills/music/scripts/music.sh`](skills/music/scripts/music.sh).

- **Playback**: [`mpv`](https://mpv.io) streams audio from YouTube, or a link you paste, using [`yt-dlp`](https://github.com/yt-dlp/yt-dlp). It is controlled through a local socket in your temp folder.
- **Install** (only when missing, and only when Claude runs `music.sh install`):
  - macOS: `brew install mpv yt-dlp`
  - Linux: downloads the yt-dlp binary from [GitHub releases](https://github.com/yt-dlp/yt-dlp/releases) into `~/.local/bin` (or uses `pipx install yt-dlp`), and installs mpv with your package manager (apt, dnf, pacman, zypper or apk) through `sudo`
- **Network**: only YouTube, or the link you gave, and GitHub when installing yt-dlp. No telemetry, and no data is sent anywhere else.

Requires Claude Code on macOS or Linux. It doesn't work on claude.ai or the mobile apps, because those can't play audio on your computer.

## FAQ

**Does it download songs?** No. Music streams through RAM only, and nothing is saved to disk.

**A song won't play?** YouTube changes often, so update yt-dlp: `brew upgrade yt-dlp`, or re-run `music.sh install`.

## License

MIT. This is a community project and isn't affiliated with Anthropic.
