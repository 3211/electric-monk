import { useAuth } from '@/composables/useAuth'
import { supabase } from '@/lib/supabase'
import { runBootSequence } from './boot'

import { generateFibonacci } from './fibonacci'
import { BabelAPI, scoreDecryptedText } from './akashic'
import bibleUrl from '@/assets/bible_stripped.txt?url'

export function testCommands() {
  return {
//--
    'test-decrypt-records': {
      help: 'Demo: Akashic Record scanner using Fibonacci seeds and Bible proximity scoring.',
      usage: '/test-decrypt-records',
      async handler(args, ctx) {
        const { terminal, tab } = ctx
        tab.setTitle("Akashic Scanner")
        const sleep = ms => new Promise(r => setTimeout(r, ms))

        terminal.write({ text: '  [SYS] Initializing Akashic Record Scanner...', class: 'term-dim' })
        
        // Load Bible
        const stopLoad = terminal.startSpinner('load-bible', '  Loading reference text (Bible)...', { speed: 80, class: 'term-steel' })
        let bibleWords = [], uniqueBibleWords = []
        try {
          const res = await fetch(bibleUrl)
          const text = await res.text()
          const cleaned = text.toLowerCase().replace(/[^\w\s]/g, '').trim()
          bibleWords = cleaned.split(/\s+/)
          uniqueBibleWords = [...new Set(bibleWords)]
          stopLoad()
          terminal.write({ text: '  [OK]  Reference text loaded.', class: 'term-ally' })
        } catch (e) {
          stopLoad()
          terminal.write({ text: '  [ERR] Failed to load reference text.', class: 'term-enemy' })
          return null
        }

        // Generate Fibonacci Seeds
        terminal.write({ text: '  [SYS] Generating Fibonacci seeds for mining...', class: 'term-dim' })
        const startOffset = Math.floor(Math.random() * 666999111) + 1
        const seqLength = Math.floor(Math.random() * (64 - 16 + 1)) + 16
        const seeds = generateFibonacci(startOffset, seqLength)
        terminal.write({ text: `  [OK]  Generated ${seqLength} seeds starting at ${startOffset}.`, class: 'term-ally' })

        // Mining Loop
        terminal.write({ text: '  [SYS] Commencing Decryption Sequence', class: 'term-brass' })
        terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })

        for (let i = 0; i < Math.min(5, seeds.length); i++) { // Limit to 5 for demo length
          const seed = seeds[i]
          const blockId = (i + 1).toString().padStart(2, '0')
          const address = seed.toString()
          const negAddress = (-seed).toString()

          terminal.write({ text: `  [BLK-${blockId}] Target Address: ${address.substring(0, 16)}...`, class: 'term-brass' })
          
          const progBar = terminal.createProgressBar(`prog-${blockId}`, {
            width: 20,
            class: 'term-steel',
            label: '  Decrypting ',
            format: '{label} [{bar}] {percent}%',
          })

          let currentProgress = 0
          while (currentProgress < 100) {
            currentProgress += 20
            progBar.update(currentProgress)
            await sleep(100)
          }

          progBar.update(100, { class: 'term-ally', label: '  Scoring    ' })
          
          // Generate text from address & score it
          const textPos = BabelAPI.addressToText(address)
          const { score, matches, overlay } = await scoreDecryptedText(textPos, uniqueBibleWords, bibleWords, 50)
          
          progBar.finish({ class: 'term-ally', label: `  Verified   ` })
          terminal.write({ text: `  [BLK-${blockId}] Score: ${score} | Hits: ${matches.length}`, class: 'term-success' })
          
          // Display snippet of the hit
          if (matches.length > 0) {
            const hit = matches[0] // just show the first hit for demo
            const contextStart = Math.max(0, hit.start - 10)
            const contextEnd = Math.min(textPos.length, hit.end + 10)
            const snippet = textPos.substring(contextStart, contextEnd)
            terminal.write({ text: `         Match: ...${snippet}...`, class: 'term-dim' })
          }

          terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })
          await sleep(500)
        }

        terminal.write({ text: '  [SYS] Sequence Complete.', class: 'term-brass' })
        return null
      }
    },

    'test2': {
      help: 'Demo: Interactive terminal features (spinner, progress bar, readLine, menu).',
      usage: '/test2',
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
//--
  }
}