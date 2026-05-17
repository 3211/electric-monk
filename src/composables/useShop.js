import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { usePrayers } from './usePrayers'
import { useEconomy } from './useEconomy'

/**
 * useShop Composable
 *
 * Manages the Karma Shop state and purchase flow:
 * - Active tab state (real_estate, workforce, infrastructure, blessings, etc.)
 * - Shop item fetching from server-authoritative shop_items table
 * - Purchase flow via purchase_shop_item RPC
 * - Player building ownership tracking
 * - Can-purchase validation against karma balance and limits
 */
export function useShop() {
  const activeTab = ref('real_estate')
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

  // Computed: real estate items
  const realEstateItems = computed(() => {
    return (itemsByCategory.value['real_estate'] || [])
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // Computed: workforce items
  const workforceItems = computed(() => {
    return (itemsByCategory.value['workforce'] || [])
      .sort((a, b) => a.sort_order - b.sort_order)
  })

  // Computed: infrastructure items
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

  // Computed: count how many of a specific item the player has purchased
  function purchasedCount(itemId) {
    return playerBuildings.value.filter(b => b.purchased_with === itemId).length
  }

  // Computed: check if player can afford and is allowed to purchase an item
  function canPurchase(item) {
    if (!item || !item.is_active) return false
    if (prayers.karma < item.karma_cost) return false
    if (item.purchase_limit !== null && purchasedCount(item.id) >= item.purchase_limit) return false
    if (item.requires_building) {
      const counts = buildingCounts.value
      if (!counts[item.requires_building] || counts[item.requires_building] === 0) return false
    }
    return true
  }

  // Computed: check if an item is at its purchase limit
  function isAtLimit(item) {
    if (!item) return false
    if (item.purchase_limit !== null && purchasedCount(item.id) >= item.purchase_limit) return true
    return false
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
   * Atomically validates cost, deducts karma, applies effect
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
    realEstateItems,
    workforceItems,
    infrastructureItems,
    buildingCounts,
    purchasedCount,
    canPurchase,
    isAtLimit,
    fetchShopItems,
    fetchPlayerBuildings,
    purchaseItem,
    clearPurchaseError,
    clearLastPurchase,
  })
}