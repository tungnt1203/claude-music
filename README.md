<div align="center">

![cmusic](assets/logo.png)

# cmusic

**Background music for Claude Code.**<br>
Ask for a song and it plays while you keep coding.

[![License: MIT](https://img.shields.io/badge/license-MIT-5EEAD4)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-3A1C5C)
![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-16213E)

**English** · [Tiếng Việt](README.vi.md)

</div>

---

```
> /music Nơi này có anh
▶ NƠI NÀY CÓ ANH | OFFICIAL MUSIC VIDEO | SƠN TÙNG M-TP

> /music
Long debugging session, so here's some lo-fi to keep you focused.
▶ lofi hip hop mix 📚 beats to relax/study to

> skip this one and turn it down a bit
⏭ Best of lofi hip hop 2021 ✨ [beats to relax/study to]
🔊 40
```

## ✨ Features

- 🎧 **Play by name.** Type a song or artist and it streams from YouTube. You can also paste a YouTube or SoundCloud link.
- 🧠 **Claude picks for you.** Ask for music for your mood or for focus, and Claude chooses something to fit.
- 📜 **Queue and controls.** Add songs to the queue, pause, skip and change the volume, either with commands or in plain language.
- 🔒 **Nothing to sign up for.** No accounts or API keys, and nothing is saved to disk.

## 🚀 Install

```
/plugin marketplace add tungnt1203/cmusic
/plugin install cmusic@cmusic
```

Then restart Claude Code. On first play, Claude installs `mpv` and `yt-dlp` for you.

> [!NOTE]
> Works in Claude Code on **macOS** and **Linux** (Windows via WSL). It doesn't work on claude.ai or the mobile apps, because those can't play audio on your computer.

<details>
<summary>Prefer the short <code>/music</code> command? Install it as a personal skill</summary>

```bash
git clone https://github.com/tungnt1203/cmusic
cp -r cmusic/skills/music ~/.claude/skills/
```

</details>

## 🎛️ Usage

| Command | What it does |
|---|---|
| `/music <song>` | Play a song by name, or play a link |
| `/music` | Let Claude pick for your mood |
| `/music add <song>` | Add to the queue |
| `/music radio <song>` | Start a radio: related songs keep playing (`radio on` / `off` for the current queue) |
| `/music queue` | Show the queue (`remove 2` and `clear` edit it) |
| `/music pause` · `next` · `prev` · `stop` | Control playback |
| `/music seek +30` · `seek 1:30` · `replay` | Jump within the track |
| `/music vol 40` | Set the volume (0–100) |
| `/music now` | Show what's playing |
| `/music focus 25` | Pomodoro: 25 min of focus music, a notification, then a 5 min break (`focus 50 break 10`) |
| `/music stop in 30m` | Sleep timer, with a gentle fade-out (`stop after this` waits for the song to end) |

<details>
<summary>Show the current track in the statusline</summary>

Ask Claude to *"show the music in my statusline"*, or add this to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "\"$(ls -td ~/.claude/plugins/cache/cmusic/cmusic/*/ | head -1)bin/cmusic\" now --line"
}
```

It prints `♪ Nơi này có anh · 1:23/4:10` (`⏸` when paused) and nothing when no music is playing. Already have a statusline? Append the output of that command to yours. `cmusic statusline` prints the right command for your install.

</details>

<details>
<summary>Audio cues from Claude: duck while it waits, swell when it's done (opt-in)</summary>

- **Duck**: when Claude needs your input (a permission prompt, or it's done and waiting), the music drops to 30% so you notice, and comes back when you reply.
- **Swell**: when Claude finishes a task that took over a minute, the music briefly swells.

Plugin installs only. Turn them on in `~/.claude/settings.json`:

```json
"env": { "CMUSIC_DUCK": "1", "CMUSIC_CELEBRATE": "1" }
```

`CMUSIC_DUCK_LEVEL` sets how low it goes (percent, default `30`); `CMUSIC_CELEBRATE_AFTER` sets what counts as a long task (seconds, default `60`).

</details>

When installed as a plugin, the command is `/cmusic:music`. You can also just say *"play some lo-fi"* or *"stop the music"*.

## 🔍 What it runs

Everything happens on your machine, through one shell script, [`skills/music/scripts/music.sh`](skills/music/scripts/music.sh), and a small mpv Lua script, [`cmusic.lua`](skills/music/scripts/cmusic.lua), for fades and timers.

| | |
|---|---|
| **Playback** | [`mpv`](https://mpv.io) streams audio using [`yt-dlp`](https://github.com/yt-dlp/yt-dlp), and is controlled through a local socket in your temp folder |
| **Install** | Runs only when a tool is missing. macOS: `brew install mpv yt-dlp`. Linux: `pipx install yt-dlp` if pipx is available, and mpv (plus yt-dlp otherwise) from apt, dnf, pacman, zypper or apk through `sudo` |
| **Network** | Connects only to YouTube or the link you gave, plus your package sources (Homebrew, PyPI, distro mirrors) when installing. No telemetry |

## ❓ FAQ

<details>
<summary><b>Does it download songs?</b></summary>

No. Music streams through RAM only, and nothing is saved to disk.

</details>

<details>
<summary><b>A song won't play?</b></summary>

YouTube changes often, so update yt-dlp: `brew upgrade yt-dlp` on macOS, or `pipx upgrade yt-dlp` on Linux.

</details>

---

<div align="center">

MIT License · [Privacy](PRIVACY.md) · [Support](https://github.com/tungnt1203/cmusic/issues) · tung.nguyen120301@gmail.com<br>
A community project, not affiliated with Anthropic

</div>
