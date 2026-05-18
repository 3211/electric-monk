import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useCombat Composable (Exodus 1 — NEW)
 *
 * Manages direct PvP tick-based combat:
 * - Initiate combat (NO faction block — always allowed)
 * - Betrayal detection handled on the API; composable displays the result
 * - Poll active combats for live tick updates
 * - Display mana bars, worker counts, gold stolen, tick progress
 */

let sharedState = null

function createCombatState() {
  const activeCombats = ref([])
  const initiating = ref(false)
  const loading = ref(false)
  const error = ref(null)
  const lastResult = ref(null)
  let pollInterval = null

  /**
   * Initiate combat against a target player.
   * No faction filtering — always allowed. API handles betrayal detection.
   */
  async function initiateCombat(targetId) {
    try {
      initiating.value = true
      error.value = null
      lastResult.value = null

      const { data, error: rpcError } = await supabase.rpc('initiate_combat', {
        p_target_id: targetId,
      })

      if (rpcError) throw rpcError

      lastResult.value = data

      if (data?.success) {
        await fetchActiveCombats()
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useCombat] Initiate error:', err)
      throw err
    } finally {
      initiating.value = false
    }
  }

  /**
   * Fetch all active PvP combats for the current player
   */
  async function fetchActiveCombats() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_active_combats')

      if (rpcError) throw rpcError

      activeCombats.value = data || []
    } catch (err) {
      error.value = err.message
      console.error('[useCombat] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Start polling active combats every 5 seconds for live tick updates
   */
  function startPolling() {
    stopPolling()
    fetchActiveCombats()
    pollInterval = setInterval(() => {
      fetchActiveCombats()
    }, 5000)
  }

  function stopPolling() {
    if (pollInterval) {
      clearInterval(pollInterval)
      pollInterval = null
    }
  }

  function resetState() {
    stopPolling()
    activeCombats.value = []
    lastResult.value = null
    error.value = null
  }

  return reactive({
    activeCombats,
    initiating,
    loading,
    error,
    lastResult,
    initiateCombat,
    fetchActiveCombats,
    startPolling,
    stopPolling,
    resetState,
  })
}

export function useCombat() {
  if (!sharedState) {
    sharedState = createCombatState()
  }
  return sharedState
}