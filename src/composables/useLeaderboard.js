import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useLeaderboard Composable
 *
 * Manages the Divine Rankings leaderboard:
 * - Fetches top 100 players sorted by karma (primary), mana (secondary)
 * - Manual refresh (no real-time subscriptions to control Supabase costs)
 * - Tracks current user's position in the rankings
 */
export function useLeaderboard() {
  const rankings = ref([])
  const loading = ref(false)
  const error = ref(null)
  const currentUserRank = computed(() => {
    if (!rankings.value || rankings.value.length === 0) return null
    const { data: { user } } = { data: { user: null } }
    // We need the user ID - will be set after auth check
    return null
  })

  /**
   * Fetch the top 100 players from the leaderboard RPC
   */
  async function fetchLeaderboard(options = {}) {
    const { offset = 0, limit = 100 } = options

    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_leaderboard', {
        p_offset: offset,
        p_limit: limit,
      })

      if (rpcError) throw rpcError

      rankings.value = data || []
    } catch (err) {
      error.value = err.message
      console.error('[useLeaderboard] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Find the current user's position in the loaded rankings
   */
  function getUserRank(userId) {
    if (!userId || !rankings.value) return null
    const entry = rankings.value.find(r => r.id === userId)
    return entry ? entry.rank : null
  }

  return reactive({
    rankings,
    loading,
    error,
    fetchLeaderboard,
    getUserRank,
  })
}