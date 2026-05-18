import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useFactions Composable
 *
 * Manages the Factions view data:
 * - Fetches all faction stats via get_factions_overview() RPC
 * - Exposes reactive factionData keyed by sect_type
 * - Provides diamond layout ordering based on player's sect
 * - Display helpers for icons, names, colors, modifier labels
 */

// Display mappings (pure front-end concerns, not game data)
const FACTION_ICONS = {
  gilded_path: '💰',
  holy_way: '🕊️',
  final_watch: '🛡️',
  black_tribunal: '⚖️',
}

const FACTION_NAMES = {
  gilded_path: 'The Gilded Path',
  holy_way: 'The Holy Way',
  final_watch: 'The Final Watch',
  black_tribunal: 'The Black Tribunal',
}

const FACTION_COLORS = {
  gilded_path: { text: 'text-yellow-500', bg: 'bg-yellow-500/10', border: 'border-yellow-500/30' },
  holy_way: { text: 'text-blue-400', bg: 'bg-blue-500/10', border: 'border-blue-500/30' },
  final_watch: { text: 'text-green-500', bg: 'bg-green-500/10', border: 'border-green-500/30' },
  black_tribunal: { text: 'text-red-400', bg: 'bg-red-500/10', border: 'border-red-500/30' },
}

const MODIFIER_LABELS = {
  mana_multiplier: 'Mana Rate',
  gold_multiplier: 'Gold Rate',
  food_multiplier: 'Food Rate',
  food_consumption_multiplier: 'Food Consumed',
  heresy_multiplier: 'Heresy Rate',
  cathedral_upkeep_multiplier: 'Upkeep',
  crusade_defense_bonus: 'Defense',
  inquisition_gold_cost_multiplier: 'Inquisition Cost',
}

function formatModifier(value) {
  const num = parseFloat(value)
  if (isNaN(num)) return String(value)
  const pct = Math.round((num - 1) * 100)
  return pct >= 0 ? `+${pct}%` : `${pct}%`
}

function getModifierLabel(key) {
  return MODIFIER_LABELS[key] || key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
}

let sharedState = null

function createFactionsState() {
  const economy = useEconomy()

  const factionData = ref({})
  const loading = ref(false)
  const error = ref(null)
  const hoveredFaction = ref(null)
  const selectedFaction = ref(null)

  const playerSect = computed(() => economy.sectType)

  /**
   * Fetch all faction overview data from RPC
   */
  async function fetchFactions() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_factions_overview')

      if (rpcError) throw rpcError

      factionData.value = data || {}
    } catch (err) {
      error.value = err.message
      console.error('[useFactions] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Compute diamond layout positions based on player's sect
   * Top = player's faction, Right = ally, Bottom = enemy, Left = neutral
   */
  const diamondPositions = computed(() => {
    const ps = playerSect.value
    const data = factionData.value

    // If player has no faction (or faction data not loaded yet), show default order
    if (!ps || !data[ps]) {
      const keys = ['gilded_path', 'holy_way', 'final_watch', 'black_tribunal']
      return [
        { slot: 'top', key: keys[0], data: data[keys[0]] || null },
        { slot: 'right', key: keys[1], data: data[keys[1]] || null },
        { slot: 'bottom', key: keys[2], data: data[keys[2]] || null },
        { slot: 'left', key: keys[3], data: data[keys[3]] || null },
      ]
    }

    const player = data[ps]
    return [
      { slot: 'top', key: ps, data: player },
      { slot: 'right', key: player.ally, data: data[player.ally] || null },
      { slot: 'bottom', key: player.enemy, data: data[player.enemy] || null },
      { slot: 'left', key: player.neutral, data: data[player.neutral] || null },
    ]
  })

  /**
   * Which faction's relationship lines to highlight
   * Defaults to player's faction; switches on hover
   */
  const activeViewpoint = computed(() => {
    return hoveredFaction.value || playerSect.value || null
  })

  /**
   * Compute SVG line colors and opacities based on active viewpoint
   */
  const lineStyles = computed(() => {
    const vp = activeViewpoint.value
    const dp = diamondPositions.value
    const data = factionData.value

    if (!vp || !data[vp]) {
      return {
        topBottom: { color: '#ef4444', opacity: 0.85 },
        topRight: { color: '#22c55e', opacity: 0.85 },
        topLeft: { color: '#a9b6c4', opacity: 0.25 },
        cross: { color: '#4a4a5a', opacity: 0.06 },
      }
    }

    const vpData = data[vp]
    const topKey = dp.find(p => p.slot === 'top')?.key
    const bottomKey = dp.find(p => p.slot === 'bottom')?.key
    const rightKey = dp.find(p => p.slot === 'right')?.key
    const leftKey = dp.find(p => p.slot === 'left')?.key

    // Top → Bottom: red if it's an enemy relationship, gray otherwise
    const topBottomIsEnemy = vpData.enemy === bottomKey
    const topBottomIsAlly = vpData.ally === bottomKey
    const topBottomColor = topBottomIsEnemy ? '#ef4444' : topBottomIsAlly ? '#22c55e' : '#6b7280'
    const topBottomOpacity = topBottomIsEnemy ? 0.85 : topBottomIsAlly ? 0.85 : 0.15

    // Top → Right: green if it's an ally relationship, gray otherwise
    const topRightIsAlly = vpData.ally === rightKey
    const topRightIsEnemy = vpData.enemy === rightKey
    const topRightColor = topRightIsAlly ? '#22c55e' : topRightIsEnemy ? '#ef4444' : '#6b7280'
    const topRightOpacity = topRightIsAlly ? 0.85 : topRightIsEnemy ? 0.85 : 0.15

    // Top → Left: muted/neutral
    const topLeftIsNeutral = vpData.neutral === leftKey
    const topLeftColor = topLeftIsNeutral ? '#eab308' : '#6b7280'
    const topLeftOpacity = topLeftIsNeutral ? 0.4 : 0.1

    return {
      topBottom: { color: topBottomColor, opacity: topBottomOpacity },
      topRight: { color: topRightColor, opacity: topRightOpacity },
      topLeft: { color: topLeftColor, opacity: topLeftOpacity },
      cross: { color: '#4a4a5a', opacity: 0.06 },
    }
  })

  /**
   * Auto-select player's faction on first data load
   */
  function autoSelectPlayerFaction() {
    if (playerSect.value && factionData.value[playerSect.value]) {
      selectedFaction.value = playerSect.value
    } else if (Object.keys(factionData.value).length > 0) {
      selectedFaction.value = Object.keys(factionData.value)[0]
    }
  }

  return reactive({
    factionData,
    loading,
    error,
    hoveredFaction,
    selectedFaction,
    playerSect,
    diamondPositions,
    activeViewpoint,
    lineStyles,
    fetchFactions,
    autoSelectPlayerFaction,
  })
}

export function useFactions() {
  if (!sharedState) {
    sharedState = createFactionsState()
  }
  return sharedState
}

// Export display helpers as named exports (pure functions, no reactivity)
export { FACTION_ICONS, FACTION_NAMES, FACTION_COLORS, MODIFIER_LABELS, formatModifier, getModifierLabel }