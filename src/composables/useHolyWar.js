import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useHolyWar Composable (Exodus 2 — siege-aware, defense scanner)
 */

let sharedState = null

function createHolyWarState() {
  const activeWars = ref([])
  const warTarget = ref(null)
  const finding = ref(false)
  const initiating = ref(false)
  const withdrawing = ref(false)
  const surrendering = ref(false)
  const loading = ref(false)
  const error = ref(null)
  const lastResult = ref(null)
  // Exodus 2: Defense scanner state
  const defenseIndex = ref(0)
  let pollInterval = null

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

  async function fetchActiveWars() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_active_holy_wars')

      if (rpcError) throw rpcError

      activeWars.value = data || []

      // Clamp defenseIndex if wars changed
      if (defenseIndex.value >= activeWars.value.length) {
        defenseIndex.value = Math.max(0, activeWars.value.length - 1)
      }
    } catch (err) {
      error.value = err.message
      console.error('[useHolyWar] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  // Exodus 2: Defense scanner navigation
  function prevDefense() {
    if (activeWars.value.length > 0) {
      defenseIndex.value = (defenseIndex.value - 1 + activeWars.value.length) % activeWars.value.length
    }
  }

  function nextDefense() {
    if (activeWars.value.length > 0) {
      defenseIndex.value = (defenseIndex.value + 1) % activeWars.value.length
    }
  }

  function startPolling() {
    stopPolling()
    fetchActiveWars()
    pollInterval = setInterval(() => fetchActiveWars(), 5000)
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
    defenseIndex.value = 0
    error.value = null
  }

  return reactive({
    activeWars,
    warTarget,
    finding,
    initiating,
    withdrawing,
    surrendering,
    loading,
    error,
    lastResult,
    defenseIndex,
    findTarget,
    initiateHolyWar,
    fetchActiveWars,
    prevDefense,
    nextDefense,
    startPolling,
    stopPolling,
    resetState,
  })
}

export function useHolyWar() {
  if (!sharedState) sharedState = createHolyWarState()
  return sharedState
}