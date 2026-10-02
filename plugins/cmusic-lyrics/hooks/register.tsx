import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Line, Track } from '../types'

// cmusic's current track and the lyric being sung, as one status line under the prompt
// while music plays. /lyrics opens a pane beside the transcript with the lyrics around it.

const PANE = 'cmusic-lyrics'
const POLL_MS = 700

const track = atom({ plugin: 'cmusic-lyrics', key: 'track' } as const, null)
const lines = atom({ plugin: 'cmusic-lyrics', key: 'lines' } as const, [])
const problem = atom({ plugin: 'cmusic-lyrics', key: 'problem' } as const, null)

// cmusic itself, newest first: installed from the same marketplace (a sibling of this
// plugin in the cache: <cache>/<marketplace>/cmusic/<version>), the repo this plugin sits
// in (a checkout run with --plugin-dir), any cmusic install, a personal-skill copy, PATH. Only one that knows `now --json` (0.5.1+).
const FIND_CMUSIC = `
root=$1
newest() { d=$(ls -td "$@" 2>/dev/null | head -1); [ -n "$d" ] && echo "\${d}bin/cmusic"; }
for b in "$(newest "$root"/../../cmusic/*/)" \
         "$root/../../bin/cmusic" \
         "$(newest "$HOME"/.claude/plugins/cache/*/cmusic/*/)" \
         "$HOME/.claude/skills/music/scripts/music.sh" \
         "$(command -v cmusic)"; do
  [ -n "$b" ] && [ -x "$b" ] && "$b" help 2>&1 | grep -q -- '--json' && { echo "$b"; exit 0; }
done
exit 1`

type NowJson = {
  title?: string
  loading?: boolean
  paused?: boolean
  pos?: number
  duration?: number
  path?: string
  lyrics?: string
  lrc?: string
}

const mmss = (secs: number) => {
  const t = Math.max(0, Math.floor(secs))
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`
}

const parseLrc = (lrc: string): Line[] =>
  lrc
    .split('\n')
    .map(row => {
      const tab = row.indexOf('\t')
      return { t: Number(row.slice(0, tab)), text: row.slice(tab + 1) }
    })
    .filter(line => !Number.isNaN(line.t))

// Module state: starts over on a reload, which is fine (the next poll rebuilds it).
const st = {
  bin: null as string | null,
  lastSearch: -Infinity,
  lrcPath: '', // the track whose lyrics `lines` holds
  isPolling: false,
  lastStatus: '',
}

// The index of the line being sung at `pos`, or -1 before the first.
function currentLine(lyric: readonly Line[], pos: number): number {
  let current = -1
  lyric.forEach((line, i) => {
    if (line.t <= pos + 0.3) current = i
  })
  return current
}

function statusText(t: Track, lyric: readonly Line[]): string {
  const title = t.isLoading ? 'Loading…' : t.title.length > 32 ? `${t.title.slice(0, 31)}…` : t.title
  const time = t.duration > 0 ? `${mmss(t.pos)}/${mmss(t.duration)}` : mmss(t.pos)
  const line = lyric[currentLine(lyric, t.pos)]?.text
  return `${t.isPaused ? '⏸' : '♪'} ${title} · ${time}${line ? ` · 🎤 ${line}` : ''}`
}

// Pin the line under the prompt, only when it changed.
function setStatus($: EngineInterface, text: string | undefined): void {
  if ((text ?? '') === st.lastStatus) return
  st.lastStatus = text ?? ''
  $.ui.status(text)
}

async function cmusic($: EngineInterface, args: string[]): Promise<NowJson | null> {
  if (!st.bin) {
    const now = await $.clock.now()
    if (now - st.lastSearch < 15000) return null
    st.lastSearch = now
    const found = await $.process.run(['/bin/sh', '-c', FIND_CMUSIC, 'sh', $.plugin.root], { timeoutMs: 10000 })
    if (found.exitCode !== 0) {
      await update($, problem, () => 'cmusic 0.5.1+ not found. Update it: /plugin marketplace update cmusic')
      return null
    }
    st.bin = found.stdout.trim()
    await update($, problem, () => null)
  }
  const r = await $.process.run([st.bin, ...args], { timeoutMs: 5000 })
  if (r.exitCode !== 0) return null
  try {
    return JSON.parse(r.stdout) as NowJson
  } catch {
    return null
  }
}

async function poll($: EngineInterface): Promise<void> {
  if (st.isPolling) return
  st.isPolling = true
  try {
    let now = await cmusic($, ['now', '--json'])
    if (!now) return

    if (!now.title) {
      await update($, track, () => null)
      setStatus($, undefined)
      return
    }

    const path = now.path ?? ''
    if (path !== st.lrcPath) {
      st.lrcPath = ''
      await update($, lines, () => [])
    }
    if (now.lyrics === 'ok' && st.lrcPath === '') {
      const withLrc = await cmusic($, ['now', '--json', '--lrc'])
      if (withLrc?.path === path) {
        now = withLrc
        st.lrcPath = path
        await update($, lines, () => parseLrc(withLrc.lrc ?? ''))
      }
    }

    const next: Track = {
      title: now.title ?? '',
      isLoading: now.loading === true,
      isPaused: now.paused === true,
      pos: now.pos ?? 0,
      duration: now.duration ?? 0,
      lyrics: now.lyrics ?? 'loading',
    }
    await update($, track, () => next)
    setStatus($, statusText(next, await read($, lines)))
  } finally {
    st.isPolling = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'lyrics', description: "Show cmusic's lyrics pane" })
    $.clock.every(POLL_MS, () => poll($))

    return next(e)
  })

  on('command.run', { command: 'lyrics' }, async $ => {
    const opened = await $.ui.open({ id: PANE, title: '♪ cmusic' })

    return { text: opened.isPlaced ? 'Lyrics pane opened.' : `Lyrics pane is waiting: ${opened.reason}` }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const why = await read($, problem)
    const t = await read($, track)
    const lyric = await read($, lines)

    if (why) return <Text dimColor>{why}</Text>
    if (!t) {
      return (
        <Text dimColor>
          ♪ Nothing playing. Try /cmusic:music and a song.
        </Text>
      )
    }

    const rows = Math.max(4, (e.viewport?.rows ?? 24) - 8)
    const time = t.duration > 0 ? `${mmss(t.pos)} / ${mmss(t.duration)}` : mmss(t.pos)
    const header = (
      <Box flexDirection="column" marginBottom={1}>
        <Text bold wrap="truncate-end">
          {t.isPaused ? '⏸' : '♪'} {t.isLoading ? 'Loading…' : t.title}
        </Text>
        <Text dimColor>{time}</Text>
      </Box>
    )

    let body
    if (lyric.length > 0) {
      // The current line sits a third of the way down, so you can read ahead.
      const current = currentLine(lyric, t.pos)
      const start = Math.max(0, Math.min(current - Math.floor(rows / 3), lyric.length - rows))
      body = (
        <Box flexDirection="column">
          {lyric.slice(start, start + rows).map((line, i) =>
            start + i === current ? (
              <Text bold color="cyan" wrap="wrap">
                ▶ {line.text || '♪'}
              </Text>
            ) : (
              <Text dimColor wrap="truncate-end">
                {'  '}
                {line.text || '♪'}
              </Text>
            ),
          )}
        </Box>
      )
    } else {
      const note: Record<string, string> = {
        loading: 'Looking up lyrics…',
        none: 'No lyrics found on lrclib.net.',
        error: "Couldn't reach lrclib.net.",
        ok: 'Only unsynced lyrics: ask for /cmusic:music lyrics.',
      }
      body = <Text dimColor>{note[t.lyrics] ?? 'Looking up lyrics…'}</Text>
    }

    return (
      <Box flexDirection="column">
        {header}
        {body}
      </Box>
    )
  })
}
