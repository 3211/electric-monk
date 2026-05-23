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
          
          // Defrag Animation Simulation (Show 5 chunks of the 3200 char text)
          const chunkSize = 64;
          const displayLines = 5;
          const startOffsets = [];
          for(let i=0; i<displayLines; i++) {
            startOffsets.push(Math.floor(Math.random() * (BabelAPI.PAGE_LENGTH - chunkSize)));
          }

          // Initialize display lines
          for(let i=0; i<displayLines; i++) {
             terminal.write({ id: `defrag-${blockId}-${i}`, text: `    ${glitchString(textPos.substring(startOffsets[i], startOffsets[i] + chunkSize), 0.8)}`, class: 'term-enemy' });
          }

          // Animate defrag
          const animSteps = 10;
          for(let step=1; step<=animSteps; step++) {
            for(let i=0; i<displayLines; i++) {
               const targetStr = textPos.substring(startOffsets[i], startOffsets[i] + chunkSize);
               const glitchIntensity = 0.8 * (1 - (step/animSteps));
               
               // Check if there's a hit in this chunk to highlight
               let hasHit = false;
               for(let j=0; j<chunkSize; j++) {
                  if (overlay[startOffsets[i] + j] === 1) hasHit = true;
               }

               const currentStr = glitchString(targetStr, glitchIntensity);
               let displayClass = 'term-steel';
               if (step === animSteps && hasHit) displayClass = 'term-success';
               else if (step < animSteps) displayClass = 'term-dim';

               terminal.updateLine(`defrag-${blockId}-${i}`, { text: `    ${currentStr}`, class: displayClass });
            }
            await sleep(100);
          }

          // Occasional Error Glitch
          if (Math.random() < 0.3) {
             const errorLineIdx = Math.floor(Math.random() * displayLines);
             terminal.updateLine(`defrag-${blockId}-${errorLineIdx}`, { text: `    [CRITICAL CORRUPTION DETECTED]`, class: 'term-enemy' });
             const stopRecover = terminal.startSpinner(`recover-${blockId}`, '  Recovering sector...', { speed: 60, class: 'term-enemy' });
             await sleep(800);
             stopRecover();
             
             const targetStr = textPos.substring(startOffsets[errorLineIdx], startOffsets[errorLineIdx] + chunkSize);
             let hasHit = false;
             for(let j=0; j<chunkSize; j++) {
                if (overlay[startOffsets[errorLineIdx] + j] === 1) hasHit = true;
             }
             terminal.updateLine(`defrag-${blockId}-${errorLineIdx}`, { text: `    ${targetStr}`, class: hasHit ? 'term-success' : 'term-steel' });
             terminal.write({ text: `  [SYS] Sector recovered.`, class: 'term-ally' });
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
          
          // Await User Input
          let validInput = false;
          while (!validInput) {
             const input = await terminal.readLine('  [SCAN ACTIVE] Press ENTER to continue, or type /end to abort > ');
             if (input.trim() === '') {
                 validInput = true;
             } else if (input.trim().toLowerCase() === '/end') {
                 validInput = true;
                 running = false;
             } else {
                 terminal.write({ text: '  [ERR] Scan running. Press ENTER to continue or type /end to abort.', class: 'term-enemy' });
             }
          }

          seedIndex++;
        }

        terminal.write({ text: '  [SYS] Sequence Terminated.', class: 'term-brass' })
        return null
      }
    }
  }
}
