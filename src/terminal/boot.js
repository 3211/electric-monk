/**
 * Holy War Online - Boot Sequence
 * 
 * A themed terminal animation that plays when a user logs in.
 * Simulates connecting to Holy War Online with procedurally generated
 * progress bars, error injection, and interactive text purification.
 * 
 * @param {Object} terminal - Terminal instance
 * @param {number} duration - Total duration in milliseconds
 * @returns {Promise<void>}
 */

import { usePlayerState } from '@/composables/usePlayerState';
import { supabase } from '@/lib/supabase';

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
      cachedBibleWords = text.split(/\s+/).filter(w => w.length > 0);
      return cachedBibleWords;
    } catch (err) {
      console.error('[boot] Failed to load sacred texts:', err);
      // Fallback so the boot still works even if the file is missing
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

/**
 * Glitch a string by randomly replacing characters with noise symbols.
 */
function glitchText(text, intensity = 0.2) {
  const glitchChars = '!@#$%^&*░▒▓█▄▀╔╗╚╝║═╬┼┤├┴└┘┐┌─│';
  return text.split('').map(char => {
    // Keep spaces intact to preserve visual word boundaries
    if (char === ' ') return ' ';
    if (Math.random() < intensity) {
      return glitchChars[Math.floor(Math.random() * glitchChars.length)];
    }
    return char;
  }).join('');
}

/** Random integer in [min, max] inclusive. */
function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/** Random element from an array. */
function randomChoice(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
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

  // ASCII Art Header — DO NOT MODIFY
  const bootLogo = [
    '',
    '  ╔═══════════════════════════════════════════════════════════╗',
    '  ║                                                           ║',
    '  ║               ██╗  ██╗ ██╗    ██╗  ██████╗                ║',
    '  ║               ██║  ██║ ██║    ██║ ██╔═══██╗               ║',
    '  ║               ███████║ ██║ █╗ ██║ ██║   ██║               ║',
    '  ║               ██╔══██║ ██║███╗██║ ██║   ██║               ║',
    '  ║               ██║  ██║ ╚███╔███╔╝ ╚██████╔╝               ║',
    '  ║               ╚═╝  ╚═╝  ╚══╝╚══╝   ╚═════╝                ║',
    '  ║                                                           ║',
    '  ║      H O L Y   W A R   O N L I N E   •   v 1 . 0 . 0      ║',
    '  ║                                                           ║',
    '  ╚═══════════════════════════════════════════════════════════╝',
    '',
  ];

  // 1. Start background loaders BEFORE drawing the logo
  const bibleLoad = loadSacredTexts();
  
  const ps = usePlayerState();
  const dbLoad = checkOnboardingStatus(supabase).then(({ player }) => {
    if (player) ps.hydrate(player);
  });

  terminal.clear();
  terminal.busy = true;

  // 2. Render logo (This takes ~1 second, masking the DB request latency!)
  const logoLines = [...bootLogo];
  for (const line of logoLines) {
    terminal.write({ text: line, class: 'term-brass' });
    await sleep(randomInt(20, 50));
  }

  // 3. Ensure both the text file AND database request have finished
  await Promise.all([bibleLoad, dbLoad]);
  await sleep(300);

  // Now the data is guaranteed to be fully hydrated from the server
  const needsOnboarding = !ps.username.value || !ps.sectId.value;

  // Base cycle range for returning players
  let minCycles = 5;
  let maxCycles = 7;

  // Extend the sequence if they are a new player missing a username/sect
  if (needsOnboarding) {
    minCycles = 8;
    maxCycles = 12;
  }

  const targetCycles = randomInt(minCycles, maxCycles);

  // ── Procedural boot message loop ──
  for (let cycles = 0; cycles < targetCycles; cycles++) {
    const uid = Math.random().toString(36).substring(2, 9);
    
    // 1. [INIT] line
    const initMsg = randomChoice(INIT_MESSAGES);
    terminal.write({ text: `  [INIT] ${initMsg}`, class: 'term-dim' });
    
    const progId = `prog-${uid}`;
    const msgId = `msg-${uid}`;
    
    // Roll for an error scenario (25% chance)
    const isError = Math.random() < 0.25;
    const totalSteps = 10;
    const errorStep = isError ? randomInt(2, 8) : totalSteps + 1; // +1 means it never matches
    
    // 2. Render Progress Bar Incrementally
    for (let i = 0; i <= totalSteps; i++) {
      if (i === errorStep) break;
      
      const pct = i * 10;
      const bar = '█'.repeat(i) + '░'.repeat(totalSteps - i);
      // Display yellow (term-brass) loading bar
      terminal.updateLine(progId, { text: `  [${bar}] ${pct}%`, class: 'term-brass' });
      await sleep(randomInt(20, 60));
    }
    
    if (isError) {
      const pct = errorStep * 10;
      const bar = '█'.repeat(errorStep) + '░'.repeat(totalSteps - errorStep);
      
      // Stop and turn the bar RED
      terminal.updateLine(progId, { text: `  [${bar}] ${pct}%`, class: 'term-enemy' });
      await sleep(150);
      
      const pureText = getPropheticFragment(2, 8);
      let currentText = glitchText(pureText, 0.75); // Heavily corrupted
      
      // Output glitched [ERR] message
      terminal.updateLine(msgId, { text: `  [ERR]  ${currentText}`, class: 'term-enemy' });
      
      // Start recovery spinner
      const spinId = `spin-${uid}`;
      const stopSpinner = terminal.startSpinner(spinId, '  Purifying payload...', { speed: 80, class: 'term-steel' });
      
      // De-corrupt the text progressively
      const recoverySteps = 6;
      for (let r = 0; r < recoverySteps; r++) {
        await sleep(150);
        let nextText = '';
        for (let c = 0; c < pureText.length; c++) {
          // Keep pure text chars, randomly fix corrupted chars. Force fix all on the last step.
          if (currentText[c] !== pureText[c] && (Math.random() < 0.4 || r === recoverySteps - 1)) {
            nextText += pureText[c];
          } else {
            nextText += currentText[c];
          }
        }
        currentText = nextText;
        terminal.updateLine(msgId, { text: `  [ERR]  ${currentText}`, class: 'term-enemy' });
      }
      
      // Stop spinner once recovered
      stopSpinner();
      await sleep(100);
      
      // Turn progress bar full GREEN
      terminal.updateLine(progId, { text: `  [██████████] 100%`, class: 'term-ally' });
      // Convert to [OK]
      terminal.updateLine(msgId, { text: `  [OK]   ${pureText}`, class: randomChoice(OK_CLASSES) });

    } else {
      // Success branch: Finish progress bar (GREEN)
      terminal.updateLine(progId, { text: `  [██████████] 100%`, class: 'term-ally' });
      const pureText = getPropheticFragment(2, 8);
      terminal.updateLine(msgId, { text: `  [OK]   ${pureText}`, class: randomChoice(OK_CLASSES) });
    }

    // Jitter between major blocks
    await sleep(randomInt(100, 250));
  }

  // Final separator
  terminal.write({ text: '', class: '' });
  terminal.write({ text: '  ' + '─'.repeat(60), class: 'term-dim' });
  terminal.write({ text: '', class: '' });

  // Unblock input
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
 * 
 * @param {Object} supabase - Supabase client instance
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
 * 
 * @param {Object} supabase - Supabase client instance
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