import { generateFibonacci } from './fibonacci'
import { BabelAPI, scoreDecryptedText } from './akashic'
import bibleUrl from '@/assets/bible_stripped.txt?url'

const GLITCH_GLYPHS = "!@#$%^&*([|/\\:;_-.,])░▒▓█▄▀╔╗╚╝║═╬┼";
const EVA_BRAILLE = "⣿⣾⣽⣻⢿⡿⣟⣯⣷";
const EVA_BAR_WIDTH = 76;
const SPINNER_CHARS = ['|', '/', '-', '\\'];
const BATCH_SIZE = 5;

// ── Deterministic pseudo-random (0–1) per frame+position ──
function pseudoRand(seed, pos) {
  let h = (seed * 0x9E3779B9 + pos * 0x517CC1B7) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x85EBCA6B);
  h = Math.imul(h ^ (h >>> 13), 0xC2B2AE35);
  return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / 0x7FFFFFFF;
}

// ── Simple seeded PRNG (0–1) from a single integer seed ──
function seededRand(seed) {
  let h = (seed * 0x9E3779B9) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x85EBCA6B);
  h = Math.imul(h ^ (h >>> 13), 0xC2B2AE35);
  return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / 0x7FFFFFFF;
}

/**
 * Roll a target phrase from the Bible using a Fibonacci-derived seed.
 * 90% chance of 2 words; power-law distribution for 3–32 words.
 * @param {string[]} bibleWords - ordered words from bible_stripped.txt
 * @param {bigint|number} seedInt - Fibonacci seed value
 * @returns {{ phrase: string, wordCount: number, startPos: number }}
 */
function rollTargetPhrase(bibleWords, seedInt) {
  const seed = Number(BigInt(seedInt) % BigInt(Number.MAX_SAFE_INTEGER));

  // Determine word count
  const r1 = seededRand(seed);
  let wordCount;
  if (r1 < 0.90) {
    wordCount = 2;
  } else {
    // Power-law: remaining 10% mapped across 3–32 with strong bias toward lower counts
    const r2 = seededRand(seed + 1);
    wordCount = 3 + Math.floor(30 * Math.pow(1 - r2, 4));
    wordCount = Math.min(wordCount, 32);
  }

  // Pick starting position
  const r3 = seededRand(seed + 2);
  const maxStart = Math.max(0, bibleWords.length - wordCount);
  const startPos = Math.floor(r3 * maxStart);

  // Extract phrase
  const phrase = bibleWords.slice(startPos, startPos + wordCount).join(' ');

  return { phrase, wordCount, startPos };
}

/**
 * Build the batch progress visualizer with colored segments.
 * @param {Array<'pending'|'active'|'complete'>} batchStates - 5-element array
 * @param {number} spinnerFrame - incremented each frame for active slot animation
 * @returns {{ text: string, segments: Array<{ text: string, class: string }> }}
 */
function buildBatchVisualizer(batchStates, spinnerFrame) {
  const segments = [];
  for (let i = 0; i < BATCH_SIZE; i++) {
    const state = batchStates[i];
    let glyph, cls;
    if (state === 'complete') {
      glyph = 'X';
      cls = 'term-success';      // Green
    } else if (state === 'active') {
      glyph = SPINNER_CHARS[spinnerFrame % SPINNER_CHARS.length];
      cls = 'term-enemy';        // Red
    } else {
      glyph = 'o';
      cls = 'term-amber';        // Yellow
    }
    if (i > 0) {
      segments.push({ text: ' . ', class: 'term-dim' });
    }
    segments.push({ text: `[ ${glyph} ]`, class: cls });
  }
  const text = segments.map(s => s.text).join('');
  return { text, segments };
}

/**
 * Find all occurrences of targetPhrase as a contiguous substring in fullText.
 * Returns an overlay array (same length as fullText) with 2 at matched positions, 0 elsewhere.
 */
function findTargetPhraseOverlay(fullText, targetPhrase) {
  const overlay = Array(fullText.length).fill(0);
  if (!targetPhrase || targetPhrase.length < 2) return overlay;

  let pos = fullText.indexOf(targetPhrase);
  while (pos !== -1) {
    for (let i = 0; i < targetPhrase.length; i++) {
      overlay[pos + i] = 2; // 2 = target phrase hit (distinct from 1 = dict hit)
    }
    pos = fullText.indexOf(targetPhrase, pos + 1);
  }
  return overlay;
}

export function buildAkashicCommands() {
  const scannerState = { running: false };

  return {
    'decrypt-records': {
      help: 'Demo: Akashic Record scanner using Fibonacci seeds and Bible proximity scoring.',
      usage: '/decrypt-records',
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

  // ── Eva bar lock state (shared across blocks in a batch) ──
  let barLocked = false;

  while (scannerState.running && seedIndex < seeds.length) {
    // ═══════════════════════════════════════════════════════
    // Clear console before each new batch of 5 blocks
    // ═══════════════════════════════════════════════════════
    terminal.clear();

    // ═══════════════════════════════════════════════════════
    // New batch — release the bar (allow glitching on first chunk)
    // ═══════════════════════════════════════════════════════
    barLocked = false;

    // Roll a new target phrase for this batch of 5 blocks
    const batchSeed = seeds[seedIndex];
    const targetPhrase = rollTargetPhrase(bibleWords, batchSeed);

    // Batch visualizer state
    const batchStates = Array(BATCH_SIZE).fill('pending');
    let batchSpinnerFrame = 0;

    // ═══════════════════════════════════════════════════════
    // Process up to BATCH_SIZE blocks with the same target phrase
    // ═══════════════════════════════════════════════════════
    for (let batchSlot = 0; batchSlot < BATCH_SIZE && seedIndex < seeds.length && scannerState.running; batchSlot++, seedIndex++) {
      const seed = seeds[seedIndex];
      const blockId = (seedIndex + 1).toString().padStart(2, '0')
      const address = seed.toString()

      // ── Per-block chunk viz ID (appears below Isolated bar) ──
      const chunkVizId = `chunk-viz-${blockId}`;
      const phraseLineId = `phrase-${blockId}`;
      
      // Mark this slot as active
      batchStates[batchSlot] = 'active';

      const addrPrefix = address.substring(0, 8);
      const addrSuffix = address.substring(address.length - 8);
      terminal.write({ text: `  [BLK-${blockId}] Locating Address: 0x${addrPrefix}...${addrSuffix}`, class: 'term-brass' })
      
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

      // ═══════════════════════════════════════════════════════
      // Phrase + Chunk Status appear BELOW the "Isolated" bar
      // ═══════════════════════════════════════════════════════
      terminal.write({ id: phraseLineId, text: `  [PHRASE] Rolling target: "${targetPhrase.phrase.substring(0, 60)}${targetPhrase.phrase.length > 60 ? '...' : ''}" (${targetPhrase.wordCount} words)`, class: 'term-brass' });
      
      const viz = buildBatchVisualizer(batchStates, batchSpinnerFrame);
      terminal.write({ id: chunkVizId, text: viz.text, class: 'term-steel', segments: viz.segments });

      const textPos = BabelAPI.addressToText(address)
      const { score, matches, overlay } = await scoreDecryptedText(textPos, uniqueBibleWords, bibleWords, 0)

      // ── Target phrase matching ──
      const targetOverlay = findTargetPhraseOverlay(textPos, targetPhrase.phrase);
      let targetHitCount = 0;
      let targetBonusScore = 0;
      for (let i = 0; i < targetOverlay.length; i++) {
        if (targetOverlay[i] === 2) targetHitCount++;
      }
      if (targetHitCount > 0) {
        // Bonus: wordCount² × 10 — short phrases low, long phrases jackpot
        targetBonusScore = targetPhrase.wordCount * targetPhrase.wordCount * 10;
        // Each character of the phrase counts as one "hit instance"
        targetHitCount = Math.floor(targetHitCount / Math.max(1, targetPhrase.phrase.length));
      }

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
      const chunkSize   = 80;
      const totalChunks = Math.ceil(BabelAPI.PAGE_LENGTH / chunkSize);
      const windowSize  = 10;
      const lineIds     = [];

      for (let i = 0; i < windowSize; i++) {
         const id = `defrag-${blockId}-${i}`;
         lineIds.push(id);
         terminal.write({ id, text: GLITCH_GLYPHS.repeat(5).substring(0, chunkSize), class: 'term-enemy' });
      }

      // Raw Decoder Bar
      const rawDecoderId = `raw-decoder-${blockId}`;
      terminal.write({ id: rawDecoderId, text: `  ═══ RAW DECODER ═══`, class: 'term-dim' });

      // Eva-style Braille loading bar
      const evaBarId = `eva-bar-${blockId}`;
      terminal.write({ id: evaBarId, text: `  [${'░'.repeat(EVA_BAR_WIDTH)}]`, class: 'term-dim' });

      // ── Raw Decoder reveal state — each char: unrevealed → cycling → locked ──
      const RAW_DECODER_WIDTH = chunkSize;
      const CYCLE_FRAMES = 8;
      const rawDecoderState = Array.from({ length: RAW_DECODER_WIDTH }, () => ({
        state: 'unrevealed',  // 'unrevealed' | 'cycling' | 'locked'
        cycleFrame: 0,
        finalHex: '',
      }));

      // ── Scanning zone constants ──
      const HEAD_WIDTH   = 18;
      const JITTER_BAND  = 140;
      const RED_BAND     = 200;
      const FAR_DIM      = 300;

      // Eva bar glitch state machine
      const evaGlitch = {
        active: false,
        phase: 0,
        gapSize: 0,
        maxGap: 14,
        frame: 0,
        stallFrames: 0,
        splitSpeed: 0.45,
        repairSpeed: 0.7,
        nextGlitchAt: 55 + Math.floor(Math.random() * 90),
      };
      const TRACER_STEP  = 16;

      // Pre-calculate best streak from dictionary matches
      let bestStreakStr = "", bestStreakScore = 0;
      matches.forEach(m => {
        if (m.word.length > bestStreakScore) {
          bestStreakScore = m.word.length;
          bestStreakStr   = m.word;
        }
      });

      // If target phrase was found, it becomes the best hit
      if (targetHitCount > 0) {
        bestStreakStr = targetPhrase.phrase;
        bestStreakScore = targetPhrase.wordCount;
      }

      let currentScore       = 0;
      let tracerPos          = 0;
      let lastRevealedCount  = 0;
      let frameSeed          = 0;

      let currentScrollLine  = 0;

      // ── Eva-style Braille loading bar updater ──
      function updateEvaBar(progress, fSeed, locked) {
        let filledCount = Math.floor(progress * EVA_BAR_WIDTH);
        let halfWidth = Math.floor(EVA_BAR_WIDTH / 2);

        // When locked, suppress glitch — bar is solid green
        let gap;
        let isGlitching;
        if (locked) {
          gap = 0;
          isGlitching = false;
        } else {
          gap = Math.floor(evaGlitch.gapSize);
          isGlitching = evaGlitch.active;
        }

        let segments = [];
        let curCls = null, curTxt = "";

        const pushSeg = (ch, cls) => {
          if (curCls === cls) { curTxt += ch; }
          else { if (curTxt.length) segments.push({ text: curTxt, class: curCls }); curCls = cls; curTxt = ch; }
        };

        pushSeg('[', 'term-dim');

        let leftEnd = halfWidth - Math.floor(gap / 2);
        for (let i = 0; i < leftEnd; i++) {
          if (i < filledCount) {
            let bri = Math.floor(pseudoRand(fSeed + 8000, i) * EVA_BRAILLE.length);
            pushSeg(EVA_BRAILLE[bri], isGlitching ? 'term-enemy' : 'term-success');
          } else {
            pushSeg('░', 'term-dim');
          }
        }

        for (let i = 0; i < gap; i++) {
          let gl = GLITCH_GLYPHS[Math.floor(pseudoRand(fSeed + 9000, i) * GLITCH_GLYPHS.length)];
          pushSeg(gl, 'term-enemy');
        }

        let rightStart = halfWidth + Math.ceil(gap / 2);
        for (let i = rightStart; i < EVA_BAR_WIDTH; i++) {
          if (i < filledCount) {
            let bri = Math.floor(pseudoRand(fSeed + 10000, i) * EVA_BRAILLE.length);
            pushSeg(EVA_BRAILLE[bri], isGlitching ? 'term-enemy' : 'term-success');
          } else {
            pushSeg('░', 'term-dim');
          }
        }

        pushSeg(']', 'term-dim');
        if (curTxt.length) segments.push({ text: curTxt, class: curCls });

        terminal.updateLine(evaBarId, {
          text: `  [${'░'.repeat(EVA_BAR_WIDTH)}]`,
          segments
        });
      }

      while (tracerPos < BabelAPI.PAGE_LENGTH && scannerState.running) {
         frameSeed++;

         // ── Eva bar glitch state machine (skipped when locked) ──
         if (!barLocked) {
           if (evaGlitch.active) {
             evaGlitch.frame++;
             if (evaGlitch.phase === 0) {
               evaGlitch.gapSize = Math.min(evaGlitch.maxGap, evaGlitch.gapSize + evaGlitch.splitSpeed);
               if (evaGlitch.gapSize >= evaGlitch.maxGap) {
                 evaGlitch.phase = 1;
                 evaGlitch.stallFrames = 8 + Math.floor(Math.random() * 16);
               }
             } else if (evaGlitch.phase === 1) {
               evaGlitch.stallFrames--;
               if (evaGlitch.stallFrames <= 0) {
                 evaGlitch.phase = 2;
               }
             } else if (evaGlitch.phase === 2) {
               evaGlitch.gapSize = Math.max(0, evaGlitch.gapSize - evaGlitch.repairSpeed);
               if (evaGlitch.gapSize <= 0) {
                 evaGlitch.active = false;
                 evaGlitch.gapSize = 0;
                 evaGlitch.phase = 0;
                 evaGlitch.nextGlitchAt = evaGlitch.frame + 45 + Math.floor(Math.random() * 70);
               }
             }
           } else {
             evaGlitch.frame++;
             if (evaGlitch.frame >= evaGlitch.nextGlitchAt) {
               evaGlitch.active = true;
               evaGlitch.phase = 0;
               evaGlitch.gapSize = 0;
             }
           }
         }

         // ── Update Eva bar (pass barLocked to suppress glitch visuals) ──
         let evaProgress = Math.min(1, tracerPos / BabelAPI.PAGE_LENGTH);
         updateEvaBar(evaProgress, frameSeed, barLocked);

         // ── Pause scan while glitching (never paused when locked) ──
         if (barLocked || !evaGlitch.active) {
           tracerPos += TRACER_STEP;
         }

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
             terminal.updateLine(bestHitId, { text: `  [BEST] ${bestStreakStr.toUpperCase().substring(0, 40)}`, class: 'term-brass' });
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
               let isDictHit   = overlay[absolutePos] === 1;
               let isTargetHit = targetOverlay[absolutePos] === 2;

               let finalChar, finalClass;

               const zoneTransition = tracerPos - JITTER_BAND;
               const headStart      = tracerPos;
               const headEnd        = tracerPos + HEAD_WIDTH;
               const redEnd         = headEnd + RED_BAND;
               const farEnd         = headEnd + FAR_DIM;

               if (absolutePos >= farEnd) {
                  finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                  finalClass = 'term-dim';

               } else if (absolutePos >= redEnd) {
                  finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                  finalClass = 'term-enemy';

               } else if (absolutePos >= headEnd) {
                  finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                  finalClass = 'term-enemy';

               } else if (absolutePos >= headStart) {
                  let depthInHead = absolutePos - headStart;
                  let headBright  = 1 - (depthInHead / HEAD_WIDTH);
                  finalChar  = sourceChar !== ' ' ? sourceChar : (pseudoRand(frameSeed + 7000, absolutePos) > 0.6 ? '▌' : '█');
                  finalClass = headBright > 0.5 ? 'term-holy term-bold' : 'term-holy';

               } else if (absolutePos >= zoneTransition) {
                  let distBehind     = tracerPos - absolutePos;
                  let stabilizeRatio = distBehind / JITTER_BAND;

                  let revealChance = 1 / (1 + Math.exp(-10 * (stabilizeRatio - 0.5)));
                  revealChance = revealChance * 0.7 + 0.08;

                  if (pseudoRand(frameSeed + 1000, absolutePos) < revealChance) {
                     finalChar  = sourceChar;
                     finalClass = isTargetHit ? 'term-holy term-bold'
                                : isDictHit   ? 'term-amber term-bold'
                                :               'term-brass';
                  } else {
                     if (pseudoRand(frameSeed + 2000, absolutePos) < 0.22) {
                        finalChar  = sourceChar;
                        finalClass = 'term-enemy';
                     } else {
                        finalChar  = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed + 3000, absolutePos) * GLITCH_GLYPHS.length)];
                        finalClass = 'term-enemy';
                     }
                  }

               } else {
                  finalChar  = sourceChar;
                  finalClass = isTargetHit ? 'term-holy term-bold'
                             : isDictHit   ? 'term-success term-bold'
                             :               'term-steel';
               }

               pushSeg(finalChar, finalClass);
            }
            if (curTxt.length) segments.push({ text: curTxt, class: curCls });

            terminal.updateLine(lineIds[y], { text: targetStr, segments });
         }

         // ── Raw Decoder Bar — Yellow Braille → Green Cycling Hex → Green Locked Hex ──
         {
            const hexChars   = "0123456789ABCDEF";
            const brailChars = "⣿⣾⣽⣻⢿⡿⣟⣯⣷";
 
            const progressRatio = tracerPos / BabelAPI.PAGE_LENGTH;
 
            // Update reveal state — jagged front using per-char jitter
            for (let x = 0; x < RAW_DECODER_WIDTH; x++) {
               const posRatio = x / RAW_DECODER_WIDTH;
               const jitter = pseudoRand(frameSeed + 70000, x) * 0.15;
               const revealThreshold = progressRatio - jitter;
 
               if (rawDecoderState[x].state === 'unrevealed' && posRatio <= revealThreshold) {
                  rawDecoderState[x].state = 'cycling';
                  rawDecoderState[x].cycleFrame = 0;
                  const absP = Math.floor(posRatio * BabelAPI.PAGE_LENGTH);
                  const c = textPos[Math.min(absP, BabelAPI.PAGE_LENGTH - 1)] || '_';
                  rawDecoderState[x].finalHex = hexChars[c.charCodeAt(0) % 16];
               }
 
               if (rawDecoderState[x].state === 'cycling') {
                  rawDecoderState[x].cycleFrame++;
                  if (rawDecoderState[x].cycleFrame >= CYCLE_FRAMES) {
                     rawDecoderState[x].state = 'locked';
                  }
               }
            }
 
            // Force-reveal remaining when scan nearly complete
            if (progressRatio >= 0.99) {
               for (let x = 0; x < RAW_DECODER_WIDTH; x++) {
                  if (rawDecoderState[x].state === 'unrevealed') {
                     rawDecoderState[x].state = 'cycling';
                     rawDecoderState[x].cycleFrame = 0;
                     const absP = Math.floor((x / RAW_DECODER_WIDTH) * BabelAPI.PAGE_LENGTH);
                     const c = textPos[Math.min(absP, BabelAPI.PAGE_LENGTH - 1)] || '_';
                     rawDecoderState[x].finalHex = hexChars[c.charCodeAt(0) % 16];
                  }
               }
            }
 
            let rawSegs = [];
            let rCls = null, rTxt = "";
            const pushR = (ch, cl) => {
               if (rCls === cl) { rTxt += ch; }
               else { if (rTxt.length) rawSegs.push({ text: rTxt, class: rCls }); rCls = cl; rTxt = ch; }
            };
 
            for (let x = 0; x < RAW_DECODER_WIDTH; x++) {
               const st = rawDecoderState[x];
               if (st.state === 'locked') {
                  pushR(st.finalHex, 'term-success');
               } else if (st.state === 'cycling') {
                  pushR(hexChars[Math.floor(pseudoRand(frameSeed + 80000 + st.cycleFrame, x) * hexChars.length)], 'term-success');
               } else {
                  pushR(brailChars[Math.floor(pseudoRand(frameSeed + 5000, x) * brailChars.length)], 'term-amber');
               }
            }
            if (rTxt.length) rawSegs.push({ text: rTxt, class: rCls });
            terminal.updateLine(rawDecoderId, { text: '─'.repeat(RAW_DECODER_WIDTH), segments: rawSegs });
         }

         // ── Score tick ──
         let progressRatio = Math.min(1, tracerPos / BabelAPI.PAGE_LENGTH);
         const totalScore = score + targetBonusScore;
         currentScore = Math.floor(progressRatio * totalScore);
         terminal.updateLine(liveScoreId, { text: `  [SCORE] ${currentScore}`, class: 'term-steel' });

         // ── Animate batch visualizer spinner for active slot ──
         batchSpinnerFrame++;
         if (batchSpinnerFrame % 4 === 0) {
           const vizSpinner = buildBatchVisualizer(batchStates, batchSpinnerFrame);
           terminal.updateLine(chunkVizId, { text: vizSpinner.text, class: 'term-steel', segments: vizSpinner.segments });
         }

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
               let isTgt = targetOverlay[absP] === 2;
               let isDict = overlay[absP] === 1;
               let cls = isTgt ? 'term-holy term-bold'
                       : isDict ? 'term-success term-bold'
                       : 'term-steel';
               if (flash % 2 === 0) cls += ' term-holy';
               if (sCls === cls) { sTxt += ch; }
               else { if (sTxt.length) segs.push({ text: sTxt, class: sCls }); sCls = cls; sTxt = ch; }
            }
            if (sTxt.length) segs.push({ text: sTxt, class: sCls });
            terminal.updateLine(lineIds[y], { text: targetStr, segments: segs });
         }
         await sleep(80);
      }

      const totalScore = score + targetBonusScore;
      terminal.updateLine(liveScoreId,  { text: `  [SCORE] ${totalScore}`, class: 'term-success term-bold' });
      terminal.updateLine(rawDecoderId, { text: `  ═══ BLOCK ${blockId} SEALED ═══`, class: 'term-holy', segments: [] });

      // Mark this slot as complete
      batchStates[batchSlot] = 'complete';
      const vizComplete = buildBatchVisualizer(batchStates, batchSpinnerFrame);
      terminal.updateLine(chunkVizId, { text: vizComplete.text, class: 'term-steel', segments: vizComplete.segments });

      // ── Lock bar green after first chunk in batch completes ──
      if (batchSlot === 0) {
        barLocked = true;
      }

      // ── Target phrase hit announcement ──
      if (targetHitCount > 0) {
        terminal.write({ text: `  [TARGET] Phrase found! "${targetPhrase.phrase.substring(0, 50)}${targetPhrase.phrase.length > 50 ? '...' : ''}" — Bonus: +${targetBonusScore}`, class: 'term-holy' });
        terminal.updateLine(bestHitId, { text: `  [BEST] ${targetPhrase.phrase.toUpperCase().substring(0, 40)}`, class: 'term-holy term-bold' });
      }

      const stopReg = terminal.startSpinner(`reg-${blockId}`, '  Registering positive matrix...', { speed: 80, class: 'term-steel' });
      await sleep(600);
      stopReg();
      if (!scannerState.running) break;

      terminal.write({ text: `  [BLK-${blockId}] Unit Verified & Sealed.`, class: 'term-holy' })
      terminal.write({ text: `  [SCORE] Points: ${totalScore} | Dictionary Hits: ${matches.length}${targetHitCount > 0 ? ` | Target Phrase Hits: ${targetHitCount}` : ''}`, class: 'term-success' })
      
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
         terminal.write({ text: `    "${bestStreakStr.toUpperCase().substring(0, 60)}"`, class: 'term-ally' });
      }

      terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })
    }

    if (!scannerState.running) break;

    // ═══════════════════════════════════════════════════════
    // Negative space verification — once per batch (every 5 blocks)
    // ═══════════════════════════════════════════════════════
    const batchNum = Math.floor(seedIndex / BATCH_SIZE);
    terminal.write({ text: `  [BATCH-${batchNum}] Validating negative space integrity...`, class: 'term-dim' });
    const stopNeg = terminal.startSpinner(`neg-batch-${batchNum}`, '  Calculating checksum...', { speed: 80, class: 'term-dim' });
    await sleep(800);
    stopNeg();
    if (!scannerState.running) break;

    terminal.write({ text: `  [BATCH-${batchNum}] Negative matrix verified.`, class: 'term-ally' })
    terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })
    
    await sleep(300);
  }

  terminal.write({ text: '  [SYS] Sequence Terminated.', class: 'term-brass' })
  scannerState.running = false;
}