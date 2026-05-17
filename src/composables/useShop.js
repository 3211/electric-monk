import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { usePrayers } from './usePrayers'
import { useEconomy } from './useEconomy'

/**
 * useShop Composable
 *
 * Manages the Karma Shop state and purchase flow:
 * - Active tab state (mana, food, workforce, infrastructure, blessings)
 * - Shop item fetching from server-authoritative shop_items table
 * - Purchase flow via purchase_shop_item RPC
 * - Player building ownership tracking
 * - Cost scaling: base_cost * 1.15^owned (deflationary)
 * - Tier prerequisite checking (must own previous tier)
 */
export function useShop() {
  const activeTab = ref('mana')
  const shopItems = ref([])
  const playerBuildings = ref([])
  const purchasing = ref(false)
  const purchaseError = ref(null)
  const lastPurchase = ref(null)
  const loading = ref(false)

  const prayers = usePrayers()
  const economy = useEconomy()

  // Computed: group items by category
  const itemsByCategory = computed(() => {
    const groups = {}
    for (const item of shopItems.value) {
      if (!groups[item.category]) {
        groups[item.category] = []
      }
      groups[item.category].push(item)
    }
    return groups
  })

  // Computed: mana estate items (sorted by sort_order)
  const manaItems = computed(() => {
    return (itemsByCategory.value['mana'] || [])
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // Computed: food estate items (sorted by sort_order)
  const foodItems = computed(() => {
    return (itemsByCategory.value['food'] || [])
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // Computed: workforce items (sorted by sort_order)
  const workforceItems = computed(() => {
    return (itemsByCategory.value['workforce'] || [])
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // Computed: infrastructure items (sorted by sort_order)
  const infrastructureItems = computed(() => {
    return (itemsByCategory.value['infrastructure'] || [])
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // Computed: building counts for ownership display
  const buildingCounts = computed(() => {
    const counts = {}
    for (const b of playerBuildings.value) {
      if (b.is_active) {
        counts[b.building_type] = (counts[b.building_type] || 0) + 1
      }
    }
    return counts
  })

  // Computed: count how many of a specific building type the player owns
  function ownedCount(buildingType) {
    return playerBuildings.value.filter(b => b.building_type === buildingType && b.is_active).length
  }

  // Computed: count how many times a specific shop item was purchased
  function purchasedCount(itemId) {
    return playerBuildings.value.filter(b => b.purchased_with === itemId).length
  }

  /**
   * Calculate the actual (scaled) cost for an item.
   * For stacking buildings: base_cost * 1.15^owned
   * For fixed-cost items (prayer slots): just the base cost
   */
  function scaledCost(item) {
    if (!item) return 0
    if (!item.cost_scaling) return item.karma_cost

    const buildingType = item.effect_data?.building_type
    if (!buildingType) return item.karma_cost

    const count = ownedCount(buildingType)
    const multiplier = economy.gameConfig['shop.cost_scaling_multiplier'] || 1.15
    return Math.floor(item.karma_cost * Math.pow(multiplier, count))
  }

  /**
   * Check if a player can purchase an item.
   * Validates: karma balance, prerequisites, and that the item is active.
   */
  function canPurchase(item) {
    if (!item || !item.is_active) return false
    const cost = scaledCost(item)
    if (prayers.karma < cost) return false
    if (item.requires_building) {
      const counts = buildingCounts.value
      if (!counts[item.requires_building] || counts[item.requires_building] === 0) return false
    }
    return true
  }

  /**
   * Check if a player meets the prerequisite for an item.
   */
  function hasPrerequisite(item) {
    if (!item || !item.requires_building) return true
    const counts = buildingCounts.value
    return counts[item.requires_building] && counts[item.requires_building] > 0
  }

  /**
   * Fetch all active shop items from server
   */
  async function fetchShopItems() {
    try {
      loading.value = true

      const { data, error: fetchError } = await supabase
        .from('shop_items')
        .select('*')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })

      if (fetchError) throw fetchError

      shopItems.value = data || []
    } catch (err) {
      console.error('[useShop] Fetch shop items error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Fetch player's buildings
   */
  async function fetchPlayerBuildings() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data, error: fetchError } = await supabase
        .from('player_buildings')
        .select('*')
        .eq('user_id', user.id)

      if (fetchError) throw fetchError

      playerBuildings.value = data || []
    } catch (err) {
      console.error('[useShop] Fetch player buildings error:', err)
    }
  }

  /**
   * Purchase a shop item via RPC
   * Server handles cost scaling and validation atomically
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
        fetchPlayerBuildings(),
      ])

      return data
    } catch (err) {
      purchaseError.value = err.message
      console.error('[useShop] Purchase error:', err)
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
    activeTab,
    shopItems,
    playerBuildings,
    purchasing,
    purchaseError,
    lastPurchase,
    loading,
    itemsByCategory,
    manaItems,
    foodItems,
    workforceItems,
    infrastructureItems,
    buildingCounts,
    ownedCount,
    purchasedCount,
    scaledCost,
    canPurchase,
    hasPrerequisite,
    fetchShopItems,
    fetchPlayerBuildings,
    purchaseItem,
    clearPurchaseError,
    clearLastPurchase,
  })
}