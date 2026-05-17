import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useEconomy Composable
 *
 * Manages the 4-resource economy state (Karma, Mana, Gold, Food):
 * - Fetches player resources and buildings from get_player_economy RPC
 * - Computes daily production rates net of upkeep
 * - Provides building counts and production summaries
 * - Shared state pattern so all components see the same economy data
 */

let sharedState = null

function createEconomyState() {
  const mana = ref(0)
  const gold = ref(0)
  const food = ref(0)
  const buildings = ref([])
  const dailyRates = ref({
    mana_per_day: 0,
    gold_per_day: 0,
    food_per_day: 0,
    gold_upkeep_per_day: 0,
    food_consumption_per_day: 0,
  })
  const gameConfig = ref({})
  const loading = ref(false)
  const error = ref(null)

  // Computed: net production rates
  const netManaPerDay = computed(() => dailyRates.value.mana_per_day || 0)
  const netGoldPerDay = computed(() => {
    const production = dailyRates.value.gold_per_day || 0
    const upkeep = dailyRates.value.gold_upkeep_per_day || 0
    return production - upkeep
  })
  const netFoodPerDay = computed(() => {
    const production = dailyRates.value.food_per_day || 0
    const consumption = dailyRates.value.food_consumption_per_day || 0
    return production - consumption
  })

  // Computed: building counts by type
  const buildingCounts = computed(() => {
    const counts = {}
    for (const b of buildings.value) {
      if (b.is_active) {
        counts[b.building_type] = (counts[b.building_type] || 0) + 1
      }
    }
    return counts
  })

  // Computed: resource caps based on daily rates and config multipliers
  const manaCap = computed(() => {
    const multiplier = gameConfig.value['cap.mana_multiplier'] || 10
    return Math.floor((dailyRates.value.mana_per_day || 0) * multiplier)
  })
  const goldCap = computed(() => {
    const multiplier = gameConfig.value['cap.gold_multiplier'] || 10
    return Math.floor((dailyRates.value.gold_per_day || 0) * multiplier)
  })
  const foodCap = computed(() => {
    const multiplier = gameConfig.value['cap.food_multiplier'] || 10
    return Math.floor((dailyRates.value.food_per_day || 0) * multiplier)
  })

  // Emoji mappings for resource display
  const resourceEmojis = {
    karma: '\u2726',       // ✦
    mana: '\u{1F4A7}',    // 💧
    gold: '\u{1F4B0}',    // 💰
    food: '\u{1F33E}',    // 🌾
  }

  // Building display names and icons — 5 tiers per category
  const buildingInfo = {
    // Mana Estates: Altar 🕯️ → Shrine ⛩️ → Temple 🏛️ → Church ⛪ → Cathedral 🏰
    altar:     { name: 'Altar',     icon: '\u{1F56F}',  tier: 1, category: 'mana' },
    shrine:    { name: 'Shrine',    icon: '\u26E9',     tier: 2, category: 'mana' },
    temple:    { name: 'Temple',    icon: '\u{1F3DB}',  tier: 3, category: 'mana' },
    church:    { name: 'Church',    icon: '\u26EA',     tier: 4, category: 'mana' },
    cathedral: { name: 'Cathedral', icon: '\u{1F3F0}',  tier: 5, category: 'mana' },
    // Food Estates: Pot 🍲 → Patch 🌱 → Garden 🌾 → Field 🌻 → Farm 🏡
    pot:    { name: 'Pot',    icon: '\u{1F372}', tier: 1, category: 'food' },
    patch:  { name: 'Patch',  icon: '\u{1F331}', tier: 2, category: 'food' },
    garden: { name: 'Garden', icon: '\u{1F33E}', tier: 3, category: 'food' },
    field:  { name: 'Field',  icon: '\u{1F33B}', tier: 4, category: 'food' },
    farm:   { name: 'Farm',   icon: '\u{1F3E1}', tier: 5, category: 'food' },
    // Workforce: Novice 🙏 → Monk 🧘 → Cleric 🧙 → Bishop 👑 → Cardinal ⭐
    novice:   { name: 'Novice',   icon: '\u{1F64F}', tier: 1, category: 'workforce' },
    monk:     { name: 'Monk',     icon: '\u{1F9D8}', tier: 2, category: 'workforce' },
    cleric:   { name: 'Cleric',   icon: '\u{1F9D9}', tier: 3, category: 'workforce' },
    bishop:   { name: 'Bishop',   icon: '\u{1F451}', tier: 4, category: 'workforce' },
    cardinal: { name: 'Cardinal', icon: '\u2B50',    tier: 5, category: 'workforce' },
  }

  // Tier progression chains (for prerequisite checking)
  const tierChains = {
    mana: ['altar', 'shrine', 'temple', 'church', 'cathedral'],
    food: ['pot', 'patch', 'garden', 'field', 'farm'],
    workforce: ['novice', 'monk', 'cleric', 'bishop', 'cardinal'],
  }

  /**
   * Fetch full economy data from get_player_economy RPC
   */
  async function fetchEconomy() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_player_economy')

      if (rpcError) throw rpcError

      if (data) {
        mana.value = data.mana || 0
        gold.value = data.gold || 0
        food.value = data.food || 0
        buildings.value = data.buildings || []
        dailyRates.value = data.daily_rates || {
          mana_per_day: 0,
          gold_per_day: 0,
          food_per_day: 0,
          gold_upkeep_per_day: 0,
          food_consumption_per_day: 0,
        }
      }
    } catch (err) {
      error.value = err.message
      console.error('[useEconomy] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Fetch game config values (for cap multipliers and display)
   */
  async function fetchGameConfig() {
    try {
      const { data, error: fetchError } = await supabase
        .from('game_config')
        .select('key, value')

      if (fetchError) throw fetchError

      if (data) {
        const configMap = {}
        for (const row of data) {
          configMap[row.key] = Number(row.value)
        }
        gameConfig.value = configMap
      }
    } catch (err) {
      console.error('[useEconomy] Config fetch error:', err)
    }
  }

  /**
   * Update local resource values after a purchase or profile refresh
   */
  function updateResources({ mana: newMana, gold: newGold, food: newFood }) {
    if (newMana !== undefined) mana.value = newMana
    if (newGold !== undefined) gold.value = newGold
    if (newFood !== undefined) food.value = newFood
  }

  return reactive({
    mana,
    gold,
    food,
    buildings,
    dailyRates,
    gameConfig,
    loading,
    error,
    netManaPerDay,
    netGoldPerDay,
    netFoodPerDay,
    buildingCounts,
    manaCap,
    goldCap,
    foodCap,
    resourceEmojis,
    buildingInfo,
    tierChains,
    fetchEconomy,
    fetchGameConfig,
    updateResources,
  })
}

export function useEconomy() {
  if (!sharedState) {
    sharedState = createEconomyState()
  }
  return sharedState
}