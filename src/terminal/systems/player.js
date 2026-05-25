import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'

/**
 * Player system — renders public player cards and the "me" settings page.
 * 
 * /connect <player_ip> → public overview (no sensitive info, no IPs of VMs, no system details)
 * /connect me → personal settings/overview (full details, VM list, quick-connect)
 */

/**
 * Fetch public player stats for a player overview card.
 */
async function getPlayerCard(ipAddress) {
  try {
    const { data: player } = await supabase
      .from('players')
      .select('username, ip_address, sect_id')
      .eq('ip_address', ipAddress)
      .single()

    if (!player) return null

    // Get faction info
    let faction = null
    if (player.sect_id) {
      const { data: sects } = await supabase
        .from('sects')
        .select('name, emoji')
        .eq('id', player.sect_id)
      if (sects && sects.length > 0) faction = sects[0]
    }

    // Get akashic score
    const { data: netData } = await supabase
      .from('network_addresses')
      .select('akashic_score')
      .eq('ip_address', ipAddress)
      .maybeSingle()

    return {
      username: player.username,
      ip_address: player.ip_address,
      faction_name: faction?.name || null,
      faction_emoji: faction?.emoji || null,
      akashic_score: netData?.akashic_score || 0
    }
  } catch (_) {
    return null
  }
}

/**
 * Fetch full personal stats for "me" page.
 */
async function getMyFullProfile() {
  const playerState = usePlayerState()
  const playerIp = playerState.get('ip_address', null)
  if (!playerIp) return null

  try {
    // Player status
    const { data: status } = await supabase.rpc('get_player_status')
    if (!status) return null

    // My VMs
    const { data: vms } = await supabase
      .from('virtual_machines')
      .select('machine_id, machine_name, ip_address, cpu_id, memory_id, storage_id')
      .eq('owner_identity', playerIp)

    // Akashic score
    const { data: netData } = await supabase
      .from('network_addresses')
      .select('akashic_score')
      .eq('ip_address', playerIp)
      .maybeSingle()

    // Recent completed scans
    const { data: scans } = await supabase
      .from('akashic_scans_completed')
      .select('score_awarded, end_time, blocks_processed')
      .eq('machine_ip', playerIp)
      .order('end_time', { ascending: false })
      .limit(5)

    return {
      ...status,
      akashic_score: netData?.akashic_score || 0,
      virtual_machines: vms || [],
      recent_scans: scans || []
    }
  } catch (_) {
    return null
  }
}

/**
 * Render the public player card.
 */
function renderPublicCard(playerData) {
  const bar = '═'.repeat(50)
  const lines = [
    { text: `  ${bar}`, class: 'term-dim' },
    { text: `  PLAYER CARD`, class: 'term-brass term-bold' },
    { text: `  ${bar}`, class: 'term-dim' },
    { text: '', class: '' },
    { text: `  Username:    ${playerData.username || 'Unknown'}`, class: 'term-ally term-bold' },
    { text: `  Faction:     ${playerData.faction_emoji || ''} ${playerData.faction_name || 'No Faction'}`, class: playerData.faction_name ? 'term-ally' : 'term-dim' },
    { text: `  Akashic:     ${playerData.akashic_score.toLocaleString()} pts`, class: 'term-brass' },
    { text: '', class: '' },
    { text: `  ${bar}`, class: 'term-dim' },
    { text: `  [PUBLIC] This player's system details are hidden.`, class: 'term-steel' },
    { text: `  ${bar}`, class: 'term-dim' },
    { text: '', class: '' }
  ]
  return lines
}

/**
 * Render the personal "Me" page with full details.
 */
function renderMePage(profile) {
  const bar = '═'.repeat(56)

  const lines = [
    { text: `  ${bar}`, class: 'term-holy' },
    { text: `  MY TERMINAL`, class: 'term-brass term-bold' },
    { text: `  ${bar}`, class: 'term-holy' },
    { text: '', class: '' },
    { text: `  Username:    ${profile.username || '(not set)'}`, class: 'term-ally term-bold' },
    { text: `  Holy IP:     ${profile.ip_address || '(unassigned)'}`, class: 'term-holy' },
    { text: `  Faction:     ${profile.sect_emoji || ''} ${profile.sect_name || 'No Faction'}`, class: profile.sect_name ? 'term-ally' : 'term-dim' },
    { text: `  Akashic:     ${(profile.akashic_score || 0).toLocaleString()} pts`, class: 'term-brass' },
    { text: '', class: '' }
  ]

  // Virtual Machines
  lines.push({ text: `  ── My Machines ──`, class: 'term-steel' })
  if (profile.virtual_machines && profile.virtual_machines.length > 0) {
    profile.virtual_machines.forEach((vm, i) => {
      lines.push({
        text: `  [${i + 1}] ${vm.machine_name} — ${vm.ip_address}`,
        class: 'term-ally'
      })
      lines.push({
        text: `      /connect ${vm.ip_address}  to access`,
        class: 'term-dim'
      })
    })
  } else {
    lines.push({ text: '  No virtual machines assigned.', class: 'term-enemy' })
  }
  lines.push({ text: '', class: '' })

  // Recent scans
  lines.push({ text: `  ── Recent Akashic Activity ──`, class: 'term-steel' })
  if (profile.recent_scans && profile.recent_scans.length > 0) {
    profile.recent_scans.forEach(scan => {
      const date = new Date(scan.end_time).toLocaleDateString()
      lines.push({
        text: `  ${date} — ${scan.blocks_processed} blocks | +${scan.score_awarded} pts`,
        class: 'term-brass'
      })
    })
  } else {
    lines.push({ text: '  No completed scans yet.', class: 'term-dim' })
  }
  lines.push({ text: '', class: '' })
  lines.push({ text: `  ${bar}`, class: 'term-holy' })
  lines.push({ text: `  /sethome to set this as your home terminal`, class: 'term-dim' })
  lines.push({ text: `  ${bar}`, class: 'term-holy' })
  lines.push({ text: '', class: '' })

  return lines
}

export function buildPlayerCommands() {
  return {
    'player-card': {
      help: 'View a public player card when connected to a player.',
      usage: '/player-card',
      hidden: true,
      async handler(args, ctx) {
        if (ctx.connection_type !== 'player') {
          return [{ text: '  [ERR] Not connected to a player.', class: 'term-enemy' }]
        }

        const isSelf = ctx.connected_ip === usePlayerState().get('ip_address', null)
        const { terminal } = ctx

        if (isSelf) {
          ctx.tab.setTitle('My Terminal')
          const profile = await getMyFullProfile()
          if (!profile) {
            return [{ text: '  [ERR] Could not load profile.', class: 'term-enemy' }]
          }
          return renderMePage(profile)
        }

        const playerData = await getPlayerCard(ctx.connected_ip)
        if (!playerData) {
          return [{ text: '  [ERR] Player not found.', class: 'term-enemy' }]
        }
        return renderPublicCard(playerData)
      }
    },

    'me': {
      help: 'View your own profile and machine list. Shortcut for /connect me.',
      usage: '/me',
      async handler(args, ctx) {
        const playerState = usePlayerState()
        const playerIp = playerState.get('ip_address', null)
        if (!playerIp) {
          return [{ text: '  [ERR] No player IP assigned.', class: 'term-enemy' }]
        }

        const profile = await getMyFullProfile()
        if (!profile) {
          return [{ text: '  [ERR] Could not load profile.', class: 'term-enemy' }]
        }

        // Use the proper connection state APIs so all modules stay in sync
        playerState.setConnection({ ip: playerIp, type: 'player', machineName: 'My Terminal' })
        ctx.tab.setTitle('My Terminal')
        ctx.terminal.setLocation(playerIp)
        playerState.defaultConnectionIp.value = playerIp
        return renderMePage(profile)
      }
    }
  }
}