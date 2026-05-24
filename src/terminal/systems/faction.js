import { supabase } from '@/lib/supabase'

/**
 * Faction system — ASCII homepages with arrow-key navigation menus.
 * Renders when /connect <faction_ip> is used.
 * 
 * Pages: Welcome, About, Members, Shop (stub), Forums (stub)
 */

const FACTION_PAGES = ['welcome', 'about', 'members', 'shop', 'forums']
const PAGE_LABELS = {
  welcome: 'WELCOME',
  about: 'ABOUT',
  members: 'MEMBERS',
  shop: 'SHOP',
  forums: 'FORUMS'
}

/**
 * Generate ASCII art header for a faction.
 */
function factionAsciiHeader(name, emoji) {
  const bar = '═'.repeat(60)
  const padded = `  ${emoji}  ${name.toUpperCase()}  ${emoji}`
  const padLeft = Math.max(0, Math.floor((60 - padded.length) / 2))
  return [
    { text: `  ${bar}`, class: 'term-holy' },
    { text: `  ${' '.repeat(padLeft)}${padded}`, class: 'term-holy term-bold' },
    { text: `  ${bar}`, class: 'term-holy' },
    { text: '', class: '' }
  ]
}

/**
 * Render the navigation menu with current page highlighted.
 */
function renderNav(currentPage) {
  const items = FACTION_PAGES.map(p => {
    const label = PAGE_LABELS[p]
    const isActive = p === currentPage
    return {
      text: isActive ? `[${label}]` : ` ${label} `,
      class: isActive ? 'term-holy term-bold' : 'term-steel'
    }
  })

  // Interleave with separators
  const nav = []
  items.forEach((item, i) => {
    if (i > 0) nav.push({ text: ' │ ', class: 'term-dim' })
    nav.push(item)
  })

  return [
    { text: '  Use ← → arrow keys to navigate | Press ENTER to select', class: 'term-dim' },
    ...nav,
    { text: '', class: '' },
    { text: '  ' + '─'.repeat(60), class: 'term-dim' },
    { text: '', class: '' }
  ]
}

/**
 * Fetch faction member count.
 */
async function getFactionMembers(factionId) {
  try {
    const { count, error } = await supabase
      .from('players')
      .select('*', { count: 'exact', head: true })
      .eq('sect_id', factionId)
      .eq('onboarding_complete', true)
    if (error) return 0
    return count || 0
  } catch (_) {
    return 0
  }
}

/**
 * Fetch total akashic score for a faction.
 */
async function getFactionScore(factionIp) {
  try {
    const { data } = await supabase
      .from('network_addresses')
      .select('akashic_score')
      .eq('ip_address', factionIp)
      .single()
    return data?.akashic_score || 0
  } catch (_) {
    return 0
  }
}

/**
 * Render the WELCOME page.
 */
async function renderWelcome(faction) {
  const memberCount = await getFactionMembers(faction.id)
  const totalScore = await getFactionScore(faction.ip_address)

  return [
    { text: '  ╔══════════════════════════════════════════════════════════╗', class: 'term-holy' },
    { text: '  ║  Welcome to the faction homepage. Glory to the cause.    ║', class: 'term-brass' },
    { text: '  ╚══════════════════════════════════════════════════════════╝', class: 'term-holy' },
    { text: '', class: '' },
    { text: `  Faction: ${faction.emoji} ${faction.name}`, class: 'term-ally term-bold' },
    { text: `  Members: ${memberCount}`, class: 'term-steel' },
    { text: `  Akashic Score: ${totalScore.toLocaleString()}`, class: 'term-brass' },
    { text: '', class: '' },
    { text: '  ── Quick Stats ──', class: 'term-dim' },
    { text: `  IP: ${faction.ip_address}`, class: 'term-dim' },
    { text: `  Faction ID: ${faction.id}`, class: 'term-dim' },
    { text: '', class: '' }
  ]
}

/**
 * Render the ABOUT page.
 */
async function renderAbout(faction) {
  return [
    { text: '  ╔══════════════════════════════════════════════════════════╗', class: 'term-holy' },
    { text: '  ║  About the Faction                                       ║', class: 'term-brass' },
    { text: '  ╚══════════════════════════════════════════════════════════╝', class: 'term-holy' },
    { text: '', class: '' },
    { text: `  ${faction.emoji} ${faction.name}`, class: 'term-ally term-bold' },
    { text: '', class: '' },
    ...wrapText(faction.description || 'No description available.', 56).map(t =>
      ({ text: `  ${t}`, class: 'term-steel' })
    ),
    { text: '', class: '' },
    { text: `  Principles:`, class: 'term-brass' },
    ...(faction.principles || []).map(p =>
      ({ text: `    • ${p}`, class: 'term-ally' })
    ),
    { text: '', class: '' }
  ]
}

/**
 * Render the MEMBERS page (top members by akashic score).
 */
async function renderMembers(faction) {
  try {
    const { data: members } = await supabase
      .from('players')
      .select('username, ip_address')
      .eq('sect_id', faction.id)
      .eq('onboarding_complete', true)
      .limit(20)

    const lines = [
      { text: '  ╔══════════════════════════════════════════════════════════╗', class: 'term-holy' },
      { text: '  ║  Faction Members                                         ║', class: 'term-brass' },
      { text: '  ╚══════════════════════════════════════════════════════════╝', class: 'term-holy' },
      { text: '', class: '' }
    ]

    if (!members || members.length === 0) {
      lines.push({ text: '  No members found.', class: 'term-dim' })
    } else {
      for (let i = 0; i < members.length; i++) {
        const m = members[i]
        const num = (i + 1).toString().padStart(2, ' ')
        lines.push({
          text: `  ${num}. ${m.username || 'Unknown'}  (${m.ip_address})`,
          class: 'term-steel'
        })
      }
    }

    lines.push({ text: '', class: '' })
    return lines
  } catch (_) {
    return [
      { text: `  Could not load member list.`, class: 'term-enemy' }
    ]
  }
}

/**
 * Render the SHOP page (stub).
 */
function renderShop(faction) {
  return [
    { text: '  ╔══════════════════════════════════════════════════════════╗', class: 'term-holy' },
    { text: '  ║  Faction Shop                                            ║', class: 'term-brass' },
    { text: '  ╚══════════════════════════════════════════════════════════╝', class: 'term-holy' },
    { text: '', class: '' },
    { text: '  [STUB] Faction shop not yet implemented.', class: 'term-dim' },
    { text: '  Coming in a future update.', class: 'term-steel' },
    { text: '', class: '' }
  ]
}

/**
 * Render the FORUMS page (stub).
 */
function renderForums(faction) {
  return [
    { text: '  ╔══════════════════════════════════════════════════════════╗', class: 'term-holy' },
    { text: '  ║  Faction Forums                                          ║', class: 'term-brass' },
    { text: '  ╚══════════════════════════════════════════════════════════╝', class: 'term-holy' },
    { text: '', class: '' },
    { text: '  [STUB] Faction forums not yet implemented.', class: 'term-dim' },
    { text: '  Coming in a future update.', class: 'term-steel' },
    { text: '', class: '' }
  ]
}

/**
 * Wrap text to a max width.
 */
function wrapText(text, maxWidth) {
  const words = text.split(/\s+/)
  const lines = []
  let current = ''
  for (const word of words) {
    if ((current + ' ' + word).trim().length > maxWidth && current.length > 0) {
      lines.push(current.trim())
      current = word
    } else {
      current += ' ' + word
    }
  }
  if (current.trim().length > 0) lines.push(current.trim())
  return lines
}

/**
 * Full page renderer for faction homepage.
 * @param {object} faction - Faction row from DB
 * @param {string} page - which page to render
 * @returns {Array<{text, class}>}
 */
async function renderPage(faction, page) {
  const header = factionAsciiHeader(faction.name, faction.emoji)
  const nav = renderNav(page)
  let body

  switch (page) {
    case 'welcome': body = await renderWelcome(faction); break
    case 'about': body = await renderAbout(faction); break
    case 'members': body = await renderMembers(faction); break
    case 'shop': body = renderShop(faction); break
    case 'forums': body = renderForums(faction); break
    default: body = await renderWelcome(faction); break
  }

  return [...header, ...nav, ...body]
}

/**
 * Command that renders the faction interactive homepage.
 * Call this after /connect <faction_ip> succeeds.
 */
export async function showFactionHomepage(ctx, faction) {
  const { terminal } = ctx
  terminal.clear()

  let currentPage = 'welcome'

  const render = async () => {
    terminal.clear()
    const lines = await renderPage(faction, currentPage)
    for (const line of lines) {
      terminal.write(line)
    }
  }

  await render()

  // Arrow key navigation via readLine (intercepts arrow key codes in the terminal)
  // The terminal API will need to support this; for now we output instructions.
  terminal.write({ text: '  [NAV] Use /faction-nav <page> to switch pages.', class: 'term-dim' })
  terminal.write({ text: `  Pages: ${FACTION_PAGES.join(', ')}`, class: 'term-steel' })

  // Return the render function so commands can re-render
  ctx._factionRenderer = { render, currentPage, faction }
}

/**
 * Command to navigate faction pages.
 */
export function buildFactionCommands() {
  return {
    'faction-nav': {
      help: 'Navigate faction pages. Use /faction-nav <page> when connected to a faction.',
      usage: '/faction-nav <welcome|about|members|shop|forums>',
      hidden: true,
      async handler(args, ctx) {
        if (ctx.connection_type !== 'faction') {
          return [{ text: '  [ERR] Not connected to a faction.', class: 'term-enemy' }]
        }

        const page = (args[0] || 'welcome').toLowerCase()
        if (!FACTION_PAGES.includes(page)) {
          return [{ text: `  [ERR] Unknown page: ${page}. Valid: ${FACTION_PAGES.join(', ')}`, class: 'term-enemy' }]
        }

        if (!ctx._factionRenderer) {
          return [{ text: '  [ERR] Faction renderer not initialized. Reconnect.', class: 'term-enemy' }]
        }

        ctx._factionRenderer.currentPage = page
        await ctx._factionRenderer.render()
        return null
      }
    }
  }
}