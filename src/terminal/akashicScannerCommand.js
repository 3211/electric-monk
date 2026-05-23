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

          // Generate text from address & score it entirely first so we can reveal it sequentially
          const textPos = BabelAPI.addressToText(address)
          const { score, matches, overlay } = await scoreDecryptedText(textPos, uniqueBibleWords, bibleWords, 0)

          // Setup Marquees & Stats
          const bestHitId = `best-hit-${blockId}`;
          const allHitsId = `all-hits-${blockId}`;
          const liveScoreId = `live-score-${blockId}`;

          terminal.write({ id: bestHitId, text: `  [BEST] --`, class: 'term-brass' });
          terminal.write({ id: allHitsId, text: `  [WORDS] --`, class: 'term-dim' });
          terminal.write({ id: liveScoreId, text: `  [SCORE] 0`, class: 'term-steel' });
          terminal.write({ text: `  [BLK-${blockId}+] Decrypting payload...`, class: 'term-steel' })
          
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

          let currentScore = 0;
          let foundWordsList = [];
          let bestStreakStr = "";
          let bestStreakScore = 0;

          // Scroll through the entire page
          for (let chunkIdx = 0; chunkIdx < totalChunks; chunkIdx++) {
             if (!running) break;

             const startOffset = chunkIdx * chunkSize;
             const endOffset = startOffset + chunkSize;
             const targetStr = textPos.substring(startOffset, endOffset).padEnd(chunkSize, ' ');
             
             // Identify words that fall within this chunk to update live stats
             const chunkMatches = matches.filter(m => m.start >= startOffset && m.start < endOffset);
             if (chunkMatches.length > 0) {
               chunkMatches.forEach(m => {
                 foundWordsList.push(m.word);
                 // We don't have the exact sequenced streak score per word easily available here from the
                 // original function, so we'll just track length as a proxy for "best string" for the marquee
                 if (m.word.length > bestStreakScore) {
                   bestStreakScore = m.word.length;
                   bestStreakStr = m.word;
                 }
               });
               
               // Keep word list marquee bounded
               const displayWords = foundWordsList.slice(-8).join(', ');
               terminal.updateLine(allHitsId, { text: `  [WORDS] ${displayWords}`, class: 'term-success' });
               terminal.updateLine(bestHitId, { text: `  [BEST] ${bestStreakStr.toUpperCase()}`, class: 'term-brass' });
             }

             // Estimate live score (rough progression based on chunk index)
             currentScore = Math.floor((chunkIdx / totalChunks) * score);
             terminal.updateLine(liveScoreId, { text: `  [SCORE] ${currentScore}`, class: 'term-steel' });

             // Shift lines up
             for (let i = 0; i < windowSize - 1; i++) {
                const prevLine = terminal.lines.find(l => l.id === lineIds[i+1]);
                if (prevLine) {
                   terminal.updateLine(lineIds[i], {
                     text: prevLine.text,
                     class: prevLine.class,
                     segments: prevLine.segments ? JSON.parse(JSON.stringify(prevLine.segments)) : undefined
                   });
                }
             }

             // Render new line at the bottom
             const currentLineId = lineIds[windowSize - 1];
             
             // Horizontal scanner effect with glitch trail and active bottom row glitching
             for (let scanPos = 0; scanPos < chunkSize; scanPos += 4) {
               let segments = [];
               let currentClass = null;
               let currentText = "";
               
               const pushSegment = (char, cls) => {
                 if (currentClass === cls) {
                   currentText += char;
                 } else {
                   if (currentText.length > 0) {
                     segments.push({ text: currentText, class: currentClass });
                   }
                   currentClass = cls;
                   currentText = char;
                 }
               };

               for (let c = 0; c < chunkSize; c++) {
                 const isHit = overlay[startOffset + c] === 1;
                 const actualChar = targetStr[c];
                 
                 if (c >= scanPos && c < scanPos + 4) {
                    // The Scanner Head
                    pushSegment(actualChar !== ' ' ? actualChar : '█', 'term-ally');
                 } else if (c < scanPos && c >= scanPos - 12) {
                    // Glitch Trail right behind the scanner
                    pushSegment(glitchString(actualChar, 0.6), 'term-enemy');
                 } else if (c < scanPos) {
                    // Fully resolved trail
                    if (isHit) {
                       pushSegment(actualChar, 'term-ally');
                    } else {
                       pushSegment(actualChar, 'term-steel');
                    }
                 } else {
                    // Unscanned Glitching Future
                    pushSegment(glitchString(actualChar, 0.9), 'term-enemy');
                 }
               }
               if (currentText.length > 0) {
                 segments.push({ text: currentText, class: currentClass });
               }

               // Create a dummy text string of correct length to satisfy updateLine's text requirement
               terminal.updateLine(currentLineId, { text: targetStr, segments: segments });
               await sleep(25); // Horizontal scan speed
             }

             // Final resolution for the line
             let finalSegments = [];
             let currentClass = null;
             let currentText = "";
             
             const pushFinalSegment = (char, cls) => {
               if (currentClass === cls) {
                 currentText += char;
               } else {
                 if (currentText.length > 0) {
                   finalSegments.push({ text: currentText, class: currentClass });
                 }
                 currentClass = cls;
                 currentText = char;
               }
             };

             for (let c = 0; c < chunkSize; c++) {
                const isHit = overlay[startOffset + c] === 1;
                if (isHit) {
                  pushFinalSegment(targetStr[c], 'term-ally');
                } else {
                  pushFinalSegment(targetStr[c], 'term-steel');
                }
             }
             if (currentText.length > 0) {
               finalSegments.push({ text: currentText, class: currentClass });
             }
             
             // Occasional Glitch during scroll
             if (Math.random() < 0.05) {
               terminal.updateLine(currentLineId, { text: `    [CORRUPTION IN SECTOR ${chunkIdx}]`, class: 'term-enemy' });
               await sleep(300);
               terminal.updateLine(currentLineId, { text: `    ${glitchString(targetStr, 0.5)}`, class: 'term-enemy' });
               await sleep(300);
             }
             
             terminal.updateLine(currentLineId, { text: targetStr, segments: finalSegments.length > 0 ? finalSegments : null, class: finalSegments.length > 0 ? '' : 'term-steel' });
             
             await sleep(150); // Slower vertical scroll
          }
          
          // Ensure final score is accurate
          terminal.updateLine(liveScoreId, { text: `  [SCORE] ${score}`, class: 'term-success term-bold' });

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
          
          // Output Summary Details
          terminal.write({ text: `  ${matches.length} of these words are in the Bible.`, class: 'term-brass' });
          if (matches.length > 0) {
             const uniqueFound = [...new Set(matches.map(m => m.word))];
             
             // Chunk words out so they don't force bad wraps if there's a lot
             let wordChunks = [];
             while (uniqueFound.length > 0) {
                wordChunks.push(uniqueFound.splice(0, 8).join(', '));
             }
             wordChunks.forEach(chunk => {
                terminal.write({ text: `    ${chunk}`, class: 'term-dim' });
             });

             terminal.write({ text: `  Longest sentence found:`, class: 'term-steel' });
             terminal.write({ text: `    "${bestStreakStr.toUpperCase()}"`, class: 'term-ally' });
          }

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
