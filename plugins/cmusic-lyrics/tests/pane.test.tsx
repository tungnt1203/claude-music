import { expect, mock, test } from 'claude-code/testing'

const NOW = {
  title: 'Nơi này có anh',
  loading: false,
  paused: false,
  pos: 27,
  duration: 278,
  path: 'https://www.youtube.com/watch?v=FN7ALfpGxiI',
  lyrics: 'ok',
}
const LRC = '21.19\tEm là ai từ đâu bước đến\n26.33\tEm là ai tựa như ánh nắng\n31.30\tNgắm em thật lâu'

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: highlights the line being sung`, async ($, on) => {
    on('process.run', async (_$, e) => {
      const argv = e.argv
      const stdout = argv[0] === '/bin/sh' ? '/fake/cmusic\n' : JSON.stringify(argv.includes('--lrc') ? { ...NOW, lrc: LRC } : NOW)
      return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } } as never
    })

    const clock = mock.clock(on, { now: 1_000_000 })
    const opened: string[] = []
    const statuses: (string | undefined)[] = []
    on('ui.status', async (_$, e) => {
      statuses.push((e as { text?: string }).text)
      return { value: undefined } as never
    })
    on('command.register', async (_$, e) => ({ value: { command: e.name } }) as never)
    on('session.start', async () => ({ cwd: '/tmp' }) as never)
    on('ui.panes', async () => ({ value: opened.map(id => ({ id, title: id, isShown: true, isFocused: false, isPlaced: true })) }) as never)
    on('ui.open', async (_$, e) => {
      opened.push(e.id)
      return { value: { isPlaced: true } } as never
    })

    await $.session.start({ source: 'startup', cwd: '/tmp' } as never)
    await clock.advance(800)
    await clock.advance(800)

    const ui = await $.ui.mount({
      plugin: 'cmusic-lyrics',
      surface,
      component: 'Pane',
      requestId: 'cmusic-lyrics',
      props: { title: '♪ cmusic', isFocused: false, bodyColumns: 40, placement: 'dock' },
    } as never)

    // Not opened unasked: the status line under the prompt carries the track and lyric.
    expect(opened).toEqual([])
    expect(statuses.at(-1)).toBe('♪ Nơi này có anh · 0:27/4:38 · 🎤 Em là ai tựa như ánh nắng')
    expect(await ui.find({ type: 'Text', text: /Nơi này có anh/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '▶ Em là ai tựa như ánh nắng' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '▶ Em là ai từ đâu' })).toBeUndefined()
  })
}
