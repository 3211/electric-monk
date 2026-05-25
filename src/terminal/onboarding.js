/**
 * Holy War Online - Interactive Onboarding Flow
 *
 * Standalone module that handles new player onboarding using
 * interactive console-style prompts (readLine, readMenu), NOT /commands.
 *
 * The activeSession mechanism in useTerminal.js naturally blocks
 * /commands during readLine sessions — if a user types /help during
 * a name prompt, it will be rejected as an invalid name (symbols).
 *
 * Flow:
 * 1. Check player.username / player.sect_id
 * 2. Stream welcome message for new users
 * 3. Interactive username selection (validate → confirm)
 * 4. Interactive sect selection (arrow key menu → confirm)
 * 5. Stream AI welcome message
 * 6. Show standard greeting
 */

import { supabase } from '@/lib/supabase'
import { getAvailableSects, runBootSequence } from './boot'
import { usePlayerState } from '@/composables/usePlayerState'

// ── Utility Helpers ──

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

/**
 * Write lines to terminal with staggered delay (non-AI output).
 * @param {Object} terminal - Terminal instance
 * @param {Array} lines - Array of { text, class } objects
 * @param {number} delay - Delay between lines in ms (default: 40)
 */
async function writeLines(terminal, lines, delay = 40) {
  for (const line of lines) {
    terminal.write(line)
    await sleep(delay)
  }
}

/**
 * Prompt the user for a line of input.
 * Manages the busy flag: disables input during output,
 * enables it during readLine so the user can type.
 *
 * @param {Object} terminal - Terminal instance
 * @param {string} prompt - Prompt text to display
 * @returns {Promise<string>} - User input (trimmed)
 */
async function promptLine(terminal, prompt) {
  terminal.busy = false
  const input = await terminal.readLine(prompt)
  terminal.busy = true
  return input.trim()
}

/**
 * Prompt the user with an interactive arrow-key menu.
 *
 * @param {Object} terminal - Terminal instance
 * @param {string} prompt - Text to display above the menu
 * @param {Array} options - Array of { label, value } objects
 * @returns {Promise<any>} - The selected value
 */
async function promptMenu(terminal, prompt, options) {
  terminal.busy = false
  const selection = await terminal.readMenu(prompt, options)
  terminal.busy = true
  return selection
}

/**
 * Ask a yes/no confirmation question.
 * Loops until user types y/yes or n/no.
 *
 * @param {Object} terminal - Terminal instance
 * @param {string} question - Question to ask
 * @returns {Promise<boolean>} - true for yes, false for no
 */
async function confirmYesNo(terminal, question) {
  while (true) {
    const answer = await promptLine(terminal, `  ${question} (y/n) > `)
    const lower = answer.toLowerCase()
    if (lower === 'y' || lower === 'yes') return true
    if (lower === 'n' || lower === 'no') return false
    terminal.write({ text: '  Please enter y or n.', class: 'term-enemy' })
  }
}

// ── Username Flow ──

/**
 * Interactive username selection flow.
 * Prompts for username, validates client-side and server-side,
 * then confirms with the user.
 *
 * @param {Object} terminal - Terminal instance
 * @returns {Promise<string>} - The confirmed username
 */
async function runUsernameFlow(terminal) {
  terminal.busy = true

  await writeLines(terminal, [
    { text: '', class: '' },
    { text: '  ════════════════════════════════════════', class: 'term-dim' },
    { text: '  STEP 1: CHOOSE YOUR NAME', class: 'term-gilded' },
    { text: '  ════════════════════════════════════════', class: 'term-dim' },
    { text: '', class: '' },
    { text: '  Your name will echo through the ages.', class: 'term-text' },
    { text: '  3-16 characters. Letters, numbers, and underscores only.', class: 'term-dim' },
    { text: '', class: '' },
  ])

  while (true) {
    const username = await promptLine(terminal, '  Enter your username > ')

    // Client-side validation
    if (!username || username.length < 3) {
      terminal.write({ text: '  Name too short. Minimum 3 characters.', class: 'term-enemy' })
      continue
    }
    if (username.length > 16) {
      terminal.write({ text: '  Name too long. Maximum 16 characters.', class: 'term-enemy' })
      continue
    }
    if (!/^[a-zA-Z0-9_]+$/.test(username)) {
      terminal.write({ text: '  Invalid characters. Only letters, numbers, and underscores allowed.', class: 'term-enemy' })
      continue
    }

    // Server-side validation
    terminal.write({ text: '  Consulting the registry...', class: 'term-dim' })
    const { data, error: validateError } = await supabase.functions.invoke('welcome-to-hwo', {
      body: { phase: 'validate_username', username },
    })

    if (validateError) {
      terminal.write({ text: `  Error: ${validateError.message}`, class: 'term-enemy' })
      continue
    }

    if (!data.success) {
      terminal.write({ text: `  ${data.error}`, class: 'term-enemy' })
      continue
    }

    // Confirm with user
    terminal.write({ text: `  "${username}" — a fine name.`, class: 'term-ally' })
    const confirmed = await confirmYesNo(terminal, `Confirm "${username}" as your name?`)

    if (!confirmed) {
      terminal.write({ text: '  Very well. Choose again.', class: 'term-dim' })
      terminal.write({ text: '', class: '' })
      continue
    }

    // Save username
    terminal.write({ text: '  Inscribing your name...', class: 'term-dim' })
    const { data: saveData, error: saveError } = await supabase.functions.invoke('welcome-to-hwo', {
      body: { phase: 'complete_onboarding', username },
    })

    if (saveError || !saveData.success) {
      terminal.write({ text: `  Failed to save: ${saveError?.message || saveData?.error}`, class: 'term-enemy' })
      continue
    }

    // Cache username in global player state
    const playerState = usePlayerState()
    playerState.set('username', username)

    // Immediately fetch and hydrate player status to get the assigned IP address
    const { data: statusData } = await supabase.rpc('get_player_status')
    if (statusData) {
      playerState.hydrate(statusData)
    }

    terminal.write({ text: `  ✓ Name set: "${username}"`, class: 'term-success' })
    terminal.write({ text: '', class: '' })
    return username
  }
}

// ── Sect Flow ──

/**
 * Interactive sect selection flow.
 * Fetches available sects, displays their lore,
 * prompts for selection via interactive menu, and confirms.
 *
 * @param {Object} terminal - Terminal instance
 * @returns {Promise<Object|null>} - The chosen sect object, or null on failure
 */
async function runSectFlow(terminal, username) {
  terminal.busy = true

  await writeLines(terminal, [
    { text: '', class: '' },
    { text: '  ════════════════════════════════════════', class: 'term-dim' },
    { text: '  STEP 2: CHOOSE YOUR SECT', class: 'term-gilded' },
    { text: '  ════════════════════════════════════════', class: 'term-dim' },
    { text: '', class: '' },
    { text: '  Every soul must pledge to a sect.', class: 'term-text' },
    { text: '  Review the archives below, then make your choice.', class: 'term-dim' },
    { text: '', class: '' },
  ])

  // Fetch sects
  terminal.write({ text: '  Loading sects...', class: 'term-dim' })
  const sects = await getAvailableSects(supabase)

  if (!sects || sects.length === 0) {
    terminal.write({ text: '  No sects available. Please try again later.', class: 'term-enemy' })
    return null
  }

  // Display sect lore (without numbers)
  terminal.write({ text: '', class: '' })
  for (const sect of sects) {
    terminal.write({ text: `  ${sect.emoji} ${sect.name}`, class: 'term-ally' })
    terminal.write({ text: `    ${sect.description || ''}`, class: 'term-text' })
    if (sect.principles && sect.principles.length > 0) {
      terminal.write({ text: `    Principles: ${sect.principles.join(', ')}`, class: 'term-dim' })
    }
    terminal.write({ text: '', class: '' })
  }

  // Map sects to menu options
  const menuOptions = sects.map(sect => ({
    label: `${sect.emoji} ${sect.name}`,
    value: sect
  }))

  while (true) {
    // Interactive arrow-key selection
    const sect = await promptMenu(terminal, '  Select your sect (Arrow Keys + Enter):', menuOptions)

    // Confirm choice
    terminal.write({ text: '', class: '' })
    const confirmed = await confirmYesNo(terminal, `Swear your vow to ${sect.name}?`)
    
    if (!confirmed) {
      terminal.write({ text: '  Very well. Choose again.', class: 'term-dim' })
      terminal.write({ text: '', class: '' })
      continue
    }

    // Generate welcome message via edge function
    terminal.busy = true
    terminal.write({ text: '  Swearing your vow...', class: 'term-dim' })

    // Pull username from global player state (cached during username flow or DB hydration)
    const playerState = usePlayerState()
    const currentUsername = playerState.get('username', 'Warrior')
    const currentIp = playerState.get('ip_address', '0.0.0.0')

    const { data, error } = await supabase.functions.invoke('welcome-to-hwo', {
      body: {
        phase: 'generate_welcome',
        sect_id: sect.id,
        username: currentUsername,
        user_ip: currentIp
      },
    })

    if (error) {
      terminal.write({ text: `  Error: ${error.message}`, class: 'term-enemy' })
      continue
    }

    if (!data.success) {
      terminal.write({ text: `  ${data.error}`, class: 'term-enemy' })
      continue
    }

    // Stream the AI welcome message
    terminal.write({ text: '', class: '' })
    terminal.write({ text: `  ${data.sect_emoji} ${data.sect_name}`, class: 'term-brass' })
    terminal.write({ text: '  ════════════════════════════════════════', class: 'term-dim' })
    terminal.write({ text: '', class: '' })

    const welcomeLines = (data.welcome_message || '').split('\n').filter(l => l.trim())
    for (const line of welcomeLines) {
      await terminal.typewrite(`  ${line}`, { speed: 18, class: 'term-text' })
    }

    // Cache sect selection in global player state
    playerState.set('sect_id', sect.id)
    playerState.set('sect_name', sect.name)
    playerState.set('sect_emoji', sect.emoji)

    terminal.write({ text: '', class: '' })
    terminal.write({ text: '  ════════════════════════════════════════', class: 'term-dim' })
    terminal.write({ text: '', class: '' })

    return sect
  }
}

// ── Main Entry Point ──

/**
 * Run the interactive onboarding flow.
 * Only runs if the player is missing a username or sect.
 *
 * @param {Object} terminal - Terminal instance
 * @param {Object} player - Player data from checkOnboardingStatus
 * @returns {Promise<boolean>} - true if onboarding completed, false if error
 */
export async function runOnboarding(terminal, player) {
  try {
    terminal.busy = true

    // Stream welcome message for brand-new players
    if (!player.username && !player.sect_id) {
      await terminal.typewrite('  A new soul enters the fray...', { speed: 35, class: 'term-gilded' })
      terminal.write({ text: '', class: '' })
      await sleep(400)
    } else if (player.username && !player.sect_id) {
      // Returning player who still needs a sect
      await terminal.typewrite(`  Welcome back, ${player.username}.`, { speed: 35, class: 'term-gilded' })
      terminal.write({ text: '  Your sect awaits.', class: 'term-dim' })
      terminal.write({ text: '', class: '' })
      await sleep(400)
    }

    // Step 1: Username (if missing)
    if (!player.username) {
      await runUsernameFlow(terminal)
    }

    // Step 2: Sect (if missing)
    if (!player.sect_id) {
      const sect = await runSectFlow(terminal)
      if (!sect) {
        // Sect fetch failed — can't complete onboarding
        terminal.busy = false
        return false
      }
    }

    // Onboarding complete — wait for any key, then boot
    terminal.write({ text: '', class: '' })
    terminal.write({ text: '  Press return to initialize your connection...', class: 'term-gilded' })
    
    // Wait for any key press (busy must be false for readLine to work)
    terminal.busy = false
    await terminal.readLine('')
    terminal.busy = true

    // Clear and run full boot sequence
    terminal.clear()
    await runBootSequence(terminal, 4000)

    // Final welcome greeting
    terminal.write({ text: '', class: '' })
    await writeLines(terminal, [
      { text: '  ════════════════════════════════════════', class: 'term-dim' },
      { text: '  Welcome to Holy War Online.', class: 'term-success' },
      { text: '  Type /help for available commands.', class: 'term-dim' },
      { text: '  ════════════════════════════════════════', class: 'term-dim' },
      { text: '', class: '' },
    ])

    // Update the terminal prompt with the player's IP
    const playerState = usePlayerState()
    const { data: statusData } = await supabase.rpc('get_player_status')
    if (statusData && statusData.ip_address) {
      playerState.hydrate(statusData)
      terminal.setLocation(statusData.ip_address)
      // Sync global default — this is the best we have until VM assignment
      playerState.defaultConnectionIp.value = statusData.ip_address
    }

    terminal.busy = false

    // Force terminal scroll calculation once layout shifts
    setTimeout(() => {
      terminal.emit('focusRequest')
    }, 100)
    
    if (terminal.tab?.setTitle) {
    terminal.tab.setTitle("Welcome");
    }  
    return true
  } catch (err) {
    console.error('[onboarding] Error:', err)
    terminal.write({ text: `  Onboarding error: ${err.message}`, class: 'term-enemy' })
    terminal.busy = false
    if (terminal.tab?.setTitle) {
    terminal.tab.setTitle("Error registering");
    }    
    return false
  }
}