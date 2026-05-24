import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'
import { showFactionHomepage } from './faction'

/**
 * Connection system — /connect, /disconnect, /home, /sethome
 * 
 * Tracks connected_ip per terminal context (ctx).
 * Logs all connections to connection_logs via the create_log RPC.
 * Supports shortcuts: /connect sect, /connect me
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
      // Try to fetch from DB
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

  // If it's a VM name, try to resolve
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
  try {
    // Check if it's a faction IP
    const { data: sects } = await supabase
      .from('sects')
      .select('id, name, ip_address, emoji, description')
      .eq('ip_address', ip)
    if (sects && sects.length > 0) {
      return { type: 'faction', data: sects[0] }
    }

    // Check if it's a player IP
    const { data: players } = await supabase
      .from('players')
      .select('username, ip_address, sect_id')
      .eq('ip_address', ip)
    if (players && players.length > 0) {
      return { type: 'player', data: players[0] }
    }

    // Check if it's a VM IP
    const { data: vms } = await supabase
      .from('virtual_machines')
      .select('machine_id, machine_name, ip_address, owner_identity')
      .eq('ip_address', ip)
    if (vms && vms.length > 0) {
      return { type: 'machine', data: vms[0] }
    }

    return { type: 'unknown', data: null }
  } catch (e) {
    return { type: 'unknown', data: null, error: e.message }
  }
}

/**
 * Log a connection event to connection_logs.
 */
async function logConnection(sourceIp, targetIp, details) {
  try {
    await supabase.rpc('create_log', {
      p_origin_actor: sourceIp,
      p_target_actor: targetIp,
      p_source_ip: sourceIp,
      p_target_ip: targetIp,
      p_details: details || `Connected from ${sourceIp} to ${targetIp}`
    })
  } catch (_) {
    // Logging is non-fatal
  }
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
          ctx.connected_ip = resolvedIp
          ctx.connection_type = 'faction'
          ctx.tab.setTitle(`Faction: ${lookup.data.name}`)

          await logConnection(playerIp, resolvedIp, `Connected to faction: ${lookup.data.name}`)

          // Render the faction ASCII homepage with navigation
          await showFactionHomepage(ctx, lookup.data)
          return null
        }

        if (lookup.type === 'player') {
          ctx.connected_ip = resolvedIp
          ctx.connection_type = 'player'
          const isSelf = resolvedIp === playerIp
          ctx.tab.setTitle(isSelf ? 'My Terminal' : `Player: ${lookup.data.username}`)

          await logConnection(playerIp, resolvedIp, `Connected to player: ${lookup.data.username}`)

          return [
            { text: '  [NET] Connection established.', class: 'term-dim' },
            { text: '', class: '' },
            { text: `  Player: ${lookup.data.username}`, class: 'term-ally' },
            { text: `  IP: ${resolvedIp}`, class: 'term-dim' },
            { text: isSelf ? '  [SELF] You are viewing your own profile.', class: 'term-steel' : '' },
            { text: '', class: '' },
            { text: '  Type /disconnect to return.', class: 'term-dim' }
          ]
        }

        if (lookup.type === 'machine') {
          ctx.connected_ip = resolvedIp
          ctx.connection_type = 'machine'
          const ownerIp = lookup.data.owner_identity
          const isOwner = ownerIp === playerIp
          ctx.tab.setTitle(`VM: ${lookup.data.machine_name}`)

          // Check if owner — if so, autofill credentials
          if (isOwner) {
            ctx.machine_access = 'admin'
            ctx.machine_id = lookup.data.machine_id
          } else {
            ctx.machine_access = 'pending'
            ctx.machine_id = lookup.data.machine_id
          }

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
        if (!ctx.connected_ip) {
          return [{ text: '  [SYS] Not connected to any remote host.', class: 'term-dim' }]
        }

        const prevIp = ctx.connected_ip
        ctx.connected_ip = null
        ctx.connection_type = null
        ctx.machine_access = null
        ctx.machine_id = null
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
          // Default to player's own IP
          if (!playerIp) {
            return [{ text: '  [ERR] No home terminal set and no player IP found.', class: 'term-enemy' }]
          }
          // Navigate to self
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
        if (!ctx.connected_ip) {
          return [{ text: '  [ERR] You must be connected to a terminal first.', class: 'term-enemy' }]
        }

        const playerState = usePlayerState()
        const playerIp = playerState.get('ip_address', null)

        // Only allow setting home on machines you own or your own IP
        if (ctx.connection_type === 'machine' && ctx.machine_access !== 'admin') {
          return [{ text: '  [ERR] You can only set home on machines you own.', class: 'term-enemy' }]
        }

        if (ctx.connection_type === 'faction') {
          return [{ text: '  [ERR] Cannot set a faction page as your home terminal.', class: 'term-enemy' }]
        }

        localStorage.setItem(HOME_STORAGE_KEY, ctx.connected_ip)
        return [{ text: `  [OK]  Home terminal set to ${ctx.connected_ip}.`, class: 'term-ally' }]
      }
    },

    'faction-menu': {
      help: 'Open the faction navigation menu (only when connected to a faction).',
      usage: '/faction-menu',
      hidden: true,
      handler(args, ctx) {
        if (ctx.connection_type !== 'faction') {
          return [{ text: '  [ERR] Not connected to a faction. Use /connect <faction_ip> first.', class: 'term-enemy' }]
        }
        // Delegates to faction homepage renderer
        return null // Handled by faction module
      }
    }
  }
}