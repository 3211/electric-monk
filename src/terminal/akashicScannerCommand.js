import { generateFibonacci } from './fibonacci'
import { BabelAPI, scoreDecryptedText } from './akashic'
import bibleUrl from '@/assets/bible_stripped.txt?url'

const GLITCH_GLYPHS = "!@#$%^&*()░▒▓█▄▀╔╗╚╝║═╬┼";

function glitchString(str, intensity = 0.5) {
  return str.split('').map(char => {
    if (char === ' ') return ' ';
    if (Math.random() < intensity) {
      return GLITCH_GLYPHS[Math.floor(Math.random() * GLITCH_GLYPHS.length)];
    }
    return char;
  }).join('');
}

export function buildAkashicCommands() {
  return {
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
        const seqLength = 64 // Let's just generate a long enough sequence
        const seeds = generateFibonacci(startOffset, seqLength)
        terminal.write({ text: `  [OK]  Generated seed sequence starting at ${startOffset}.`, class: 'term-ally' })

        terminal.write({ text: '  [SYS] Commencing Decryption Sequence', class: 'term-brass' })
        terminal.write({ text: '  [SYS] Type /end to terminate the scan at the next prompt.', class: 'term-dim' })
        terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })

        let running = true;
        let seedIndex = 0;

        // Non-blocking listener for /end command
        const stopListener = terminal.on('lineAdded', (line) => {
          if (line.text.trim().toLowerCase() === '/end') {
            running = false;
            terminal.write({ text: '  [SYS] Terminate signal received. Halting after current cycle...', class: 'term-enemy' });
          }
        });

        while (running && seedIndex < seeds.length) {
          const seed = seeds[seedIndex];
          const blockId = (seedIndex + 1).toString().padStart(2, '0')
          const address = seed.toString()
          
          terminal.write({ text: `  [BLK-${blockId}] Locating Address: ${address.substring(0, 16)}...`, class: 'term-brass' })
          
          const progBar = terminal.createProgressBar(`prog-${blockId}`, {
            width: 20,
            class: 'term-steel',
            label: '  Calculating',
            format: '{label} [{bar}] {percent}%',
          })

          for (let p = 0; p <= 100; p += 20) {
            progBar.update(p);
            await sleep(50);
          }
          progBar.finish({ class: 'term-ally', label: '  Isolated   ' })
          await sleep(200);

          terminal.write({ text: `  [BLK-${blockId}+] Decrypting payload...`, class: 'term-steel' })
          
          // Generate text from address
          const textPos = BabelAPI.addressToText(address)
          const { score, matches, overlay } = await scoreDecryptedText(textPos, uniqueBibleWords, bibleWords, 0)
          
          // Full Akashic Record Scroll Animation
          const chunkSize = 64; // Characters per terminal line
          const totalChunks = Math.ceil(BabelAPI.PAGE_LENGTH / chunkSize);
          
          // We'll maintain a rolling window of 6 visible lines to avoid spamming the history too fast,
          // but we effectively "scroll" through the entire 3200 characters.
          const windowSize = 6;
          const lineIds = [];
          for (let i = 0; i < windowSize; i++) {
             const id = `defrag-${blockId}-${i}`;
             lineIds.push(id);
             terminal.write({ id, text: `    ...`, class: 'term-dim' });
          }

          // Scroll through the entire page
          for (let chunkIdx = 0; chunkIdx < totalChunks; chunkIdx++) {
             if (!running) break;

             const startOffset = chunkIdx * chunkSize;
             const targetStr = textPos.substring(startOffset, startOffset + chunkSize).padEnd(chunkSize, ' ');
             
             let hasHit = false;
             for(let j=0; j<chunkSize; j++) {
                if (overlay[startOffset + j] === 1) hasHit = true;
             }

             // Shift lines up
             for (let i = 0; i < windowSize - 1; i++) {
                const prevLine = terminal.getLine(lineIds[i+1]);
                if (prevLine) {
                   terminal.updateLine(lineIds[i], { text: prevLine.text, class: prevLine.class });
                }
             }

             // Render new line at the bottom
             const currentLineId = lineIds[windowSize - 1];
             
             // Occasional Glitch during scroll
             if (Math.random() < 0.05) { // 5% chance per line
               terminal.updateLine(currentLineId, { text: `    [CORRUPTION IN SECTOR ${chunkIdx}]`, class: 'term-enemy' });
               await sleep(200);
               terminal.updateLine(currentLineId, { text: `    ${glitchString(targetStr, 0.5)}`, class: 'term-enemy' });
               await sleep(200);
               terminal.updateLine(currentLineId, { text: `    ${targetStr}`, class: hasHit ? 'term-success' : 'term-steel' });
             } else {
               // Normal reveal
               terminal.updateLine(currentLineId, { text: `    ${glitchString(targetStr, 0.8)}`, class: 'term-dim' });
               await sleep(30); // Fast scan
               terminal.updateLine(currentLineId, { text: `    ${targetStr}`, class: hasHit ? 'term-success' : 'term-steel' });
             }
             
             await sleep(20);
          }

          // Registering
          const stopReg = terminal.startSpinner(`reg-${blockId}`, '  Registering positive matrix...', { speed: 80, class: 'term-steel' });
          await sleep(600);
          stopReg();

          // Negative Verification
          terminal.write({ text: `  [BLK-${blockId}-] Validating negative space integrity...`, class: 'term-dim' });
          const stopNeg = terminal.startSpinner(`neg-${blockId}`, '  Calculating checksum...', { speed: 80, class: 'term-dim' });
          await sleep(800);
          stopNeg();

          terminal.write({ text: `  [BLK-${blockId}] Unit Verified & Sealed.`, class: 'term-holy' })
          terminal.write({ text: `  [SCORE] Points: ${score} | Dictionary Hits: ${matches.length}`, class: 'term-success' })

          terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })
          
          seedIndex++;
          await sleep(500); // Brief pause before next block
        }

        if (stopListener) stopListener();
        terminal.write({ text: '  [SYS] Sequence Terminated.', class: 'term-brass' })
        return null
      }
    }
  }
}
