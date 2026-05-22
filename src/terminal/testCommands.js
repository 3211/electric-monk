import { useAuth } from '@/composables/useAuth'
import { supabase } from '@/lib/supabase'
import { runBootSequence } from './boot'

/**
 * Global terminal commands — auth, navigation, and utility.
 *
 * Onboarding is handled interactively via src/terminal/onboarding.js,
 * not through /commands. This keeps the onboarding flow isolated and
 * ensures /commands are blocked during readLine sessions.
 *
 * Each command entry:
 *   help   — single-line description (first sentence used in /help summary)
 *   usage  — (optional) usage string shown by /help [command]
 *   handler(args, ctx) → returns null | [{ text, class }]
 *
 * ctx contains: { terminal, tab, registry }
 *
 * To add a new global command, add an entry here and it will
 * automatically appear in /help.
 */
export function testCommands() {
  return {
//--
    'test2': {
      help: 'Demo: Interactive terminal features (spinner, progress bar, readLine).',
      usage: '/test2',
      async handler(args, ctx) {
        const { terminal } = ctx

        // Demo 1: Classic Windows-style spinner
        terminal.write({ text: '  Starting spinner demo...', class: 'term-brass' })
        const stopSpinner = terminal.startSpinner('demo-spinner', '  Loading', { speed: 80, class: 'term-steel' })

        // Wait 2 seconds
        await new Promise(r => setTimeout(r, 2000))
        stopSpinner()

        // Demo 2: Progress bar with live updates
        terminal.write({ text: '  Progress bar demo:', class: 'term-brass' })
        for (let i = 0; i <= 100; i += 10) {
          terminal.showProgress('demo-progress', i, '  Downloading')
          await new Promise(r => setTimeout(r, 150))
        }
        terminal.removeProgress('demo-progress')

        // Demo 3: readLine interaction
        terminal.write({ text: '  Interactive input demo:', class: 'term-brass' })
        terminal.write({ text: '  What is your name?', class: 'term-text' })
        const name = await terminal.readLine('  > ')
        terminal.write({ text: `  Nice to meet you, ${name}!`, class: 'term-ally' })

        // Demo 4: updateLine manipulation
        terminal.write({ text: '  Line manipulation demo:', class: 'term-brass' })
        terminal.updateLine('status-line', { text: '  Status: Initializing...', class: 'term-dim' })
        await new Promise(r => setTimeout(r, 500))
        terminal.updateLine('status-line', { text: '  Status: Processing...', class: 'term-text' })
        await new Promise(r => setTimeout(r, 500))
        terminal.updateLine('status-line', { text: '  Status: Complete!', class: 'term-ally' })
        await new Promise(r => setTimeout(r, 500))
        terminal.removeLine('status-line')

        return [{ text: '  Demo complete.', class: 'term-brass' }]
      },
    },
//--
  }
}