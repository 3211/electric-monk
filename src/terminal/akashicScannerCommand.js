import { generateFibonacci } from './fibonacci'
import { BabelAPI, scoreDecryptedText } from './akashic'
import bibleUrl from '@/assets/bible_stripped.txt?url'

const GLITCH_GLYPHS = "!@#$%^&*()░▒▓█▄▀╔╗╚╝║═╬┼";

export function buildAkashicCommands() {
  const scannerState = { running: false };

  return {
    'test-decrypt-records': {
      help: 'Demo: Akashic Record scanner using Fibonacci seeds and Bible proximity scoring.',
      usage: '/test-decrypt-records',
      handler(args, ctx) {
        if (scannerState.running) {
          ctx.terminal.write({ text: '  [SYS] Scanner is already running. Type /stop to terminate.', class: 'term-enemy' });
          return null;
        }
        scannerState.running = true;
        // Start background execution and return immediately to unblock input
        runScanner(ctx, scannerState).catch(console.error);
        return null; // Unblock terminal input
      }
    },
    'stop': {
      help: 'Stop the Akashic scanner',
      usage: '/stop',
      handler(args, ctx) {
        if (scannerState.running) {
          scannerState.running = false;
          ctx.terminal.write({ text: '  [SYS] Terminate signal received. Halting...', class: 'term-enemy' });
        } else {
          ctx.terminal.write({ text: '  [SYS] No scanner running.', class: 'term-dim' });
        }
        return null;
      }
    },
    'end': {
      help: 'Stop the Akashic scanner',
      usage: '/end',
      handler(args, ctx) {
        if (scannerState.running) {
          scannerState.running = false;
          ctx.terminal.write({ text: '  [SYS] Terminate signal received. Halting...', class: 'term-enemy' });
        } else {
          ctx.terminal.write({ text: '  [SYS] No scanner running.', class: 'term-dim' });
        }
        return null;
      }
    }
  }
}

async function runScanner(ctx, scannerState) {
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
    scannerState.running = false;
    return
  }

  // Generate Fibonacci Seeds
  terminal.write({ text: '  [SYS] Generating Fibonacci seeds for mining...', class: 'term-dim' })
  const startOffset = Math.floor(Math.random() * 666999111) + 1
  const seqLength = 64
  const seeds = generateFibonacci(startOffset, seqLength)
  terminal.write({ text: `  [OK]  Generated seed sequence starting at ${startOffset}.`, class: 'term-ally' })

  terminal.write({ text: '  [SYS] Commencing Decryption Sequence', class: 'term-brass' })
  terminal.write({ text: '  [SYS] Type /stop or /end to terminate the scan.', class: 'term-ally' })
  terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })

  let seedIndex = 0;

  while (scannerState.running && seedIndex < seeds.length) {
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
      if (!scannerState.running) break;
      progBar.update(p);
      await sleep(50);
    }
    if (!scannerState.running) { progBar.remove(); break; }
    progBar.finish({ class: 'term-ally', label: '  Isolated   ' })
    await sleep(200);

    const textPos = BabelAPI.addressToText(address)
    const { score, matches, overlay } = await scoreDecryptedText(textPos, uniqueBibleWords, bibleWords, 0)

    const bestHitId = `best-hit-${blockId}`;
    const allHitsId = `all-hits-${blockId}`;
    const liveScoreId = `live-score-${blockId}`;

    terminal.write({ id: bestHitId, text: `  [BEST] --`, class: 'term-brass' });
    terminal.write({ id: allHitsId, text: `  [WORDS] --`, class: 'term-dim' });
    terminal.write({ id: liveScoreId, text: `  [SCORE] 0`, class: 'term-steel' });
    terminal.write({ text: `  [BLK-${blockId}+] Decrypting payload...`, class: 'term-steel' })
    
    const chunkSize = 64; 
    const totalChunks = Math.ceil(BabelAPI.PAGE_LENGTH / chunkSize);
    
    const windowSize = 6;
    const lineIds = [];
    for (let i = 0; i < windowSize; i++) {
       const id = `defrag-${blockId}-${i}`;
       lineIds.push(id);
       terminal.write({ id, text: `    ...`, class: 'term-dim' });
    }

    let currentScore = 0;
    let tracerPos = 0;
    let redGlitchY = 0;

    let bestStreakStr = "";
    let bestStreakScore = 0;

    // Pre-calculate best streak for the marquee
    matches.forEach(m => {
      if (m.word.length > bestStreakScore) {
        bestStreakScore = m.word.length;
        bestStreakStr = m.word;
      }
    });

    while (tracerPos < BabelAPI.PAGE_LENGTH && scannerState.running) {
       tracerPos += 12;
       redGlitchY += 0.3;
       if (redGlitchY >= windowSize) redGlitchY = 0;

       let tracerLine = Math.floor(tracerPos / chunkSize);
       let currentScrollLine = Math.max(0, tracerLine - 4);
       if (currentScrollLine > totalChunks - windowSize) {
           currentScrollLine = totalChunks - windowSize;
       }

       // Update live words marquee
       const revealedMatches = matches.filter(m => m.start < tracerPos);
       if (revealedMatches.length > 0) {
         const displayWords = revealedMatches.slice(-8).map(m => m.word).join(', ');
         terminal.updateLine(allHitsId, { text: `  [WORDS] ${displayWords}`, class: 'term-success' });
         terminal.updateLine(bestHitId, { text: `  [BEST] ${bestStreakStr.toUpperCase()}`, class: 'term-brass' });
       }

       for (let y = 0; y < windowSize; y++) {
          let lineIdx = currentScrollLine + y;
          if (lineIdx >= totalChunks) {
            terminal.updateLine(lineIds[y], { text: ' ', class: 'term-dim' });
            continue;
          }

          const startOffset = lineIdx * chunkSize;
          const endOffset = Math.min(startOffset + chunkSize, BabelAPI.PAGE_LENGTH);
          const targetStr = textPos.substring(startOffset, endOffset).padEnd(chunkSize, ' ');

          // Build compositing layers
          let segments = [];
          let currentClass = null;
          let currentText = "";
          
          const pushSegment = (char, cls) => {
             if (currentClass === cls) {
                currentText += char;
             } else {
                if (currentText.length > 0) segments.push({ text: currentText, class: currentClass });
                currentClass = cls;
                currentText = char;
             }
          };

          for (let x = 0; x < chunkSize; x++) {
             let char = targetStr[x] || ' ';
             let absolutePos = startOffset + x;
             let isHit = overlay[absolutePos] === 1;

             let finalChar = char;
             let finalClass = 'term-steel'; // Layer 1 (Base)

             // Layer 4: Red glitch moving down
             if (absolutePos >= tracerPos && absolutePos < tracerPos + 120) {
                // The unscanned portion ahead of the tracer is red glitch
                finalChar = GLITCH_GLYPHS[Math.floor(Math.random() * GLITCH_GLYPHS.length)];
                finalClass = 'term-enemy';
             } else if (absolutePos >= tracerPos + 120) {
                // Far ahead is just dim glitch
                finalChar = GLITCH_GLYPHS[Math.floor(Math.random() * GLITCH_GLYPHS.length)];
                finalClass = 'term-dim term-bold text-slate-800/20'; // like reference/decryptor.html idle display
             } else if (absolutePos >= tracerPos - 12 && absolutePos < tracerPos) {
                 // Layer 3: Colored tracing scan right behind head
                 finalChar = char !== ' ' ? char : '█';
                 finalClass = 'term-brass';
             } else {
                 // Layer 2: Artifacts and highlight
                 if (isHit) {
                     finalClass = 'term-success term-bold';
                 } else if (Math.random() < 0.02) {
                     finalChar = GLITCH_GLYPHS[Math.floor(Math.random() * GLITCH_GLYPHS.length)];
                     finalClass = 'term-dim';
                 }
             }

             pushSegment(finalChar, finalClass);
          }
          if (currentText.length > 0) segments.push({ text: currentText, class: currentClass });

          terminal.updateLine(lineIds[y], { text: targetStr, segments });
       }

       let progressRatio = Math.min(1, tracerPos / BabelAPI.PAGE_LENGTH);
       currentScore = Math.floor(progressRatio * score);
       terminal.updateLine(liveScoreId, { text: `  [SCORE] ${currentScore}`, class: 'term-steel' });

       await sleep(30);
    }

    if (!scannerState.running) break;

    terminal.updateLine(liveScoreId, { text: `  [SCORE] ${score}`, class: 'term-success term-bold' });

    const stopReg = terminal.startSpinner(`reg-${blockId}`, '  Registering positive matrix...', { speed: 80, class: 'term-steel' });
    await sleep(600);
    stopReg();
    if (!scannerState.running) break;

    terminal.write({ text: `  [BLK-${blockId}-] Validating negative space integrity...`, class: 'term-dim' });
    const stopNeg = terminal.startSpinner(`neg-${blockId}`, '  Calculating checksum...', { speed: 80, class: 'term-dim' });
    await sleep(800);
    stopNeg();
    if (!scannerState.running) break;

    terminal.write({ text: `  [BLK-${blockId}] Unit Verified & Sealed.`, class: 'term-holy' })
    terminal.write({ text: `  [SCORE] Points: ${score} | Dictionary Hits: ${matches.length}`, class: 'term-success' })
    
    terminal.write({ text: `  ${matches.length} of these words are in the Bible.`, class: 'term-brass' });
    if (matches.length > 0) {
       const uniqueFound = [...new Set(matches.map(m => m.word))];
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
    await sleep(500);
  }

  terminal.write({ text: '  [SYS] Sequence Terminated.', class: 'term-brass' })
  scannerState.running = false;
}
