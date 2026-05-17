import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'
import { usePrayers } from './usePrayers'

/**
 * useCatacombs Composable
 *
 * Manages the Catacombs (shadow economy) state:
 * - Heresy resource display and cap
 * - Catacombs shop items (Cultist, Coven)
 * - Purchase flow for multi-currency items
 * - Heresy generation rates
 */

let sharedState = null

function createCatacombsState() {
  const economy = useEconomy()
  const prayers = usePrayers()

  // -- Shop state --
  const catacombsItems = ref([])
  const playerBuildings = ref([])
  const purchasing = ref(false)
  const purchaseError = ref(null)
  const lastPurchase = ref(null)
  const loading = ref(false)

  // -- Computed: heresy data from economy --
  const heresy = computed(() => economy.heresy || 0)
  const heresyCap = computed(() => economy.heresyCap || 100)
  const heresyPerDay = computed(() => economy.dailyRates?.heresy_per_day || 0)
  const heresyPercent = computed(() => {
    if (heresyCap.value === 0) return 0
    return Math.min(100, Math.floor((heresy.value / heresyCap.value) * 100))
  })

  // -- Computed: Gold data from economy --
  const gold = computed(() => economy.gold || 0)

  // -- Computed: building counts for catacombs items --
  const buildingCounts = computed(() => economy.buildingCounts || {})

  // -- Computed: cultist items (sorted) --
  const cultistItems = computed(() => {
    return catacombsItems.value
      .filter(item => item.category === 'catacombs' && item.effect_data?.building_type === 'cultist')
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // -- Computed: coven items (sorted) --
  const covenItems = computed(() => {
    return catacombsItems.value
      .filter(item => item.category === 'catacombs' && item.effect_data?.building_type === 'coven')
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // -- Computed: all catacombs items (sorted) --
  const allCatacombsItems = computed(() => {
    return catacombsItems.value
      .filter(item => item.category === 'catacombs')
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // Building display info for catacombs
  const catacombsBuildingInfo = {
    cultist: { name: 'Cultist', icon: '\u{1F9DE}', tier: 1, category: 'catacombs' },
    coven: { name: 'Coven', icon: '\u{1F52E}', tier: 2, category: 'catacombs' },
  }

  /**
   * Calculate the actual (scaled) cost for a catacombs item
   * Supports multi-currency: karma, gold, heresy
   */
  function scaledCosts(item) {
    if (!item) return { karma: 0, gold: 0, heresy: 0 }

    const buildingType = item.effect_data?.building_type
    const count = buildingType ? (buildingCounts.value[buildingType] || 0) : 0
    const multiplier = economy.gameConfig?.['shop.cost_scaling_multiplier'] || 1.15

    if (item.cost_scaling && buildingType) {
      return {
        karma: Math.floor(item.karma_cost * Math.pow(multiplier, count)),
        gold: Math.floor(item.gold_cost * Math.pow(multiplier, count)),
        heresy: Math.floor(item.heresy_cost * Math.pow(multiplier, count)),
      }
    }

    return {
      karma: item.karma_cost || 0,
      gold: item.gold_cost || 0,
      heresy: item.heresy_cost || 0,
    }
  }

  /**
   * Check if player can afford a catacombs item
   */
  function canAfford(item) {
    if (!item || !item.is_active) return false
    const costs = scaledCosts(item)
    if (costs.karma > 0 && (prayers.karma || 0) < costs.karma) return false
    if (costs.gold > 0 && gold.value < costs.gold) return false
    if (costs.heresy > 0 && heresy.value < costs.heresy) return false

    // Check prerequisite
    if (item.requires_building) {
      const counts = buildingCounts.value
      if (!counts[item.requires_building] || counts[item.requires_building] === 0) return false
    }

    return true
  }

  /**
   * Check if prerequisite is met
   */
  function hasPrerequisite(item) {
    if (!item || !item.requires_building) return true
    const counts = buildingCounts.value
    return counts[item.requires_building] && counts[item.requires_building] > 0
  }

  /**
   * Format cost display string
   */
  function formatCosts(item) {
    const costs = scaledCosts(item)
    const parts = []
    if (costs.karma > 0) parts.push(`${costs.karma} karma`)
    if (costs.gold > 0) parts.push(`${costs.gold} gold`)
    if (costs.heresy > 0) parts.push(`${costs.heresy} heresy`)
    return parts.length > 0 ? parts.join(', ') : 'Free'
  }

  /**
   * Fetch catacombs shop items from server
   */
  async function fetchCatacombsItems() {
    try {
      loading.value = true

      const { data, error: fetchError } = await supabase
        .from('shop_items')
        .select('*')
        .eq('category', 'catacombs')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })

      if (fetchError) throw fetchError

      catacombsItems.value = data || []
    } catch (err) {
      console.error('[useCatacombs] Fetch items error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Purchase a catacombs item via the multi-currency RPC
   */
  async function purchaseItem(itemId) {
    try {
      purchasing.value = true
      purchaseError.value = null
      lastPurchase.value = null

      const { data, error: rpcError } = await supabase.rpc('purchase_shop_item', {
        p_item_id: itemId,
      })

      if (rpcError) throw rpcError

      lastPurchase.value = data

      // Refresh all relevant state after purchase
      await Promise.all([
        prayers.fetchProfile(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      purchaseError.value = err.message
      console.error('[useCatacombs] Purchase error:', err)
      throw err
    } finally {
      purchasing.value = false
    }
  }

  /**
   * Clear purchase error state
   */
  function clearPurchaseError() {
    purchaseError.value = null
  }

  /**
   * Clear last purchase result
   */
  function clearLastPurchase() {
    lastPurchase.value = null
  }

  return reactive({
    // Shop state
    catacombsItems,
    playerBuildings,
    purchasing,
    purchaseError,
    lastPurchase,
    loading,

    // Computed
    heresy,
    heresyCap,
    heresyPerDay,
    heresyPercent,
    gold,
    buildingCounts,
    cultistItems,
    covenItems,
    allCatacombsItems,
    catacombsBuildingInfo,

    // Methods
    scaledCosts,
    canAfford,
    hasPrerequisite,
    formatCosts,
    fetchCatacombsItems,
    purchaseItem,
    clearPurchaseError,
    clearLastPurchase,
  })
}

export function useCatacombs() {
  if (!sharedState) {
    sharedState = createCatacombsState()
  }
  return sharedState
}