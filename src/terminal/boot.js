/**
 * Holy War Online - Boot Sequence
 * * A themed terminal animation that plays when a user logs in.
 * Simulates connecting to Holy War Online with procedurally generated
 * progress bars, error injection, and interactive text purification.
 * * @param {Object} terminal - Terminal instance
 * @param {number} duration - Total duration in milliseconds
 * @returns {Promise<void>}
 */

import { usePlayerState } from '@/composables/usePlayerState';
import { supabase } from '@/lib/supabase';
import { checkVirtualComputerStatus } from './onboarding_two';

// ── Module-level cache for sacred texts ──
let cachedBibleWords = null;
let bibleLoadPromise = null;

/**
 * Fetch and parse the bible text file into a word array.
 * Caches the result so subsequent calls are instant.
 * @returns {Promise<string[]>} Array of words from the bible
 */
async function loadSacredTexts() {
  if (cachedBibleWords) return cachedBibleWords;
  if (bibleLoadPromise) return bibleLoadPromise;

  bibleLoadPromise = (async () => {
    try {
      const bibleUrl = new URL('../assets/bible_stripped.txt', import.meta.url).href;
      const response = await fetch(bibleUrl);
      const text = await response.text();
      cachedBibleWords = text.toLowerCase().split(/\s+/).filter(w => w.length > 0);
      return cachedBibleWords;
    } catch (err) {
      console.error('[boot] Failed to load sacred texts:', err);
      cachedBibleWords = [
        'THE', 'VOID', 'SPEAKS', 'IN', 'SILENCE',
        'AND', 'THE', 'WORD', 'WAS', 'WITH',
        'GOD', 'FROM', 'THE', 'BEGINNING',
      ];
      return cachedBibleWords;
    }
  })();

  return bibleLoadPromise;
}

/**
 * Grab a sequential fragment of 1–10 words from the bible cache.
 */
function getPropheticFragment(minWords = 1, maxWords = 10) {
  if (!cachedBibleWords || cachedBibleWords.length === 0) {
    return 'THE_VOID_SPEAKS';
  }
  const count = minWords + Math.floor(Math.random() * (maxWords - minWords + 1));
  const maxStart = Math.max(0, cachedBibleWords.length - count);
  const start = Math.floor(Math.random() * maxStart);
  return cachedBibleWords.slice(start, start + count).join(' ');
}

/** Random integer in [min, max] inclusive. */
function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/** Random element from an array. */
function randomChoice(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * Scrambles characters in a string selectively.
 */
function glitchString(str, intensity = 0.15) {
  const glitchChars = '!@#$%^&*()░▒▓█▄▀╔╗╚╝║═╬┼┤├┴└┘┐┌─│';
  return str.split('').map(char => {
    if (char === ' ' || char === '\n' || char === '\r') return char;
    if (Math.random() < intensity) {
      return glitchChars[Math.floor(Math.random() * glitchChars.length)];
    }
    return char;
  }).join('');
}

// ── Procedural boot message pools ──
const INIT_MESSAGES = [
  'Connecting to Holy War Online...',
  'Establishing divine uplink...',
  'Synchronizing prayer cache...',
  'Resolving celestial DNS...',
  'Authenticating with the firmament...',
  'Loading sacred protocols...',
  'Binding daemon processes...',
  'Initializing Electric Monk subsystem...',
  'Tuning prophetic receiver...',
  'Calibrating quantum faith matrix...',
  'Handshaking with the void...',
  'Decrypting angelic firewall...',
  'Compiling liturgical bytecode...',
  'Allocating spiritual heap memory...',
  'Mounting /dev/genesis...',
  'Pinging archangel relay...',
  'Routing intercessory packets...',
  'Verifying canonical checksums...',
  'Initializing blasphemy filter...',
  'Loading faction topology...',
  'Negotiating covenant handshake...',
  'Registering mortal endpoint...',
];

const OK_CLASSES = ['term-ally', 'term-success', 'term-brass', 'term-gilded', 'term-holy'];

// ────────────────────────────────────────────────────────────────

export async function runBootSequence(terminal, duration = 3500) {
  const startTime = Date.now();
  if (terminal.tab?.setTitle) {
    terminal.tab.setTitle("booting HWO");
  }
  
  const bootLogo = [
    '',
    '#  ╔═══════════════════════════════════════════════════════════╗',
    '#  ║                                                           ║',
    '#  ║               ██╗  ██╗ ██╗    ██╗  ██████╗                ║',
    '#  ║               ██║  ██║ ██║    ██║ ██╔═══██╗               ║',
    '#  ║               ███████║ ██║ █╗ ██║ ██║   ██║               ║',
    '#  ║               ██╔══██║ ██║███╗██║ ██║   ██║               ║',
    '#  ║               ██║  ██║ ╚███╔███╔╝ ╚██████╔╝               ║',
    '#  ║               ╚═╝  ╚═╝  ╚══╝╚══╝   ╚═════╝                ║',
    '#  ║                                                           ║',
    '#  ║      H O L Y   W A R   O N L I N E   •   v 1 . 0 . 0      ║',
    '#  ║                                                           ║',
    '#  ╚═══════════════════════════════════════════════════════════╝',
    '',
  ];

  const bibleLoad = loadSacredTexts();
  
  const ps = usePlayerState();
  const dbLoad = checkOnboardingStatus(supabase).then(async ({ player }) => {
    if (player) {
      ps.hydrate(player);
      // Resolve and stash the default IP for this session
      // This ensures no stale data from a previous user's session
      const defaultIp = await ps.resolveDefaultIp();
      ps.defaultConnectionIp.value = defaultIp;
    }
  });

  terminal.clear();
  terminal.busy = true;

  // 2. Render logo lines with persistent unique IDs to target them during boot sequence
  const logoLines = [...bootLogo];
  for (let idx = 0; idx < logoLines.length; idx++) {
    const line = logoLines[idx];
    terminal.write({ id: `boot-logo-${idx}`, text: line, class: 'term-brass' });
    await sleep(randomInt(20, 50));
  }

  await Promise.all([bibleLoad, dbLoad]);
  await sleep(300);

  // Set boot terminal's location now that we've resolved the default IP
  if (ps.defaultConnectionIp.value && ps.defaultConnectionIp.value !== '0.0.0.0') {
    terminal.setLocation(ps.defaultConnectionIp.value);
  }

  const needsOnboarding = !ps.username.value || !ps.sectId.value;

  let minCycles = 5;
  let maxCycles = 7;

  if (needsOnboarding) {
    minCycles = 8;
    maxCycles = 12;
  }
  
  const targetCycles = randomInt(minCycles, maxCycles);

  // ── Procedural boot message loop ──
  for (let cycles = 0; cycles < targetCycles; cycles++) {
    const uid = Math.random().toString(36).substring(2, 9);

    const initMsg = randomChoice(INIT_MESSAGES);
    terminal.write({ text: `  [INIT] ${initMsg}`, class: 'term-dim' });

    const progId = `prog-${uid}`;
    const msgId = `msg-${uid}`;

    const bar = terminal.createProgressBar(progId, {
      width: 10,
      class: 'term-brass',
    });

    const isError = Math.random() < 0.25;
    const totalSteps = 10;
    const errorStep = isError ? randomInt(2, 8) : totalSteps + 1;

    // 2. Render Progress Bar Incrementally and occasionally glitch lines of the logo
    for (let i = 0; i <= totalSteps; i++) {
      if (i === errorStep) break;
      bar.update(i * 10);

      // 15% chance to momentarily glitch a random logo line matching progress stream activity
      if (Math.random() < 0.15) {
        const lineIdx = randomInt(1, bootLogo.length - 2);
        const originalText = bootLogo[lineIdx];
        const glitched = glitchString(originalText, 0.12);
        terminal.updateLine(`boot-logo-${lineIdx}`, { text: glitched, class: 'term-enemy' });
        
        // Swiftly restore line to keep glitch effect punchy and transient
        setTimeout(() => {
          terminal.updateLine(`boot-logo-${lineIdx}`, { text: originalText, class: 'term-brass' });
        }, 150);
      }

      await sleep(randomInt(20, 60));
    }

    if (isError) {
      bar.update(null, { class: 'term-enemy' });
      await sleep(150);

      // Surges error state glitch directly across multiple lines of the logo header
      const glitchedIndices = [];
      const numGlitches = randomInt(3, 6);
      for (let k = 0; k < numGlitches; k++) {
        const lineIdx = randomInt(1, bootLogo.length - 2);
        glitchedIndices.push(lineIdx);
        const originalText = bootLogo[lineIdx];
        const glitched = glitchString(originalText, 0.4);
        terminal.updateLine(`boot-logo-${lineIdx}`, { text: glitched, class: 'term-enemy' });
      }

      const pureText = getPropheticFragment(2, 8);

      const spinId = `spin-${uid}`;
      const stopSpinner = terminal.startSpinner(spinId, '  Purifying payload...', { speed: 80, class: 'term-steel' });

      await terminal.purifyLine(msgId, pureText, {
        glitchPrefix: '  [ERR]  ',
        purePrefix: '  [OK]   ',
        glitchClass: 'term-enemy',
        pureClass: randomChoice(OK_CLASSES),
        intensity: 0.75,
        steps: 6,
        stepDelay: 150,
        fixChance: 0.4,
      });

      stopSpinner();
      await sleep(100);

      // Restore the glitched header segments once the payload is verified/purified
      for (const idx of glitchedIndices) {
        terminal.updateLine(`boot-logo-${idx}`, { text: bootLogo[idx], class: 'term-brass' });
      }

      bar.finish();

    } else {
      bar.finish();
      const pureText = getPropheticFragment(2, 8);
      terminal.updateLine(msgId, { text: `  [OK]   ${pureText}`, class: randomChoice(OK_CLASSES) });
    }

    await sleep(randomInt(100, 250));
  }

  // 3. Revert the logo entirely back to its proper uncorrupted, pristine state
  for (let idx = 0; idx < bootLogo.length; idx++) {
    terminal.updateLine(`boot-logo-${idx}`, { text: bootLogo[idx], class: 'term-brass' });
  }

  // Final separator
  terminal.write({ text: '', class: '' });
  terminal.write({ text: '  ' + '─'.repeat(60), class: 'term-dim' });
  terminal.write({ text: '', class: '' });

  if (terminal.tab?.setTitle) {
    terminal.tab.setTitle("Terminal");
  }
  
  terminal.busy = false;
  await sleep(300);
}

/**
 * Simple sleep utility
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Check if player needs onboarding
 * Calls the database to check onboarding status
 * * @param {Object} supabase - Supabase client instance
 * @returns {Promise<Object>} - { needsOnboarding: boolean, player: Object|null }
 */
export async function checkOnboardingStatus(supabase) {
  try {
    const { data, error } = await supabase.rpc('get_player_status');
    
    if (error) {
      console.error('[boot] Error fetching player status:', error);
      return { needsOnboarding: false, player: null, error };
    }
    
    if (!data || data.error) {
      console.error('[boot] No player data found:', data);
      return { needsOnboarding: false, player: null, error: data?.error || 'No player data' };
    }
    
    const needsOnboarding = !data.onboarding_complete || !data.username || !data.sect_id;
    
    return {
      needsOnboarding,
      player: data,
      error: null,
    };
  } catch (err) {
    console.error('[boot] Exception checking onboarding:', err);
    return { needsOnboarding: false, player: null, error: err };
  }
}

/**
 * Get available sects from database
 * * @param {Object} supabase - Supabase client instance
 * @returns {Promise<Array>} - Array of sect objects
 */
export async function getAvailableSects(supabase) {
  try {
    const { data, error } = await supabase.rpc('get_available_sects');
    
    if (error) {
      console.error('[boot] Error fetching sects:', error);
      return [];
    }
    
    return data || [];
  } catch (err) {
    console.error('[boot] Exception fetching sects:', err);
    return [];
  }
}

// Re-export for TerminalDock.vue
export { checkVirtualComputerStatus };