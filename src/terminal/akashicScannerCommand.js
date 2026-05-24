import { generateFibonacci } from './fibonacci'
import { BabelAPI, scoreDecryptedText } from './akashic'
import bibleUrl from '@/assets/bible_stripped.txt?url'

const GLITCH_GLYPHS = "!@#$%^&*([|/\\:;_-.,])░▒▓█▄▀╔╗╚╝║═╬┼";

// ── Deterministic pseudo-random (0–1) per frame+position ──
function pseudoRand(seed, pos) {
  let h = (seed * 0x9E3779B9 + pos * 0x517CC1B7) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x85EBCA6B);
  h = Math.imul(h ^ (h >>> 13), 0xC2B2AE35);
  return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / 0x7FFFFFFF;
}

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
        runScanner(ctx, scannerState).catch(console.error);
        return null;
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
    bibleWords = text.toLowerCase().split(/\s+/).filter(w => w.length > 0)
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
    
    terminal.write({ text: `  [BLK-${blockId}] Locating Address: 0x${address.substring(0, 16)}...`, class: 'term-brass' })
    
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

    const bestHitId   = `best-hit-${blockId}`;
    const allHitsId   = `all-hits-${blockId}`;
    const liveScoreId = `live-score-${blockId}`;

    terminal.write({ id: bestHitId,   text: `  [BEST]  --`,      class: 'term-brass' });
    terminal.write({ id: allHitsId,   text: `  [WORDS] --`,      class: 'term-dim' });
    terminal.write({ id: liveScoreId, text: `  [SCORE] 0`,       class: 'term-steel' });
    terminal.write({ text: `  [BLK-${blockId}+] Decrypting payload...`, class: 'term-steel' })
    
    // ═══════════════════════════════════════════════════════
    // Grid setup — 10 visible lines + 1 raw-decoder bar
    // ═══════════════════════════════════════════════════════
    const chunkSize   = 80;                               // full terminal width
    const totalChunks = Math.ceil(BabelAPI.PAGE_LENGTH / chunkSize);
    const windowSize  = 10;
    const lineIds     = [];

    for (let i = 0; i < windowSize; i++) {
       const id = `defrag-${blockId}-${i}`;
       lineIds.push(id);
       // Pre-fill each line with pure red glitch
       terminal.write({ id, text: GLITCH_GLYPHS.repeat(5).substring(0, chunkSize), class: 'term-enemy' });
    }

    // Raw Decoder Bar
    const rawDecoderId = `raw-decoder-${blockId}`;
    terminal.write({ id: rawDecoderId, text: `  ═══ RAW DECODER ═══`, class: 'term-dim' });

    // ── Scanning zone constants ──
    const HEAD_WIDTH   = 18;
    const JITTER_BAND  = 140;
    const RED_BAND     = 200;
    const FAR_DIM      = 300;
    const TRACER_STEP  = 16;

    // Pre-calculate best streak
    let bestStreakStr = "", bestStreakScore = 0;
    matches.forEach(m => {
      if (m.word.length > bestStreakScore) {
        bestStreakScore = m.word.length;
        bestStreakStr   = m.word;
      }
    });

    let currentScore       = 0;
    let tracerPos          = 0;
    let lastRevealedCount  = 0;
    let frameSeed          = 0;

    let currentScrollLine  = 0;

    while (tracerPos < BabelAPI.PAGE_LENGTH && scannerState.running) {
       frameSeed++;
       tracerPos += TRACER_STEP;

       // ── Scroll window (tracer at row 5) ──
       let tracerLine = Math.floor(tracerPos / chunkSize);
       currentScrollLine = Math.max(0, tracerLine - 5);
       if (currentScrollLine > totalChunks - windowSize) {
           currentScrollLine = Math.max(0, totalChunks - windowSize);
       }

       // ── Marquee sync ──
       const revealedMatches = matches.filter(m => m.start < tracerPos);
       if (revealedMatches.length > lastRevealedCount) {
         lastRevealedCount = revealedMatches.length;
         const displayWords = revealedMatches.slice(-8).map(m => m.word).join(', ');
         terminal.updateLine(allHitsId, { text: `  [WORDS] ${displayWords}`, class: 'term-success' });

         if (revealedMatches.some(m => m.word === bestStreakStr)) {
           terminal.updateLine(bestHitId, { text: `  [BEST] ${bestStreakStr.toUpperCase()}`, class: 'term-brass' });
         }
       }

       // ── Render 10-line grid ──
       for (let y = 0; y < windowSize; y++) {
          let lineIdx = currentScrollLine + y;
          if (lineIdx >= totalChunks) {
            terminal.updateLine(lineIds[y], { text: ' ', segments: [], class: 'term-dim' });
            continue;
          }

          const startOffset = lineIdx * chunkSize;
          const targetStr = textPos.substring(startOffset, Math.min(startOffset + chunkSize, BabelAPI.PAGE_LENGTH)).padEnd(chunkSize, ' ');

          let segments    = [];
          let curCls      = null;
          let curTxt      = "";

          const pushSeg = (ch, cls) => {
             if (curCls === cls) { curTxt += ch; }
             else {
                if (curTxt.length) segments.push({ text: curTxt, class: curCls });
                curCls = cls;
                curTxt = ch;
             }
          };

          for (let x = 0; x < chunkSize; x++) {
             let absolutePos = startOffset + x;
             let sourceChar  = targetStr[x] || ' ';
             let isHit = overlay[absolutePos] === 1;

             let finalChar, finalClass;

             const zoneTransition = tracerPos - JITTER_BAND;
             const headStart      = tracerPos;
             const headEnd        = tracerPos + HEAD_WIDTH;
             const redEnd         = headEnd + RED_BAND;
             const farEnd         = headEnd + FAR_DIM;

             if (absolutePos >= farEnd) {
                // ▓▓▓ Far ahead — dim entropy ▓▓▓
                finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                finalClass = 'term-dim';

             } else if (absolutePos >= redEnd) {
                // ▓▓▓ Mid-ahead — faint red ▓▓▓
                finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                finalClass = 'term-enemy';

             } else if (absolutePos >= headEnd) {
                // ▓▓▓ Red glitch — intense entropy ▓▓▓
                finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                finalClass = 'term-enemy';

             } else if (absolutePos >= headStart) {
                // ▓▓▓ Scanner Head — holy beam ▓▓▓
                let depthInHead = absolutePos - headStart;
                let headBright  = 1 - (depthInHead / HEAD_WIDTH);
                finalChar  = sourceChar !== ' ' ? sourceChar : (pseudoRand(frameSeed + 7000, absolutePos) > 0.6 ? '▌' : '█');
                finalClass = headBright > 0.5 ? 'term-holy term-bold' : 'term-holy';

             } else if (absolutePos >= zoneTransition) {
                // ▓▓▓ Jitter — chaotic stabilization ▓▓▓
                let distBehind     = tracerPos - absolutePos;
                let stabilizeRatio = distBehind / JITTER_BAND;

                // Sigmoid reveal curve: slow→fast→slow
                let revealChance = 1 / (1 + Math.exp(-10 * (stabilizeRatio - 0.5)));
                revealChance = revealChance * 0.7 + 0.08;

                if (pseudoRand(frameSeed + 1000, absolutePos) < revealChance) {
                   finalChar  = sourceChar;
                   finalClass = isHit ? 'term-amber term-bold' : 'term-brass';
                } else {
                   // Partial glitch — sometimes shows real char in enemy color
                   if (pseudoRand(frameSeed + 2000, absolutePos) < 0.22) {
                      finalChar  = sourceChar;
                      finalClass = 'term-enemy';
                   } else {
                      finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed + 3000, absolutePos) * GLITCH_GLYPHS.length)];
                      finalClass = 'term-enemy';
                   }
                }

             } else {
                // ▓▓▓ Deciphered — purified text ▓▓▓
                finalChar  = sourceChar;
                finalClass = isHit ? 'term-success term-bold' : 'term-steel';
             }

             pushSeg(finalChar, finalClass);
          }
          if (curTxt.length) segments.push({ text: curTxt, class: curCls });

          terminal.updateLine(lineIds[y], { text: targetStr, segments });
       }

       // ── Raw Decoder Bar — scrolling hex + braille ──
       {
          const hexChars   = "0123456789ABCDEF";
          const brailChars = "⣿⣾⣽⣻⢿⡿⣟⣯⣷";
          let rawSegs = [];
          let rCls = null, rTxt = "";
          const pushR = (ch, cl) => {
             if (rCls === cl) { rTxt += ch; }
             else { if (rTxt.length) rawSegs.push({ text: rTxt, class: rCls }); rCls = cl; rTxt = ch; }
          };

          for (let x = 0; x < chunkSize; x++) {
             let absP = (tracerPos + x) % BabelAPI.PAGE_LENGTH;
             if (absP < tracerPos) {
                let c = textPos[Math.min(absP, BabelAPI.PAGE_LENGTH - 1)] || '_';
                pushR(hexChars[c.charCodeAt(0) % 16], 'term-steel');
             } else if (absP < tracerPos + HEAD_WIDTH) {
                pushR(brailChars[Math.floor(pseudoRand(frameSeed + 5000, absP) * brailChars.length)], 'term-holy');
             } else {
                pushR(hexChars[Math.floor(pseudoRand(frameSeed + 6000, absP) * hexChars.length)], 'term-enemy');
             }
          }
          if (rTxt.length) rawSegs.push({ text: rTxt, class: rCls });
          terminal.updateLine(rawDecoderId, { text: '─'.repeat(chunkSize), segments: rawSegs });
       }

       // ── Score tick ──
       let progressRatio = Math.min(1, tracerPos / BabelAPI.PAGE_LENGTH);
       currentScore = Math.floor(progressRatio * score);
       terminal.updateLine(liveScoreId, { text: `  [SCORE] ${currentScore}`, class: 'term-steel' });

       await sleep(25);
    }

    if (!scannerState.running) break;

    // ── Seal Flash — rapid purify all grid lines ──
    for (let flash = 0; flash < 3; flash++) {
       for (let y = 0; y < windowSize; y++) {
          let lineIdx = currentScrollLine + y;
          if (lineIdx >= totalChunks) continue;
          const startOffset = lineIdx * chunkSize;
          const targetStr = textPos.substring(startOffset, Math.min(startOffset + chunkSize, BabelAPI.PAGE_LENGTH)).padEnd(chunkSize, ' ');
          let segs = [];
          let sCls = null, sTxt = "";
          for (let x = 0; x < chunkSize; x++) {
             let absP = startOffset + x;
             let ch = targetStr[x] || ' ';
             let cls = overlay[absP] === 1 ? 'term-success term-bold' : 'term-steel';
             if (flash % 2 === 0) cls += ' term-holy';
             if (sCls === cls) { sTxt += ch; }
             else { if (sTxt.length) segs.push({ text: sTxt, class: sCls }); sCls = cls; sTxt = ch; }
          }
          if (sTxt.length) segs.push({ text: sTxt, class: sCls });
          terminal.updateLine(lineIds[y], { text: targetStr, segments: segs });
       }
       await sleep(80);
    }

    terminal.updateLine(liveScoreId,  { text: `  [SCORE] ${score}`, class: 'term-success term-bold' });
    terminal.updateLine(rawDecoderId, { text: `  ═══ BLOCK ${blockId} SEALED ═══`, class: 'term-holy', segments: [] });

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