import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

const NOW = {
  title: 'Mất Trí Nhớ - Chi Dân | Official Music Video',
  loading: false,
  paused: false,
  pos: 27,
  duration: 306,
  path: 'https://www.youtube.com/watch?v=vL0J4-twOaw',
  lyrics: 'ok',
}
const LRC = '21.19\tEm là ai từ đâu bước đến\n26.33\tKhông thể nào nhớ những gì\n31.30\tNgắm em thật lâu'

// Stand in for the engine and a running cmusic reporting `now`; returns what got opened.
async function start($: Engine, on: On, now: object | null): Promise<string[]> {
  on('process.run', async (_$, e) => {
    const argv = e.argv
    const json = now === null ? {} : argv.includes('--lrc') ? { ...now, lrc: LRC } : now
    const stdout = argv[0] === '/bin/sh' ? '/fake/cmusic\n' : JSON.stringify(json)
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } } as never
  })
  const clock = mock.clock(on, { now: 1_000_000 })
  const opened: string[] = []
  on('command.register', async (_$, e) => ({ value: { command: e.name } }) as never)
  on('session.start', async () => ({ cwd: '/tmp' }) as never)
  on('ui.open', async (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } } as never
  })
  on('ui.render', { component: 'PromptHint' }, async ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>auto mode on</Text>
  })

  await $.session.start({ source: 'startup', cwd: '/tmp' } as never)
  await clock.advance(800)
  await clock.advance(800)

  return opened
}

const hint = { isDraft: false, isWorking: false, hint: 'auto mode on' }

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: track, progress and lyric under the prompt`, async ($, on) => {
    const opened = await start($, on, NOW)
    const ui = await $.ui.mount({ plugin: 'cmusic-lyrics', surface, component: 'PromptHint', props: hint } as never)

    expect(opened).toEqual([]) // nothing opens unasked
    // The lyric sits beside the title, on one row.
    expect(await ui.find({ type: 'Text', text: '🎵  Mất Trí Nhớ — Chi Dân   🎤 Không thể nào nhớ những gì' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /●.*0:27 \/ 5:06/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'auto mode on' })).toBeDefined() // Claude Code's own line stays
  })

  test(`${surface}: paused hides the lyric`, async ($, on) => {
    await start($, on, { ...NOW, paused: true })
    const ui = await $.ui.mount({ plugin: 'cmusic-lyrics', surface, component: 'PromptHint', props: hint } as never)

    expect(await ui.find({ type: 'Text', text: '⏸  Mất Trí Nhớ — Chi Dân' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /🎤/ })).toBeUndefined()
  })

  test(`${surface}: nothing when no music plays`, async ($, on) => {
    await start($, on, null)
    const ui = await $.ui.mount({ plugin: 'cmusic-lyrics', surface, component: 'PromptHint', props: hint } as never)

    expect(await ui.find({ type: 'Text', text: /🎵|⏸/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'auto mode on' })).toBeDefined()
  })

  test(`${surface}: /lyrics pane highlights the line being sung`, async ($, on) => {
    await start($, on, NOW)
    const ui = await $.ui.mount({
      plugin: 'cmusic-lyrics',
      surface,
      component: 'Pane',
      requestId: 'cmusic-lyrics',
      props: { title: '♪ cmusic', isFocused: false, bodyColumns: 40, placement: 'dock' },
    } as never)

    expect(await ui.find({ type: 'Text', text: '▶ Không thể nào nhớ những gì' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '▶ Em là ai từ đâu bước đến' })).toBeUndefined()
  })
}
