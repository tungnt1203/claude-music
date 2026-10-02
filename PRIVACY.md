# Privacy Policy

_Last updated: October 2, 2026_

cmusic is a Claude Code plugin that plays music on your computer. This policy explains what data it handles.

## Summary

The developer collects **no data**. cmusic has no server, no analytics and no telemetry. Everything runs locally on your machine.

## What leaves your machine

| Data | Sent to | Why |
|---|---|---|
| The song name you ask for, or the link you paste | YouTube, or the site the link points to, through [yt-dlp](https://github.com/yt-dlp/yt-dlp) | To find and stream the audio |
| The current track's title, cleaned up | [lrclib.net](https://lrclib.net), only when you ask for lyrics | To find the lyrics |
| Standard package-manager requests | Homebrew, PyPI or your Linux distribution's mirrors | Only when Claude installs `mpv` or `yt-dlp` for you |

Those services process the requests under their own privacy policies, for example the [Google Privacy Policy](https://policies.google.com/privacy) for YouTube. Nothing is sent to the developer.

## What is stored on your machine

- **Audio**: nothing. Audio streams through memory and is never written to disk.
- **Temporary files**: a control socket and a log file of the latest player output, in your temp folder (`cmusic-<uid>.sock`, `cmusic-<uid>.log`). The log is overwritten each time a song starts.
- **yt-dlp cache**: yt-dlp may keep a small technical cache, a few KB, in `~/.cache/yt-dlp`.

## Your conversations

cmusic does not read, store or transmit your Claude conversations, memory or files. Claude only passes it the song name or command you asked for.

## Changes

Changes to this policy are published in this file, and its history is visible in the [repository's commit log](https://github.com/tungnt1203/cmusic/commits/main/PRIVACY.md).

## Contact

Questions or concerns: **tung.nguyen120301@gmail.com**, or [open an issue](https://github.com/tungnt1203/cmusic/issues).
