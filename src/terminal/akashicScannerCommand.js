import { generateFibonacci } from './fibonacci'
import { BabelAPI, scoreDecryptedText } from './akashic'
import bibleUrl from '@/assets/bible_stripped.txt?url'
import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'

// ── Akashic file generation helpers ──

/** Compute the "negative" address — the mirror/inverse of a positive address */
function computeNegativeAddress(positiveAddress) {
  if (!BabelAPI.MODULUS) BabelAPI.init()
  const pos = BigInt(positiveAddress)
  const neg = (BabelAPI.MODULUS - pos + BabelAPI.INCREMENT) % BabelAPI.MODULUS
  return neg.toString()
}

/** Create akashic record files for a completed block via the manage-files edge function */
async function createAkashicFiles(machineId, blockId, positiveAddress, positiveText, negativeAddress, negativeText, ownerIp) {
  try {
    const { data } = await supabase.functions.invoke('manage-files', {
      body: {
        action: 'create_akashic',
        machine_id: machineId,
        block_id: blockId,
        positive_address: positiveAddress,
        negative_address: negativeAddress,
        positive_text: positiveText,
        negative_text: negativeText,
        owner_ip: ownerIp,
      }
    })
    return data
  } catch (e) {
    console.warn('[akashic] File creation failed (non-fatal):', e.message)
    return null
  }
}

const GLITCH_GLYPHS = "!@#$%^&*([|/\\:;_-.,])░▒▓█▄▀╔╗╚╝║═╬┼";
const EVA_BRAILLE = "⣿⣾⣽⣻⢿⡿⣟⣯⣷";
const EVA_BAR_WIDTH = 76;
const SPINNER_CHARS = ['|', '/', '-', '\\'];
const BOXES_PER_ROW = 5;

// ── Deterministic pseudo-random (0–1) per frame+position ──
function pseudoRand(seed, pos) {
  let h = (seed * 0x9E3779B9 + pos * 0x517CC1B7) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x85EBCA6B);
  h = Math.imul(h ^ (h >>> 13), 0xC2B2AE35);
  return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / 0x7FFFFFFF;
}

function seededRand(seed) {
  let h = (seed * 0x9E3779B9) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x85EBCA6B);
  h = Math.imul(h ^ (h >>> 13), 0xC2B2AE35);
  return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / 0x7FFFFFFF;
}

function rollTargetPhrase(bibleWords, seedInt) {
  const seed = Number(BigInt(seedInt) % BigInt(Number.MAX_SAFE_INTEGER));
  const r1 = seededRand(seed);
  let wordCount;
  if (r1 < 0.90) {
    wordCount = 2;
  } else {
    const r2 = seededRand(seed + 1);
    wordCount = 3 + Math.floor(30 * Math.pow(1 - r2, 4));
    wordCount = Math.min(wordCount, 32);
  }
  const r3 = seededRand(seed + 2);
  const maxStart = Math.max(0, bibleWords.length - wordCount);
  const startPos = Math.floor(r3 * maxStart);
  const phrase = bibleWords.slice(startPos, startPos + wordCount).join(' ');
  return { phrase, wordCount, startPos };
}

/**
 * N-box visualizer: shows all segments at once, 5 boxes per row.
 * @param {Array<'pending'|'active'|'complete'>} states - N-element array
 * @param {number} spinnerFrame
 * @returns {{ text: string, segments: Array<{ text: string, class: string }> }}
 */
function buildSegmentVisualizer(states, spinnerFrame) {
  const segments = [];
  const n = states.length;
  const rows = Math.ceil(n / BOXES_PER_ROW);

  for (let row = 0; row < rows; row++) {
    if (row > 0) {
      segments.push({ text: '\n  ', class: 'term-dim' });
    }
    for (let col = 0; col < BOXES_PER_ROW; col++) {
      const idx = row * BOXES_PER_ROW + col;
      if (idx >= n) break;
      const state = states[idx];
      let glyph, cls;
      if (state === 'complete') {
        glyph = 'X';
        cls = 'term-success';
      } else if (state === 'active') {
        glyph = SPINNER_CHARS[spinnerFrame % SPINNER_CHARS.length];
        cls = 'term-enemy';
      } else {
        glyph = 'o';
        cls = 'term-amber';
      }
      if (col > 0) {
        segments.push({ text: ' . ', class: 'term-dim' });
      }
      segments.push({ text: `[ ${glyph} ]`, class: cls });
    }
  }
  const text = segments.map(s => s.text).join('');
  return { text, segments };
}

function findTargetPhraseOverlay(fullText, targetPhrase) {
  const overlay = Array(fullText.length).fill(0);
  if (!targetPhrase || targetPhrase.length < 2) return overlay;
  let pos = fullText.indexOf(targetPhrase);
  while (pos !== -1) {
    for (let i = 0; i < targetPhrase.length; i++) {
      overlay[pos + i] = 2;
    }
    pos = fullText.indexOf(targetPhrase, pos + 1);
  }
  return overlay;
}

// ── Module-level scanner state ──
const activeScannerState = { running: false, processId: null, machineIp: null }
export function getActiveScannerState() { return activeScannerState }

export function buildAkashicCommands() {
  /** Clean up scanner state: cancel reservations + kill process, then reset */
  async function cleanStop(ctx, reason) {
    const pid = activeScannerState.processId
    const mip = activeScannerState.machineIp
    activeScannerState.running = false
    activeScannerState.processId = null

    if (pid && mip) {
      try {
        await supabase.functions.invoke('akashic-mining', {
          body: { action: 'cancel', process_id: pid, machine_ip: mip }
        }).catch(() => {})
      } catch (_) {}
    }

    // Also kill the virtual_process row if one exists
    if (pid) {
      try {
        await supabase.rpc('complete_process', {
          p_process_id: pid,
          p_status: 'terminated'
        }).catch(() => {})
      } catch (_) {}
    }

    ctx.terminal.write({ text: `  [SYS] Terminate signal received. Halting...${reason ? ` (${reason})` : ''}`, class: 'term-enemy' });
  }

  return {
    'decrypt-records': {
      help: 'Akashic Record scanner — mine the Akashic blockchain for credits and faction standing.',
      usage: '/decrypt-records',
      hidden: true,
      handler(args, ctx) {
        if (activeScannerState.running) {
          ctx.terminal.write({ text: '  [SYS] Scanner is already running. Type /stop to terminate.', class: 'term-enemy' });
          return null;
        }

        const playerState = usePlayerState();
        const vmIp = playerState.get('virtual_machine_ip', null);
        if (!vmIp) {
          ctx.terminal.write({ text: '  [ERR] No virtual machine found. Complete onboarding first.', class: 'term-enemy' });
          return null;
        }

        // Clear any stale state before starting fresh
        Object.keys(activeScannerState).forEach(k => delete activeScannerState[k])
        activeScannerState.machineIp = vmIp;
        activeScannerState.machineId = playerState.machineId.value || null;
        activeScannerState.running = true;
        activeScannerState.processId = null;
        runScanner(ctx, activeScannerState).catch(console.error);
        return null;
      }
    },
    'stop': {
      help: 'Stop the Akashic scanner and clean up any orphaned reservations.',
      usage: '/stop',
      hidden: true,
      handler(args, ctx) {
        if (activeScannerState.running) {
          cleanStop(ctx, 'user requested');
        } else {
          ctx.terminal.write({ text: '  [SYS] No scanner running.', class: 'term-dim' });
        }
        return null;
      }
    },
    'end': {
      help: 'Stop the Akashic scanner and clean up any orphaned reservations.',
      usage: '/end',
      hidden: true,
      handler(args, ctx) {
        if (activeScannerState.running) {
          cleanStop(ctx, 'user requested');
        } else {
          ctx.terminal.write({ text: '  [SYS] No scanner running.', class: 'term-dim' });
        }
        return null;
      }
    }
  }
}

export async function runScanner(ctx, scannerState) {
  const { terminal, tab } = ctx
  tab.setTitle("Akashic Scanner")
  const sleep = ms => new Promise(r => setTimeout(r, ms))

  const totalSegments = scannerState.totalSegments || 5
  const scanMode = scannerState.scanMode || 'scan'
  const initiatorIp = scannerState.initiatorIp || null

  terminal.write({ text: '  [SYS] Initializing Akashic Record Scanner...', class: 'term-dim' })
  terminal.write({ text: `  [SYS] Mode: ${scanMode.toUpperCase()} | Segments: ${totalSegments}`, class: 'term-steel' })

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

  // ── Determine if rehydrating ──
  const isRehydrating = !!scannerState.rehydrateFrom

  // ── Generate seeds / blocks to scan ──
  let seeds = []
  let isVerification = false

  if (isRehydrating) {
    // Query DB for actual progress
    terminal.write({ text: `  [SYS] Rehydrating Akashic Scanner from DB state...`, class: 'term-brass' })
    try {
      const { data: statusData } = await supabase.functions.invoke('akashic-mining', {
        body: { action: 'status', process_id: scannerState.processId, machine_ip: scannerState.machineIp }
      })
      if (statusData?.success && statusData.found) {
        const scan = statusData.scan
        scanMode = scan.scan_mode || 'scan'
        isVerification = scan.is_verification

        // Use the akashic process_id (may differ from virtual_process_id used for lookup)
        scannerState.processId = scan.process_id

        if (scan.scan_mode === 'verify' && scan.reserved_blocks?.length > 0) {
          seeds = scan.reserved_blocks
        } else {
          const startOffset = scannerState.startOffset || (Math.floor(Math.random() * 666999111) + 1)
          seeds = generateFibonacci(startOffset, totalSegments)
        }
        scannerState.blocksCompleted = scan.blocks_completed || 0
        terminal.write({ text: `  [OK]  Found pending scan. Progress: ${scannerState.blocksCompleted}/${seeds.length || totalSegments}`, class: 'term-ally' })
      } else {
        // DB state not found — fall back to local state from process_metadata
        terminal.write({ text: '  [WARN] DB scan state not found. Using local metadata.', class: 'term-amber' })
        const startOffset = scannerState.startOffset || (Math.floor(Math.random() * 666999111) + 1)
        seeds = generateFibonacci(startOffset, totalSegments)
      }
    } catch (_) {
      terminal.write({ text: '  [WARN] Could not reach server. Using local state.', class: 'term-amber' })
      const startOffset = scannerState.startOffset || (Math.floor(Math.random() * 666999111) + 1)
      seeds = generateFibonacci(startOffset, totalSegments)
    }
  } else if (scanMode === 'verify') {
    // Register verify scan and get reserved blocks
    terminal.write({ text: '  [SYS] Registering verification scan...', class: 'term-dim' })
    try {
      const { data: startData, error: startErr } = await supabase.functions.invoke('akashic-mining', {
        body: {
          action: 'start',
          machine_ip: scannerState.machineIp,
          scan_mode: 'verify',
          target_blocks: totalSegments,
          start_block_id: 0,
          virtual_process_id: scannerState.virtualProcessId || null
        }
      })
      if (startErr) throw new Error(startErr.message || 'Edge function error')
      if (!startData.success) throw new Error(startData.error)

      scannerState.processId = startData.process_id
      seeds = startData.reserved_blocks || []
      scannerState.blockSpeedMs = startData.block_speed_ms
      scannerState.expectedCompletion = startData.expected_completion_time
      isVerification = true
      terminal.write({ text: `  [NET] Verification scan registered. PID: ${startData.process_id.substring(0, 8)}...`, class: 'term-dim' })
      if (seeds.length === 0) {
        terminal.write({ text: '  [ERR] No unverified blocks available.', class: 'term-enemy' })
        scannerState.running = false
        return
      }
      terminal.write({ text: `  [NET] Reserved ${seeds.length} blocks for verification.`, class: 'term-steel' })
    } catch (e) {
      terminal.write({ text: `  [ERR] Failed to register: ${e.message}`, class: 'term-enemy' })
      scannerState.running = false
      return
    }
  } else {
    // Scan mode: generate random seeds
    const startOffset = scannerState.startOffset || (Math.floor(Math.random() * 666999111) + 1)
    seeds = generateFibonacci(startOffset, totalSegments)
    terminal.write({ text: `  [OK]  Generated seed sequence starting at ${startOffset}.`, class: 'term-ally' })

    // Register scan with edge function
    terminal.write({ text: '  [SYS] Registering scan...', class: 'term-dim' })
    try {
      const { data: startData, error: startErr } = await supabase.functions.invoke('akashic-mining', {
        body: {
          action: 'start',
          machine_ip: scannerState.machineIp,
          scan_mode: 'scan',
          target_blocks: totalSegments,
          start_block_id: Number(BigInt(seeds[0]) % BigInt(Number.MAX_SAFE_INTEGER)),
          virtual_process_id: scannerState.virtualProcessId || null
        }
      })
      if (startErr) throw new Error(startErr.message || 'Edge function error')
      if (!startData.success) throw new Error(startData.error)

      scannerState.processId = startData.process_id
      scannerState.blockSpeedMs = startData.block_speed_ms
      scannerState.expectedCompletion = startData.expected_completion_time
      terminal.write({ text: `  [NET] Scan registered. PID: ${startData.process_id.substring(0, 8)}... | Block speed: ${startData.block_speed_ms}ms`, class: 'term-dim' })
    } catch (e) {
      terminal.write({ text: `  [NET] Offline mode — rewards will not be recorded: ${e.message}`, class: 'term-amber' })
      scannerState.processId = null
    }
  }

  const blockSpeedMs = scannerState.blockSpeedMs || 25
  terminal.write({ text: '  [SYS] Commencing Decryption Sequence', class: 'term-brass' })
  terminal.write({ text: '  [SYS] Type /stop or /end to terminate the scan.', class: 'term-ally' })
  terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })

  const activeSegments = Math.min(seeds.length, totalSegments)
  if (activeSegments === 0) {
    terminal.write({ text: '  [ERR] No blocks to scan.', class: 'term-enemy' })
    scannerState.running = false
    return
  }

  // ── Seed index tracking ──
  let seedIndex = scannerState.blocksCompleted || 0

  // ── Fast-forward: render completed blocks ──
  if (isRehydrating && seedIndex > 0) {
    terminal.write({ text: `  [SYS] ${seedIndex}/${activeSegments} blocks already complete.`, class: 'term-dim' })
  }

  // ── Segment visualizer state (all segments at once) ──
  const segmentStates = Array(activeSegments).fill('pending')
  for (let i = 0; i < seedIndex; i++) segmentStates[i] = 'complete'
  let vizSpinnerFrame = 0
  const segmentVizId = 'segment-viz'

  // ── Eva bar lock ──
  let barLocked = false

  // ── Batch scores for pulse ──
  const batchScores = []

  // ── Roll a target phrase for the entire scan ──
  const targetSeed = seeds[0] || 1
  const targetPhrase = rollTargetPhrase(bibleWords, targetSeed)

  terminal.clear()

  // Render initial segment visualizer
  const initViz = buildSegmentVisualizer(segmentStates, 0)
  terminal.write({ id: segmentVizId, text: initViz.text, class: 'term-steel', segments: initViz.segments })

  // ── Storage pre-check: how many blocks will fit? ──
  const BYTES_PER_BLOCK = 6400 // 2 files × 3200 chars each
  let blocksThatFit = activeSegments
  if (scannerState.machineId) {
    try {
      const { data: storageData } = await supabase.functions.invoke('manage-files', {
        body: { action: 'storage', machine_id: scannerState.machineId, bytes_per_block: BYTES_PER_BLOCK }
      })
      if (storageData?.success) {
        blocksThatFit = storageData.blocks_that_fit
        if (blocksThatFit < activeSegments) {
          terminal.write({ text: `  ⚠ STORAGE WARNING: Only ${blocksThatFit}/${activeSegments} blocks will fit. Scan will stop when storage is full.`, class: 'term-amber' })
          if (blocksThatFit === 0) {
            terminal.write({ text: `  ⛔ STORAGE FULL! Scanner cannot proceed. Use /delete to free space.`, class: 'term-enemy' })
            scannerState.running = false
            return
          }
        }
      }
    } catch (_) {
      // Storage check is non-fatal — proceed with full scan
    }
  }

  // ═══════════════════════════════════════════
  // Main loop: process each segment sequentially
  // ═══════════════════════════════════════════
  for (; seedIndex < activeSegments && scannerState.running; seedIndex++) {
    const seed = seeds[seedIndex]
    const blockId = (seedIndex + 1).toString().padStart(2, '0')
    const address = seed.toString()

    // Mark as active
    segmentStates[seedIndex] = 'active'

    const chunkVizUpdate = buildSegmentVisualizer(segmentStates, vizSpinnerFrame)
    terminal.updateLine(segmentVizId, { text: chunkVizUpdate.text, class: 'term-steel', segments: chunkVizUpdate.segments })

    const addrPrefix = address.substring(0, 8)
    const addrSuffix = address.substring(address.length - 8)
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

    const phraseLineId = `phrase-${blockId}`
    terminal.write({ id: phraseLineId, text: `  [PHRASE] Target: "${targetPhrase.phrase.substring(0, 60)}${targetPhrase.phrase.length > 60 ? '...' : ''}" (${targetPhrase.wordCount} words)`, class: 'term-brass' });

    const textPos = BabelAPI.addressToText(address)
    const { score, matches, overlay } = await scoreDecryptedText(textPos, uniqueBibleWords, bibleWords, 0)

    // Target phrase matching
    const targetOverlay = findTargetPhraseOverlay(textPos, targetPhrase.phrase);
    let targetHitCount = 0;
    let targetBonusScore = 0;
    for (let i = 0; i < targetOverlay.length; i++) {
      if (targetOverlay[i] === 2) targetHitCount++;
    }
    if (targetHitCount > 0) {
      targetBonusScore = targetPhrase.wordCount * targetPhrase.wordCount * 10;
      targetHitCount = Math.floor(targetHitCount / Math.max(1, targetPhrase.phrase.length));
    }

    const bestHitId   = `best-hit-${blockId}`;
    const allHitsId   = `all-hits-${blockId}`;
    const liveScoreId = `live-score-${blockId}`;

    terminal.write({ id: bestHitId,   text: `  [BEST]  --`,      class: 'term-brass' });
    terminal.write({ id: allHitsId,   text: `  [WORDS] --`,      class: 'term-dim' });
    terminal.write({ id: liveScoreId, text: `  [SCORE] 0`,       class: 'term-steel' });
    terminal.write({ text: `  [BLK-${blockId}+] Decrypting payload...`, class: 'term-steel' })

    // Grid setup
    const chunkSize   = 80;
    const totalChunks = Math.ceil(BabelAPI.PAGE_LENGTH / chunkSize);
    const windowSize  = 10;
    const lineIds     = [];

    for (let i = 0; i < windowSize; i++) {
       const id = `defrag-${blockId}-${i}`;
       lineIds.push(id);
       terminal.write({ id, text: GLITCH_GLYPHS.repeat(5).substring(0, chunkSize), class: 'term-enemy' });
    }

    const rawDecoderId = `raw-decoder-${blockId}`;
    terminal.write({ id: rawDecoderId, text: `  ═══ RAW DECODER ═══`, class: 'term-dim' });

    const evaBarId = `eva-bar-${blockId}`;
    terminal.write({ id: evaBarId, text: `  [${'░'.repeat(EVA_BAR_WIDTH)}]`, class: 'term-dim' });

    // Raw decoder state
    const RAW_DECODER_WIDTH = chunkSize;
    const CYCLE_FRAMES = 8;
    const rawDecoderState = Array.from({ length: RAW_DECODER_WIDTH }, () => ({
      state: 'unrevealed',
      cycleFrame: 0,
      finalHex: '',
    }));

    const HEAD_WIDTH   = 18;
    const JITTER_BAND  = 140;
    const RED_BAND     = 200;
    const FAR_DIM      = 300;

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

    // Best streak
    let bestStreakStr = "", bestStreakScore = 0;
    matches.forEach(m => {
      if (m.word.length > bestStreakScore) {
        bestStreakScore = m.word.length;
        bestStreakStr   = m.word;
      }
    });
    if (targetHitCount > 0) {
      bestStreakStr = targetPhrase.phrase;
      bestStreakScore = targetPhrase.wordCount;
    }

    let tracerPos = 0;
    let lastRevealedCount = 0;
    let frameSeed = 0;
    let currentScrollLine = 0;

    function updateEvaBar(progress, fSeed, locked) {
      let filledCount = Math.floor(progress * EVA_BAR_WIDTH);
      let halfWidth = Math.floor(EVA_BAR_WIDTH / 2);
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

    // ── Per-block scan loop ──
    while (tracerPos < BabelAPI.PAGE_LENGTH && scannerState.running) {
       frameSeed++;

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
             if (evaGlitch.stallFrames <= 0) evaGlitch.phase = 2;
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

       let evaProgress = Math.min(1, tracerPos / BabelAPI.PAGE_LENGTH);
       updateEvaBar(evaProgress, frameSeed, barLocked);

       if (barLocked || !evaGlitch.active) {
         tracerPos += TRACER_STEP;
       }

       let tracerLine = Math.floor(tracerPos / chunkSize);
       currentScrollLine = Math.max(0, tracerLine - 5);
       if (currentScrollLine > totalChunks - windowSize) {
           currentScrollLine = Math.max(0, totalChunks - windowSize);
       }

       const revealedMatches = matches.filter(m => m.start < tracerPos);
       if (revealedMatches.length > lastRevealedCount) {
         lastRevealedCount = revealedMatches.length;
         const displayWords = revealedMatches.slice(-8).map(m => m.word).join(', ');
         terminal.updateLine(allHitsId, { text: `  [WORDS] ${displayWords}`, class: 'term-success' });
         if (revealedMatches.some(m => m.word === bestStreakStr)) {
           terminal.updateLine(bestHitId, { text: `  [BEST] ${bestStreakStr.toUpperCase().substring(0, 40)}`, class: 'term-brass' });
         }
       }

       for (let y = 0; y < windowSize; y++) {
          let lineIdx = currentScrollLine + y;
          if (lineIdx >= totalChunks) {
            terminal.updateLine(lineIds[y], { text: ' ', segments: [], class: 'term-dim' });
            continue;
          }
          const startOffset = lineIdx * chunkSize;
          const targetStr = textPos.substring(startOffset, Math.min(startOffset + chunkSize, BabelAPI.PAGE_LENGTH)).padEnd(chunkSize, ' ');
          let segments = [];
          let curCls = null, curTxt = "";
          const pushSeg = (ch, cls) => {
             if (curCls === cls) { curTxt += ch; }
             else { if (curTxt.length) segments.push({ text: curTxt, class: curCls }); curCls = cls; curTxt = ch; }
          };
          for (let x = 0; x < chunkSize; x++) {
             let absolutePos = startOffset + x;
             let sourceChar = targetStr[x] || ' ';
             let isDictHit = overlay[absolutePos] === 1;
             let isTargetHit = targetOverlay[absolutePos] === 2;
             let finalChar, finalClass;
             const zoneTransition = tracerPos - JITTER_BAND;
             const headStart = tracerPos;
             const headEnd = tracerPos + HEAD_WIDTH;
             const redEnd = headEnd + RED_BAND;
             const farEnd = headEnd + FAR_DIM;
             if (absolutePos >= farEnd) {
                finalChar = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                finalClass = 'term-dim';
             } else if (absolutePos >= redEnd) {
                finalChar = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                finalClass = 'term-enemy';
             } else if (absolutePos >= headEnd) {
                finalChar = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed, absolutePos) * GLITCH_GLYPHS.length)];
                finalClass = 'term-enemy';
             } else if (absolutePos >= headStart) {
                let depthInHead = absolutePos - headStart;
                let headBright = 1 - (depthInHead / HEAD_WIDTH);
                finalChar = sourceChar !== ' ' ? sourceChar : (pseudoRand(frameSeed + 7000, absolutePos) > 0.6 ? '▌' : '█');
                finalClass = headBright > 0.5 ? 'term-holy term-bold' : 'term-holy';
             } else if (absolutePos >= zoneTransition) {
                let distBehind = tracerPos - absolutePos;
                let stabilizeRatio = distBehind / JITTER_BAND;
                let revealChance = 1 / (1 + Math.exp(-10 * (stabilizeRatio - 0.5)));
                revealChance = revealChance * 0.7 + 0.08;
                if (pseudoRand(frameSeed + 1000, absolutePos) < revealChance) {
                   finalChar = sourceChar;
                   finalClass = isTargetHit ? 'term-holy term-bold'
                             : isDictHit ? 'term-amber term-bold'
                             : 'term-brass';
                } else {
                   if (pseudoRand(frameSeed + 2000, absolutePos) < 0.22) {
                      finalChar = sourceChar;
                      finalClass = 'term-enemy';
                   } else {
                      finalChar = GLITCH_GLYPHS[Math.floor(pseudoRand(frameSeed + 3000, absolutePos) * GLITCH_GLYPHS.length)];
                      finalClass = 'term-enemy';
                   }
                }
             } else {
                finalChar = sourceChar;
                finalClass = isTargetHit ? 'term-holy term-bold'
                          : isDictHit ? 'term-success term-bold'
                          : 'term-steel';
             }
             pushSeg(finalChar, finalClass);
          }
          if (curTxt.length) segments.push({ text: curTxt, class: curCls });
          terminal.updateLine(lineIds[y], { text: targetStr, segments });
       }

       // Raw decoder bar
       {
          const hexChars = "0123456789ABCDEF";
          const brailChars = "⣿⣾⣽⣻⢿⡿⣟⣯⣷";
          const progressRatio = tracerPos / BabelAPI.PAGE_LENGTH;
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

       let progressRatio = Math.min(1, tracerPos / BabelAPI.PAGE_LENGTH);
       const totalScore = score + targetBonusScore;
       const currentScore = Math.floor(progressRatio * totalScore);
       terminal.updateLine(liveScoreId, { text: `  [SCORE] ${currentScore}`, class: 'term-steel' });

       // Animate segment visualizer spinner
       vizSpinnerFrame++;
       if (vizSpinnerFrame % 4 === 0) {
         const vizUpdate = buildSegmentVisualizer(segmentStates, vizSpinnerFrame);
         terminal.updateLine(segmentVizId, { text: vizUpdate.text, class: 'term-steel', segments: vizUpdate.segments });
       }

       await sleep(Math.max(15, blockSpeedMs / 200));
    }

    if (!scannerState.running) break;

    // Seal flash
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

    // Mark complete
    segmentStates[seedIndex] = 'complete';
    if (seedIndex === 0) barLocked = true;

    const vizComplete = buildSegmentVisualizer(segmentStates, vizSpinnerFrame);
    terminal.updateLine(segmentVizId, { text: vizComplete.text, class: 'term-steel', segments: vizComplete.segments });

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

    // ── Create akashic record files for this block ──
    const blockSeedNum = Number(BigInt(seed) % BigInt(Number.MAX_SAFE_INTEGER))
    const negativeAddress = computeNegativeAddress(address)
    const negativeTextPos = BabelAPI.addressToText(negativeAddress)
    const machineId = scannerState.machineId

    if (machineId) {
      terminal.write({ text: `  [FILE] Generating akashic records for Block #${blockSeedNum}...`, class: 'term-dim' })
      const fileSpinner = terminal.startSpinner(`file-${blockId}`, '  Writing filesystem...', { speed: 60, class: 'term-dim' })
      await createAkashicFiles(
        machineId,
        blockSeedNum,
        address,
        textPos,
        negativeAddress,
        negativeTextPos,
        scannerState.initiatorIp || scannerState.machineIp
      )
      fileSpinner()
      terminal.write({ text: `  [FILE] ✓ Positive: ak_*.record | ✓ Negative: ak_*.record`, class: 'term-ally' })
      terminal.write({ text: `  [FILE]   Stored under akashic_records/B${String(blockSeedNum).substring(0,2)}/...`, class: 'term-dim' })
    }

    // Accumulate score
    batchScores.push({
      block_id: blockSeedNum,
      score: totalScore,
      matches_count: matches.length
    });

    // Heartbeat: update progress in process_metadata
    if (scannerState.processId && scannerState.onHeartbeat) {
      scannerState.onHeartbeat(seedIndex + 1, activeSegments)
    }

    // ── Storage check: stop mid-loop if HDD full ──
    if (machineId && blocksThatFit > 0 && seedIndex + 1 >= blocksThatFit && seedIndex + 1 < activeSegments) {
      terminal.write({ text: `  ⛔ STORAGE FULL — Scan stopped after ${seedIndex + 1}/${activeSegments} blocks.`, class: 'term-enemy term-bold' })
      terminal.write({ text: `  [SYS] No more blocks will fit on your HDD. Use /delete to free space.`, class: 'term-amber' })
      scannerState.running = false
      break
    }
  }

  if (!scannerState.running) {
    terminal.write({ text: '  [SYS] Sequence Terminated.', class: 'term-brass' })
    scannerState.running = false;
    return
  }

  // ═══════════════════════════════════════════
  // PULSE: Submit all results
  // ═══════════════════════════════════════════
  if (scannerState.processId && batchScores.length > 0) {
    terminal.write({ text: `  [NET] Submitting ${batchScores.length} block results to Akashic Registry...`, class: 'term-dim' })
    const stopPulse = terminal.startSpinner('pulse-final', '  Transmitting...', { speed: 80, class: 'term-dim' })
    try {
      const { data: pulseData, error: pulseErr } = await supabase.functions.invoke('akashic-mining', {
        body: {
          action: 'pulse',
          process_id: scannerState.processId,
          block_scores: batchScores
        }
      })
      stopPulse()
      if (pulseErr) throw new Error(pulseErr.message || 'Edge function error')

      if (pulseData.success) {
        terminal.write({ text: `  [NET] Registered! Score awarded: +${pulseData.total_score_awarded}`, class: 'term-holy term-bold' })
        pulseData.verification_results?.forEach(vr => {
          terminal.write({ text: `    Block #${vr.block_id}: ${vr.is_new ? 'DISCOVERED' : 'Verified'} (+${vr.score})`, class: vr.is_new ? 'term-success' : 'term-dim' })
        })
      } else if (pulseData.retry_after_ms) {
        terminal.write({ text: `  [NET] Pulse too early. Waiting ${Math.round(pulseData.retry_after_ms / 1000)}s...`, class: 'term-amber' })
        await sleep(pulseData.retry_after_ms)
        const retryResult = await supabase.functions.invoke('akashic-mining', {
          body: { action: 'pulse', process_id: scannerState.processId, block_scores: batchScores }
        })
        if (retryResult.data?.success) {
          terminal.write({ text: `  [NET] Registered on retry! Score: +${retryResult.data.total_score_awarded}`, class: 'term-holy term-bold' })
        } else {
          terminal.write({ text: `  [ERR] Pulse rejected: ${retryResult.data?.error || 'Unknown'}`, class: 'term-enemy' })
        }
      } else {
        terminal.write({ text: `  [ERR] Pulse rejected: ${pulseData.error || 'Unknown'}`, class: 'term-enemy' })
      }
    } catch (e) {
      stopPulse()
      terminal.write({ text: `  [ERR] Pulse failed: ${e.message}. Results not recorded.`, class: 'term-enemy' })
    }
  } else {
    terminal.write({ text: '  [SYS] Negative matrix verified (offline/no registration).', class: 'term-amber' })
  }

  terminal.write({ text: '  [SYS] Sequence Complete.', class: 'term-brass' })
  scannerState.running = false;

  // Cleanup: mark process as completed
  if (scannerState.processId) {
    try {
      await supabase.rpc('complete_process', {
        p_process_id: scannerState.processId,
        p_status: 'completed'
      })
      terminal.write({ text: '  [SYS] Process finalized in registry.', class: 'term-dim' })
    } catch (_) {
      // Cron job will handle it
    }
  }
}