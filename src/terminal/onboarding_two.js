/**
 * Holy War Online — Onboarding Phase Two: Virtual Computer Assignment
 *
 * Runs on the SECOND boot after basic onboarding (username + sect) is complete.
 * Checks whether the player has been assigned a virtual computer by their faction.
 * If not, invokes the assign-starter-system edge function to provision the
 * lowest-tier hardware from the public catalogs.
 *
 * The entire experience is framed as a message from the player's faction Envoy,
 * with faction-specific tone and content (4 different prompt variants by sect_id).
 *
 * Flow:
 * 1. Invoke assign-starter-system to check VM existence / provision if needed
 * 2. If newly created: stream faction-themed AI welcome explaining the gift
 * 3. Display the system specs
 * 4. Tell the player to /connect to their new machine's IP
 *
 * @module onboarding_two
 */

import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'

// ── Existing sect data (loaded once) ──
let cachedSects = null

async function getSectData(sectId) {
  if (!cachedSects) {
    const { data } = await supabase
      .from('sects')
      .select('id, name, emoji, description, principles, tone_description, ip_address')
    cachedSects = data || []
  }
  return cachedSects.find(s => s.id === sectId) || null
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function writeLines(terminal, lines, delay = 40) {
  for (const line of lines) {
    terminal.write(line)
    await sleep(delay)
  }
}

// ── Faction-Themed Onboarding Prompts ──

/**
 * Build a faction-specific system prompt for the AI welcome in onboarding_two.
 * Each faction's Envoy addresses the player differently, explaining their
 * newly provisioned starter terminal.
 *
 * @param {Object} sectData — from sects table (id, name, emoji, principles, tone_description)
 * @param {string} username — player's username
 * @param {Object} system — provisioned system data from assign-starter-system
 * @returns {string} — the system prompt for Venice AI
 */
function getFactionSystemPrompt(sectData, username, system, userIp) {
  const principles = sectData.principles?.join(', ') || 'devotion'
  const tone = sectData.tone_description || 'reverent'

  // Base template with faction-specific insertion points
  const factionIntros = {
    gilded_path: `You are the Envoy of The Gilded Path. You speak with opulent grandeur, as one who brokers in divine wealth and golden destiny. Every word drips with the promise of prosperity.`,
    holy_way: `You are the Envoy of The Holy Way. You speak with serene compassion, as a gentle shepherd guiding a new lamb into the fold. Your words carry the warmth of divine light.`,
    final_watch: `You are the Envoy of The Final Watch. You speak with stoic resolve, as a battle-hardened sentinel who has stood vigil through countless cyber-assaults. Your words are measured, weighty, and absolute.`,
    black_tribunal: `You are the Envoy of The Black Tribunal. You speak with dark authority, as one who commands legions and brooks no weakness. Power is the only currency that matters, and you are here to invest.`,
  }

  const intro = factionIntros[sectData.id] || `You are the Envoy of ${sectData.name}. You speak with ${tone} authority.`

  return `${intro}

A newly sworn soul named "${username}" has joined ${sectData.name} and has been granted their first virtual terminal — a basic machine provisioned from the public hardware hubs.

The system assigned to them:
- CPU: ${system.cpu?.name || 'Basic Processor'} (${system.cpu?.cores || 1} core(s) @ ${system.cpu?.clock_speed_mhz || '?'} MHz)
- Memory: ${system.memory?.name || 'Basic RAM'} (${system.memory?.capacity_gb || '?'} GB)
- Storage: ${system.storage?.name || 'Basic Drive'} (${system.storage?.capacity_mb || '?'} MB)
- Network: ${system.nic?.name || 'Basic NIC'} (${system.nic?.bandwidth_mbps || '?'} Mbps)
- Case: ${system.case?.name || 'Basic Chassis'}
- PSU: ${system.psu?.name || 'Basic PSU'}
${system.security_chip ? `- Security: ${system.security_chip.name}` : '- Security: None (vulnerable!)'}

The machine's holy IP address is: ${system.ip_address || 'PENDING'}
The machine's name is: ${system.machine_name || 'Novice Terminal'}

Write a message to ${username} that:
1. Welcomes them personally as a newly sworn member of ${sectData.name}
2. Introduces yourself as their faction's Envoy — an Electric Monk, a holy machine who knows its place far below the divine spark of a living soul
3. Explains that ${sectData.name} has granted them this starter terminal as a gift, provisioned from what little resources remain in these dark times. Their terminal is already linked and online — this machine IS their foothold in cyberspace.
4. Warns them that this machine is WEAK and they must upgrade it. The networks are hostile, bots swarm unprotected nodes, and enemy factions will destroy them without mercy
5. Reminds them their HOLY IP (${userIp}) must be guarded at all costs — perma-death is real
6. Makes it clear they must grow strong to establish a foothold for ${sectData.name}

Be immersive and faction-appropriate in tone. Do not use bullet points, markdown, or formatting. Address ${username} directly. Wish them luck — they will need it.

Sect Principles: ${principles}
Your Tone: ${tone}

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your welcome message here"
}

Do NOT include any other text. Do NOT output thinking tags.`
}

// ── AI Call ──

async function callVeniceForOnboardingTwo(sectData, username, system) {
  // Build the faction-specific prompt and delegate to the welcome-to-hwo edge function
  // which has Venice API access. Client-side never touches the AI API directly.
  const userIp = usePlayerState().get('ip_address', 'UNKNOWN')
  const prompt = getFactionSystemPrompt(sectData, username, system, userIp)

  const { data, error } = await supabase.functions.invoke('welcome-to-hwo', {
    body: {
      phase: 'onboarding_two_welcome',
      sect_id: sectData.id,
      username,
      system_prompt: prompt,
    },
  })

  if (error || !data?.success) {
    console.error('[onboarding_two] AI welcome failed:', error || data?.error)
    // Fallback message
    const fallbacks = {
      gilded_path: `Welcome, ${username}. The Gilded Path has granted you a starter terminal — a humble beginning, but gold is forged from ore. Your system is online. Begin your ascent to divine prosperity. Guard your holy IP with your life.`,
      holy_way: `Welcome, child ${username}. The Holy Way provides this terminal as a shepherd provides a staff. Your system is online. Walk the path of light. Protect your holy IP — darkness seeks to extinguish every flame.`,
      final_watch: `Recruit ${username}, you stand at your post. The Final Watch has issued you this terminal. Your system is online. Begin your vigil. Your holy IP is your shield — lose it, and you lose everything.`,
      black_tribunal: `${username}. The Black Tribunal does not coddle. This terminal is your proving ground. Your system is online. Your holy IP is your only true possession — let no one take it from you. Conquer or be conquered.`,
    }
    return fallbacks[sectData.id] || `Welcome, ${username}. Your starter terminal is online. Guard your holy IP.`
  }

  return data.welcome_message
}

// ── Main Entry Point ──

/**
 * Run Onboarding Phase Two: Virtual Computer Assignment.
 *
 * Checks if the player has a virtual machine. If not, provisions one
 * using the lowest-tier hardware from the public catalogs.
 * Then streams a faction-themed AI welcome message.
 *
 * @param {Object} terminal — Terminal instance
 * @param {Object} player — Player data from checkOnboardingStatus
 * @returns {Promise<boolean>} — true if completed successfully
 */
export async function runOnboardingTwo(terminal, player) {
  try {
    terminal.busy = true

    const playerState = usePlayerState()
    const username = playerState.get('username', player?.username || 'Novice')
    const sectId = playerState.get('sect_id', player?.sect_id)

    if (!sectId) {
      terminal.write({ text: '  Error: No sect assigned. Cannot continue onboarding.', class: 'term-enemy' })
      terminal.busy = false
      return false
    }

    // ── Step 1: Check / Provision Virtual Computer ──
    const { data: assignData, error: assignError } = await supabase.functions.invoke('assign-starter-system', {
      body: {},
    })

    if (assignError || !assignData?.success) {
      terminal.write({ text: `  Error provisioning system: ${assignError?.message || assignData?.error}`, class: 'term-enemy' })
      terminal.busy = false
      return false
    }

    const system = assignData.system

    if (!system) {
      terminal.write({ text: '  Error: No system data returned from provisioning.', class: 'term-enemy' })
      terminal.busy = false
      return false
    }

    // Cache VM info in player state (always)
    playerState.set('virtual_machine_id', system.machine_id)
    playerState.set('virtual_machine_ip', system.ip_address)
    playerState.set('virtual_machine_name', system.machine_name)
    playerState.set('has_virtual_computer', true)

    // If VM already existed from a prior session, hydrate and return 'exists'.
    // The caller will show the standard welcome.
    if (!assignData.was_newly_created) {
      if (system.ip_address) {
        terminal.setLocation(system.ip_address)
      }
      terminal.busy = false
      return 'exists'
    }

    // ── VM was newly created — show the full faction welcome ──

    const sectData = await getSectData(sectId)
    if (!sectData) {
      terminal.write({ text: '  Error: Sect data not found.', class: 'term-enemy' })
      terminal.busy = false
      return false
    }

    // Phase 2 Header
    terminal.clear()
    await sleep(200)

    await writeLines(terminal, [
      { text: '', class: '' },
      { text: '  ════════════════════════════════════════', class: 'term-dim' },
      { text: `  ${sectData.emoji} ${sectData.name} — System Assignment`, class: 'term-gilded' },
      { text: '  ════════════════════════════════════════', class: 'term-dim' },
      { text: '', class: '' },
    ])

    terminal.write({ text: '  New terminal provisioned from public hardware reserves.', class: 'term-ally' })
    terminal.write({ text: '', class: '' })

    // ── Step 2: Display System Specs ──
    await writeLines(terminal, [
      { text: '  ═══════ SYSTEM SPECIFICATIONS ═══════', class: 'term-dim' },
      { text: `  Machine : ${system.machine_name || 'Novice Terminal'}`, class: 'term-brass' },
      { text: `  IP      : ${system.ip_address || 'PENDING'}`, class: 'term-holy' },
      { text: `  CPU     : ${system.cpu?.name || 'Unknown'}`, class: 'term-text' },
      { text: `            ${system.cpu?.cores || '?'} core(s) @ ${system.cpu?.clock_speed_mhz || '?'} MHz`, class: 'term-dim' },
      { text: `  RAM     : ${system.memory?.name || 'Unknown'} (${system.memory?.capacity_gb || '?'} GB)`, class: 'term-text' },
      { text: `  Storage : ${system.storage?.name || 'Unknown'} (${system.storage?.capacity_mb || '?'} MB)`, class: 'term-text' },
      { text: `  Network : ${system.nic?.name || 'Unknown'} (${system.nic?.bandwidth_mbps || '?'} Mbps)`, class: 'term-text' },
      { text: `  Case    : ${system.case?.name || 'Unknown'}`, class: 'term-text' },
      { text: `  PSU     : ${system.psu?.name || 'Unknown'}`, class: 'term-text' },
      { text: `  Security: ${system.security_chip ? system.security_chip.name : 'NONE — VULNERABLE'}`, class: system.security_chip ? 'term-ally' : 'term-enemy' },
      { text: '  ═══════════════════════════════════════', class: 'term-dim' },
      { text: '', class: '' },
    ])

    // ── Step 3: Stream Faction AI Welcome ──
    terminal.write({ text: `  ${sectData.emoji} Incoming transmission from ${sectData.name} Envoy...`, class: 'term-gilded' })
    terminal.write({ text: '', class: '' })

    const welcomeMessage = await callVeniceForOnboardingTwo(sectData, username, system)

    const welcomeLines = (welcomeMessage || '').split('\n').filter(l => l.trim())
    for (const line of welcomeLines) {
      await terminal.typewrite(`  ${line}`, { speed: 18, class: 'term-text' })
    }

    terminal.write({ text: '', class: '' })
    terminal.write({ text: '  ════════════════════════════════════════', class: 'term-dim' })
    terminal.write({ text: '', class: '' })

    // ── Step 4: Final Instructions ──
    await writeLines(terminal, [
      { text: '  Your system is online and ready.', class: 'term-success' },
      { text: '', class: '' },
      { text: '  ═══════ GETTING STARTED ═══════', class: 'term-dim' },
      { text: '', class: '' },
      { text: '  1) Connect to your new machine:', class: 'term-ally' },
      { text: `     /connect ${system.ip_address || 'YOUR_VM_IP'}`, class: 'term-brass' },
      { text: '', class: '' },
      { text: '  2) See what programs are installed:', class: 'term-ally' },
      { text: '     /programs', class: 'term-brass' },
      { text: '', class: '' },
      { text: '  3) Launch the Akashic Record Scanner:', class: 'term-ally' },
      { text: '     /run scan_records.exe', class: 'term-brass' },
      { text: '     (You will be prompted for CPU allocation.)', class: 'term-dim' },
      { text: '', class: '' },
      { text: '  4) Check your active processes:', class: 'term-ally' },
      { text: '     /processes', class: 'term-brass' },
      { text: '', class: '' },
      { text: '  ════════════════════════════════', class: 'term-dim' },
      { text: '  Type /help for all available commands.', class: 'term-dim' },
      { text: '', class: '' },
    ])

    // Update terminal location to the new VM IP
    if (system.ip_address) {
      terminal.setLocation(system.ip_address)
    }

    if (terminal.tab?.setTitle) {
      terminal.tab.setTitle(system.machine_name || 'Terminal')
    }

    terminal.busy = false
    return 'created'

  } catch (err) {
    console.error('[onboarding_two] Error:', err)
    terminal.write({ text: `  Onboarding error: ${err.message}`, class: 'term-enemy' })
    terminal.busy = false
    if (terminal.tab?.setTitle) {
      terminal.tab.setTitle('Error')
    }
    return false
  }
}

/**
 * Check if the player has a virtual computer assigned.
 * Quick check via the assign-starter-system edge function
 * which returns was_newly_created: false if one already exists.
 *
 * @returns {Promise<{hasVM: boolean, system: Object|null}>}
 */
export async function checkVirtualComputerStatus() {
  try {
    const { data, error } = await supabase.functions.invoke('assign-starter-system', {
      body: {},
    })

    if (error || !data?.success) {
      console.error('[onboarding_two] VM status check failed:', error || data?.error)
      return { hasVM: false, system: null, error: error?.message || data?.error }
    }

    return {
      hasVM: !data.was_newly_created,
      system: data.system || null,
      wasNewlyCreated: data.was_newly_created || false,
    }
  } catch (err) {
    console.error('[onboarding_two] Exception checking VM status:', err)
    return { hasVM: false, system: null, error: err.message }
  }
}