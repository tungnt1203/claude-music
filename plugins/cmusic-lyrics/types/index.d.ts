/** What `cmusic now --json` reports about the playing track. */
export type Track = {
  title: string
  isLoading: boolean
  isPaused: boolean
  pos: number
  duration: number
  /** lrclib lookup state: loading | ok | none | error */
  lyrics: string
  /** seconds the lyrics run late on this track (`cmusic lyrics offset`) */
  offset: number
}

/** One synced lyric line: when it starts (seconds) and its words. */
export type Line = { t: number; text: string }

declare module 'claude-code' {
  interface PluginState {
    'cmusic-lyrics': {
      /** null while nothing plays */
      track: Track | null
      lines: Line[]
      /** set when no cmusic with `now --json` (0.5.1+) is installed */
      problem: string | null
    }
  }
}
