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
export function buildGlobalCommands() {
  return {
    help: {
      help: 'Show this help index. Use /help [command] for details on a specific command.',
      usage: '/help [command]',
      handler(args, ctx) {
        const registry = ctx.registry
        const target = args[0]
        ctx.tab.setTitle("help")
        if (target) {
          const cmd = registry[target]
          if (!cmd) {
            return [{ text: `  No help available for: ${target}`, class: 'term-enemy' }]
          }

          const lines = [
            { text: `  /${target}`, class: 'term-brass' },
            { text: `    ${cmd.help}`, class: 'term-steel' },
          ]
          if (cmd.usage) {
            lines.push({ text: `    Usage: ${cmd.usage}`, class: 'term-dim' })
          }
          return lines
        }

        const cmds = Object.keys(registry)
                                          .filter((key) => !registry[key].hidden)
                                          .sort()
        return [
          { text: '  Welcome to Holy War Online. Type /help for help.', class: 'term-brass' },
          { text: '', class: '' },
          { text: '  Available commands:', class: 'term-steel' },
          ...cmds.map((c) => ({
            text: `    /${c} — ${registry[c].help.split('.')[0]}.`,
            class: 'term-text',
          })),
        ]
      },
    },

    clear: {
      help: 'Clear the terminal buffer.',
      handler(_args, ctx) {
        ctx.terminal.clear()
        return null // no output — buffer is just emptied
      },
    },

    logout: {
      help: 'Sign out of Holy War Online and return to the login screen.',
      handler(_args, _ctx) {
        const auth = useAuth()
        auth.signOut()
        return [{ text: '  Logging out…', class: 'term-brass' }]
      },
    },

    moveto: {
      help: 'Move to a different location. (Stub — navigation not yet wired to the backend.)',
      usage: '/moveto <location>',
      handler(args, _ctx) {
        const dest = args[0]
        if (!dest) {
          return [
            {
              text: '  /moveto: no destination specified. Usage: /moveto <location>',
              class: 'term-enemy',
            },
          ]
        }
        return [
          {
            text: `  /moveto: "${dest}" — location navigation not yet wired to the backend.`,
            class: 'term-dim',
          },
        ]
      },
    },

    'test-interactive': {
      help: 'Demo: Interactive terminal features (spinner, progress bar, readLine).',
      usage: '/test-interactive',
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

    boot: {
      help: 'Run the Holy War Online boot sequence.',
      usage: '/boot',
      hidden: true,
      async handler(args, ctx) {
        const { terminal } = ctx
        terminal.clear()
        await runBootSequence(terminal, 3500)
        return null
      },
    },

    status: {
      help: 'Check your player status and onboarding state.',
      usage: '/status',
      async handler(args, ctx) {
        const { terminal } = ctx
        const { data, error } = await supabase.rpc('get_player_status')
        
        if (error || !data) {
          return [{ text: `  Error fetching status: ${error?.message || 'Unknown error'}`, class: 'term-enemy' }]
        }
        
        const lines = [
          { text: '', class: '' },
          { text: '  ════════════════════════════════════════', class: 'term-dim' },
          { text: '  PLAYER STATUS', class: 'term-brass' },
          { text: '  ════════════════════════════════════════', class: 'term-dim' },
          { text: `  Username: ${data.username || '(not set)'}`, class: data.username ? 'term-ally' : 'term-dim' },
          { text: `  Sect: ${data.sect_name || '(not chosen)'}`, class: data.sect_name ? 'term-ally' : 'term-dim' },
          { text: `  Onboarding: ${data.onboarding_complete ? 'Complete' : 'Incomplete'}`, class: data.onboarding_complete ? 'term-success' : 'term-dim' },
          { text: '  ════════════════════════════════════════', class: 'term-dim' },
          { text: '', class: '' },
        ]
        
        return lines
      },
    },

    'list-sects': {
      help: 'List available sects to join.',
      usage: '/list-sects',
      async handler(args, ctx) {
        const { terminal } = ctx
        
        const { data: sects, error } = await supabase.rpc('get_available_sects')
        
        if (error || !sects) {
          return [{ text: `  Error fetching sects: ${error?.message || 'Unknown error'}`, class: 'term-enemy' }]
        }
        
        const lines = [
          { text: '', class: '' },
          { text: '  ════════════════════════════════════════', class: 'term-dim' },
          { text: '  AVAILABLE SECTS', class: 'term-brass' },
          { text: '  ════════════════════════════════════════', class: 'term-dim' },
          { text: '', class: '' },
        ]
        
        for (const sect of sects) {
          lines.push({ text: `  ${sect.emoji} ${sect.name}`, class: 'term-ally' })
          lines.push({ text: `     ${sect.description || ''}`, class: 'term-text' })
          if (sect.principles && sect.principles.length > 0) {
            lines.push({ text: `     Principles: ${sect.principles.join(', ')}`, class: 'term-dim' })
          }
          lines.push({ text: '', class: '' })
        }
        
        lines.push({ text: '  ════════════════════════════════════════', class: 'term-dim' })
        lines.push({ text: '', class: '' })
        
        return lines
      },
    },
  }
}