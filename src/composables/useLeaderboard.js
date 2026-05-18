import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useLeaderboard Composable (Overhauled)
 *
 * Manages the Divine Rankings leaderboard with per-faith columns:
 * - One scrollable column per faith (5 entries at a time, lazy-load on scroll-to-bottom)
 * - Global top 5 card (scrollable, 5 entries at a time)
 * - User's personal position (global rank + faith rank)
 * - Uses "You" instead of the user's username in the personalized section
 */

const FAITH_KEYS = ['gilded_path', 'holy_way', 'final_watch', 'black_tribunal']

const FAITH_ICONS = {
  gilded_path: '💰',
  holy_way: '🕊️',
  final_watch: '🛡️',
  black_tribunal: '⚖️',
}

const FAITH_NAMES = {
  gilded_path: 'The Gilded Path',
  holy_way: 'The Holy Way',
  final_watch: 'The Final Watch',
  black_tribunal: 'The Black Tribunal',
}

/**
 * Creates a faith column state object.
 */
function createFaithColumn() {
  const entries = ref([])
  const loading = ref(false)
  const hasMore = ref(true)
  const offset = ref(0)

  return { entries, loading, hasMore, offset }
}

let sharedState = null

function createLeaderboardState() {
  // Global top-5
  const globalTop5 = ref([])
  const globalLoading = ref(false)
  const globalOffset = ref(0)
  const globalHasMore = ref(true)

  // Per-faith columns
  const faithColumns = {}
  for (const key of FAITH_KEYS) {
    faithColumns[key] = createFaithColumn()
  }

  // User ranks
  const userRanks = ref(null)   // { global_rank, faith_rank, faith }
  const userRanksLoading = ref(false)
  const userRanksError = ref(null)

  // Global error
  const error = ref(null)

  /** Fetch the next page of global top 5 */
  async function fetchGlobalTop5() {
    if (globalLoading.value || !globalHasMore.value) return

    try {
      globalLoading.value = true
      const { data, error: rpcError } = await supabase.rpc('get_leaderboard', {
        p_offset: globalOffset.value,
        p_limit: 5,
      })

      if (rpcError) throw rpcError

      const rows = data || []
      if (rows.length < 5) globalHasMore.value = false

      globalTop5.value = [...globalTop5.value, ...rows]
      globalOffset.value += rows.length
    } catch (err) {
      error.value = err.message
      console.error('[useLeaderboard] Global fetch error:', err)
    } finally {
      globalLoading.value = false
    }
  }

  /** Fetch the next page for a specific faith column */
  async function fetchFaithPage(faithKey) {
    const col = faithColumns[faithKey]
    if (!col) return
    if (col.loading.value || !col.hasMore.value) return

    try {
      col.loading.value = true
      const { data, error: rpcError } = await supabase.rpc('get_leaderboard_by_faith', {
        p_faith: faithKey,
        p_offset: col.offset.value,
        p_limit: 5,
      })

      if (rpcError) throw rpcError

      const rows = data || []
      if (rows.length < 5) col.hasMore.value = false

      col.entries.value = [...col.entries.value, ...rows]
      col.offset.value += rows.length
    } catch (err) {
      error.value = err.message
      console.error(`[useLeaderboard] Faith fetch error (${faithKey}):`, err)
    } finally {
      col.loading.value = false
    }
  }

  /** Fetch user's global and faith ranks */
  async function fetchUserRanks() {
    try {
      userRanksLoading.value = true
      userRanksError.value = null

      const { data, error: rpcError } = await supabase.rpc('get_user_ranks')

      if (rpcError) throw rpcError

      userRanks.value = data || null
    } catch (err) {
      userRanksError.value = err.message
      console.error('[useLeaderboard] User ranks error:', err)
    } finally {
      userRanksLoading.value = false
    }
  }

  /** Initialize everything: global top 5 first page, all faith columns first page, user ranks */
  async function initAll() {
    error.value = null

    // Reset global
    globalTop5.value = []
    globalOffset.value = 0
    globalHasMore.value = true

    // Reset all faith columns
    for (const key of FAITH_KEYS) {
      faithColumns[key].entries.value = []
      faithColumns[key].offset.value = 0
      faithColumns[key].hasMore.value = true
    }

    // Fetch everything in parallel
    const promises = [fetchGlobalTop5(), fetchUserRanks()]
    for (const key of FAITH_KEYS) {
      promises.push(fetchFaithPage(key))
    }

    await Promise.allSettled(promises)
  }

  /** Handle scroll-to-bottom for global top 5 */
  async function onGlobalScrollToBottom() {
    await fetchGlobalTop5()
  }

  /** Handle scroll-to-bottom for a faith column */
  async function onFaithScrollToBottom(faithKey) {
    await fetchFaithPage(faithKey)
  }

  /** Derived: is the user in the global top 5? */
  const userIsTop5 = computed(() => {
    if (!userRanks.value) return false
    return userRanks.value.global_rank >= 1 && userRanks.value.global_rank <= 5
  })

  /** Backward-compat: FactionsView rankings tab expects `rankings` array */
  const rankings = computed(() => globalTop5.value)

  /** Backward-compat: FactionsView checks `leaderboard.loading` */
  const loading = computed(() => globalLoading.value)

  /** Backward-compat: FactionsView calls `leaderboard.fetchLeaderboard()` */
  async function fetchLeaderboard() {
    // Reset and pull a fresh top 100 (legacy behavior)
    globalTop5.value = []
    globalOffset.value = 0
    globalHasMore.value = true
    error.value = null

    try {
      globalLoading.value = true
      const { data, error: rpcError } = await supabase.rpc('get_leaderboard', {
        p_offset: 0,
        p_limit: 100,
      })

      if (rpcError) throw rpcError

      globalTop5.value = data || []
      globalOffset.value = globalTop5.value.length
      globalHasMore.value = globalTop5.value.length >= 100
    } catch (err) {
      error.value = err.message
      console.error('[useLeaderboard] Legacy fetch error:', err)
    } finally {
      globalLoading.value = false
    }
  }

  /** Backward-compat: FactionsView calls `leaderboard.getUserRank(userId)` */
  function getUserRank(userId) {
    if (!userId) return null
    if (userRanks.value && userId) {
      // If the userId matches the logged-in user, return userRanks
      // Otherwise fall back to scanning globalTop5
    }
    if (!globalTop5.value) return null
    const entry = globalTop5.value.find(r => r.id === userId)
    return entry ? entry.rank : null
  }

  return reactive({
    FAITH_KEYS,
    FAITH_ICONS,
    FAITH_NAMES,
    globalTop5,
    globalLoading,
    globalHasMore,
    faithColumns,
    userRanks,
    userRanksLoading,
    userRanksError,
    userIsTop5,
    error,
    initAll,
    onGlobalScrollToBottom,
    onFaithScrollToBottom,
    // Backward-compat shims (used by FactionsView.vue rankings tab)
    rankings,
    loading,
    fetchLeaderboard,
    getUserRank,
  })
}

export function useLeaderboard() {
  if (!sharedState) {
    sharedState = createLeaderboardState()
  }
  return sharedState
}

export { FAITH_KEYS, FAITH_ICONS, FAITH_NAMES }