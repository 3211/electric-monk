export function testCommands() {
  return {
    'test2': {
      help: 'Demo: Interactive terminal features (spinner, progress bar, readLine, menu).',
      usage: '/test2',
      hidden: true,
      async handler(args, ctx) {
        const { terminal, tab } = ctx
        ctx.tab.setTitle("Test 2")
        const sleep = ms => new Promise(r => setTimeout(r, ms))

        // Demo 1: Classic Windows-style spinner
        terminal.write({ text: '  Starting spinner demo...', class: 'term-brass' })
        const stopSpinner = terminal.startSpinner('demo-spinner', '  Loading', { speed: 80, class: 'term-steel' })
        await sleep(2000)
        stopSpinner()

        // Demo 2: Legacy showProgress (still works!)
        terminal.write({ text: '  Legacy progress bar (showProgress):', class: 'term-brass' })
        for (let i = 0; i <= 100; i += 10) {
          terminal.showProgress('demo-progress', i, '  Downloading')
          await sleep(150)
        }
        terminal.removeProgress('demo-progress')

        // Demo 3: Stateful createProgressBar with puppetry
        terminal.write({ text: '  Stateful progress bar (createProgressBar):', class: 'term-brass' })
        const bar = terminal.createProgressBar('demo-bar', {
          width: 20,
          class: 'term-steel',
          label: '  Processing',
          format: '{label} [{bar}] {percent}%',
        })

        // Increment normally
        for (let i = 0; i <= 50; i += 10) {
          bar.update(i)
          await sleep(200)
        }

        // ERROR! Change color mid-flight
        bar.update(null, { class: 'term-enemy', label: '  CORRUPTED' })
        await sleep(800)

        // Recovery — purify a line while the bar is red
        await terminal.purifyLine('demo-purify', 'PAYLOAD RECOVERED', {
          glitchPrefix: '  [ERR]  ',
          purePrefix: '  [OK]   ',
          glitchClass: 'term-enemy',
          pureClass: 'term-ally',
          intensity: 0.8,
          steps: 5,
          stepDelay: 120,
        })

        // Back to normal — finish green
        bar.finish({ class: 'term-ally', label: '  Restored' })
        await sleep(500)
        bar.remove()
        terminal.removeLine('demo-purify')

        // Demo 4: readLine interaction
        terminal.write({ text: '  Interactive input demo:', class: 'term-brass' })
        terminal.write({ text: '  What is your name?', class: 'term-text' })
        const name = await terminal.readLine('  > ')
        terminal.write({ text: `  Nice to meet you, ${name}!`, class: 'term-ally' })

        // Demo 5: Interactive Arrow Key Menu
        terminal.write({ text: '  Interactive Menu demo:', class: 'term-brass' })
        const selection = await terminal.readMenu('  Select a starting class:', [
          { label: 'Cyber-Knight', value: 'knight' },
          { label: 'Neon-Mage', value: 'mage' },
          { label: 'Data-Rogue', value: 'rogue' },
          { label: 'Sys-Admin', value: 'admin' }
        ])
        terminal.write({ text: `  System registered class choice: [${selection.toUpperCase()}]`, class: 'term-steel' })

        // Demo 6: Tab Control
        if (tab && tab.newTab) {
           terminal.write({ text: '  Opening process in new tab...', class: 'term-brass' })
           await sleep(1000)
           tab.newTab('/help')
        }

        return [{ text: '  Demo complete.', class: 'term-brass' }]
      },
    },
  }
}
