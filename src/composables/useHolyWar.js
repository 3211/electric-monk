import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useHolyWar Composable (Exodus 1 — NEW)
 *
 * Manages Synod-vs-Synod Holy War tick-based combat:
 * - Find target synod by exact text name
 * - Initiate Holy War (leader only, auto-conscripts all members)
 * - Poll active wars for live tick updates
 * - Display collective mana pools, worker counts, gold stolen, tick progress
 */

let sharedState = null

function createHolyWarState() {
  const activeWars = ref([])
  const warTarget = ref(null)
  const finding = ref(false)
  const initiating = ref(false)
  const loading = ref(false)
  const error = ref(null)
  const lastResult = ref(null)
  let pollInterval = null

  /**
   * Find a synod by exact name (case-insensitive)
   */
  async function findTarget(name) {
    try {
      finding.value = true
      error.value = null
      warTarget.value = null

      const { data, error: rpcError } = await supabase.rpc('find_synod_by_name', {
        p_name: name,
      })

      if (rpcError) throw rpcError

      warTarget.value = data
      return data
    } catch (err) {
      error.value = err.message
      console.error('[useHolyWar] Find error:', err)
      return { found: false }
    } finally {
      finding.value = false
    }
  }

  /**
   * Initiate a Holy War against a target synod (leader only)
   */
  async function initiateHolyWar(synodId) {
    try {
      initiating.value = true
      error.value = null
      lastResult.value = null

      const { data, error: rpcError } = await supabase.rpc('initiate_holy_war', {
        p_target_synod_id: synodId,
      })

      if (rpcError) throw rpcError

      lastResult.value = data

      if (data?.success) {
        await fetchActiveWars()
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useHolyWar] Initiate error:', err)
      throw err
    } finally {
      initiating.value = false
    }
  }

  /**
   * Fetch all active Holy Wars involving the player's synod
   */
  async function fetchActiveWars() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_active_holy_wars')

      if (rpcError) throw rpcError

      activeWars.value = data || []
    } catch (err) {
      error.value = err.message
      console.error('[useHolyWar] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Start polling active wars every 5 seconds for live tick updates
   */
  function startPolling() {
    stopPolling()
    fetchActiveWars()
    pollInterval = setInterval(() => {
      fetchActiveWars()
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
    activeWars.value = []
    warTarget.value = null
    lastResult.value = null
    error.value = null
  }

  return reactive({
    activeWars,
    warTarget,
    finding,
    initiating,
    loading,
    error,
    lastResult,
    findTarget,
    initiateHolyWar,
    fetchActiveWars,
    startPolling,
    stopPolling,
    resetState,
  })
}

export function useHolyWar() {
  if (!sharedState) {
    sharedState = createHolyWarState()
  }
  return sharedState
}