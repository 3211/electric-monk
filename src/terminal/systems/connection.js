import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'
import { showFactionHomepage } from './faction'

/**
 * Connection system — /connect, /disconnect, /home, /sethome
 * 
 * Connection state is written to usePlayerState() singleton — the single source of truth.
 * All other modules (processManager, faction, player) read from the same singleton,
 * so there's no need to sync ctx properties across modules.
 */

const HOME_STORAGE_KEY = 'hwo_home_ip'

/**
 * Resolve an IP from a shortcut keyword (e.g., "me", "sect").
 * @returns {string|null} the resolved IP or null
 */
async function resolveShortcut(keyword, ctx) {
  const playerState = usePlayerState()
  const playerIp = playerState.get('ip_address', null)
  const factionIp = playerState.get('sect_ip', null)

  if (!keyword) return null

  const kw = keyword.toLowerCase().trim()

  if (kw === 'me' || kw === 'self' || kw === 'my') {
    if (!playerIp) return null
    return playerIp
  }

  if (kw === 'sect' || kw === 'faction' || kw === 'guild') {
    if (!factionIp) {
      try {
        const { data } = await supabase.rpc('get_player_status')
        if (data?.sect_ip) {
          playerState.set('sect_ip', data.sect_ip)
          playerState.set('sect_name', data.sect_name)
          return data.sect_ip
        }
      } catch (_) {}
      return null
    }
    return factionIp
  }

  if (!kw.includes('.')) {
    try {
      const playerStatus = await supabase.rpc('get_player_status')
      const vms = playerStatus?.virtual_machines || []
      const match = vms.find(vm =>
        vm.machine_name.toLowerCase() === kw ||
        vm.ip_address === kw
      )
      if (match) return match.ip_address
    } catch (_) {}
  }

  return kw // Assume it's a raw IP
}

/**
 * Look up an IP address in the game registry.
 * Returns { type: 'player'|'faction'|'machine'|'unknown', data }
 */
async function lookupIp(ip) {
  if (!ip) return { type: 'unknown' }
  // Strip any CIDR suffix for lookup
  const cleanIp = typeof ip === 'string' ? ip.replace(/\/\d+$/, '') : ip
  try {
    const { data: sects } = await supabase
      .from('sects')
      .select('id, name, ip_address, emoji, description')
      .filter('ip_address', 'eq', cleanIp)
    if (sects && sects.length > 0) {
      return { type: 'faction', data: sects[0] }
    }

    const { data: players } = await supabase
      .from('players')
      .select('username, ip_address, sect_id')
      .filter('ip_address', 'eq', cleanIp)
    if (players && players.length > 0) {
      return { type: 'player', data: players[0] }
    }

    const { data: vms } = await supabase
      .from('virtual_machines')
      .select('machine_id, machine_name, ip_address, owner_identity')
      .filter('ip_address', 'eq', cleanIp)
    if (vms && vms.length > 0) {
      return { type: 'machine', data: vms[0] }
    }

    return { type: 'unknown', data: null }
  } catch (e) {
    return { type: 'unknown', data: null, error: e.message }
  }
}

async function logConnection(sourceIp, targetIp, details) {
  try {
    await supabase.rpc('create_log', {
      p_origin_actor: sourceIp,
      p_target_actor: targetIp,
      p_source_ip: sourceIp,
      p_target_ip: targetIp,
      p_details: details || `Connected from ${sourceIp} to ${targetIp}`
    })
  } catch (_) {}
}

export function buildConnectionCommands() {
  return {
    connect: {
      help: 'Connect to a remote terminal. Use /connect <ip>, /connect sect, or /connect me.',
      usage: '/connect <ip|sect|me|machine_name>',
      async handler(args, ctx) {
        const { terminal } = ctx
        const playerState = usePlayerState()
        const target = args[0]

        if (!target) {
          return [
            { text: '  [SYS] Usage: /connect <ip|sect|me|machine_name>', class: 'term-dim' },
            { text: '  [SYS] Examples: /connect 127.0.0.1 | /connect sect | /connect me', class: 'term-dim' }
          ]
        }

        terminal.write({ text: '  [NET] Resolving address...', class: 'term-dim' })

        const resolvedIp = await resolveShortcut(target, ctx)
        if (!resolvedIp) {
          return [{ text: '  [ERR] Could not resolve target address.', class: 'term-enemy' }]
        }

        terminal.write({ text: `  [NET] Connecting to ${resolvedIp}...`, class: 'term-dim' })

        const lookup = await lookupIp(resolvedIp)
        const playerIp = playerState.get('ip_address', 'unknown')

        if (lookup.type === 'faction') {
          // Write to singleton state — all modules now see this
          playerState.setConnection({ ip: resolvedIp, type: 'faction', machineName: `Faction: ${lookup.data.name}` })
          ctx.tab.setTitle(`Faction: ${lookup.data.name}`)

          await logConnection(playerIp, resolvedIp, `Connected to faction: ${lookup.data.name}`)

          const result = await showFactionHomepage(ctx, lookup.data)
          if (result === '__disconnect__') {
            playerState.clearConnection()
            ctx.tab.setTitle('Terminal')
            ctx.terminal.write({ text: '  [SYS] Disconnected. Returned to home terminal.', class: 'term-steel' })
          }
          return null
        }

        if (lookup.type === 'player') {
          const isSelf = resolvedIp === playerIp
          playerState.setConnection({ ip: resolvedIp, type: 'player', machineName: isSelf ? 'My Terminal' : `Player: ${lookup.data.username}` })
          ctx.tab.setTitle(isSelf ? 'My Terminal' : `Player: ${lookup.data.username}`)

          await logConnection(playerIp, resolvedIp, `Connected to player: ${lookup.data.username}`)

          return [
            { text: '  [NET] Connection established.', class: 'term-dim' },
            { text: '', class: '' },
            { text: `  Player: ${lookup.data.username}`, class: 'term-ally' },
            { text: `  IP: ${resolvedIp}`, class: 'term-dim' },
            { text: isSelf ? '  [SELF] You are viewing your own profile.' : '', class: 'term-steel' },
            { text: '', class: '' },
            { text: '  Type /disconnect to return.', class: 'term-dim' }
          ]
        }

        if (lookup.type === 'machine') {
          const ownerIp = lookup.data.owner_identity
          const isOwner = ownerIp === playerIp
          ctx.tab.setTitle(`VM: ${lookup.data.machine_name}`)

          // Write to singleton state
          playerState.setConnection({
            ip: resolvedIp,
            type: 'machine',
            machineId: lookup.data.machine_id,
            access: isOwner ? 'admin' : 'pending',
            machineName: lookup.data.machine_name
          })

          await logConnection(playerIp, resolvedIp,
            `Connected to VM: ${lookup.data.machine_name} (access: ${isOwner ? 'admin' : 'pending'})`)

          const lines = [
            { text: '  [NET] Connection established.', class: 'term-dim' },
            { text: '', class: '' },
            { text: `  Machine: ${lookup.data.machine_name}`, class: 'term-brass' },
            { text: `  IP: ${resolvedIp}`, class: 'term-dim' },
            { text: `  Access: ${isOwner ? 'ADMIN (auto-authenticated)' : 'PENDING (credentials required)'}`, class: isOwner ? 'term-ally' : 'term-enemy' },
            { text: '', class: '' },
          ]

          if (!isOwner) {
            lines.push({ text: '  [AUTH] Credentials required. Use /auth <password> to login.', class: 'term-amber' })
          } else {
            lines.push({ text: '  [OK]  Authenticated. Type /processes to view active processes.', class: 'term-ally' })
          }

          lines.push({ text: '  Type /disconnect to return.', class: 'term-dim' })
          return lines
        }

        // Unknown IP — 405 stub
        return [
          { text: `  [405]  Address ${resolvedIp} is not reachable.`, class: 'term-enemy' },
          { text: '  [SYS] Only faction, player, or virtual machine IPs are accessible.', class: 'term-dim' }
        ]
      }
    },

    disconnect: {
      help: 'Disconnect from the current remote session.',
      usage: '/disconnect',
      handler(args, ctx) {
        const playerState = usePlayerState()
        const prevIp = playerState.connectedIp.value

        if (!prevIp) {
          return [{ text: '  [SYS] Not connected to any remote host.', class: 'term-dim' }]
        }

        playerState.clearConnection()
        ctx.tab.setTitle('Terminal')

        return [
          { text: `  [NET] Disconnected from ${prevIp}.`, class: 'term-dim' },
          { text: '  [SYS] Local terminal restored.', class: 'term-steel' }
        ]
      }
    },

    home: {
      help: 'Navigate to your home terminal. Use /sethome to set your current connection as home.',
      usage: '/home',
      async handler(args, ctx) {
        const { terminal } = ctx
        const playerState = usePlayerState()
        const storedHome = localStorage.getItem(HOME_STORAGE_KEY)
        const playerIp = playerState.get('ip_address', null)

        if (!storedHome) {
          if (!playerIp) {
            return [{ text: '  [ERR] No home terminal set and no player IP found.', class: 'term-enemy' }]
          }
          return ctx.registry['connect'].handler(['me'], ctx)
        }

        terminal.write({ text: `  [NET] Navigating home: ${storedHome}...`, class: 'term-dim' })
        return ctx.registry['connect'].handler([storedHome], ctx)
      }
    },

    sethome: {
      help: 'Set the currently connected terminal as your home. Only works on machines you own.',
      usage: '/sethome',
      handler(args, ctx) {
        const playerState = usePlayerState()
        const connectedIp = playerState.connectedIp.value
        const connectionType = playerState.connectionType.value
        const machineAccess = playerState.machineAccess.value

        if (!connectedIp) {
          return [{ text: '  [ERR] You must be connected to a terminal first.', class: 'term-enemy' }]
        }

        if (connectionType === 'machine' && machineAccess !== 'admin') {
          return [{ text: '  [ERR] You can only set home on machines you own.', class: 'term-enemy' }]
        }

        if (connectionType === 'faction') {
          return [{ text: '  [ERR] Cannot set a faction page as your home terminal.', class: 'term-enemy' }]
        }

        localStorage.setItem(HOME_STORAGE_KEY, connectedIp)
        return [{ text: `  [OK]  Home terminal set to ${connectedIp}.`, class: 'term-ally' }]
      }
    },

    'faction-menu': {
      help: 'Open the faction navigation menu (only when connected to a faction).',
      usage: '/faction-menu',
      hidden: true,
      handler(args, ctx) {
        const playerState = usePlayerState()
        if (playerState.connectionType.value !== 'faction') {
          return [{ text: '  [ERR] Not connected to a faction. Use /connect <faction_ip> first.', class: 'term-enemy' }]
        }
        return null // Handled by faction module
      }
    }
  }
}