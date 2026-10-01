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

## FAQ

**Does it download songs?** No. Music streams through RAM only, and nothing is saved to disk.

**A song won't play?** YouTube changes often, so update yt-dlp: `brew upgrade yt-dlp`, or re-run `music.sh install`.

## License

MIT
