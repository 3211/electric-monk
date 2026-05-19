import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useCombat Composable (Exodus 2 — siege-aware, one-at-a-time)
 */

let sharedState = null

function createCombatState() {
  const activeCombats = ref([])
  const initiating = ref(false)
  const loading = ref(false)
  const error = ref(null)
  const lastResult = ref(null)
  // Exodus 2: Track our active target
  const myCombatTargetId = ref(null)
  let pollInterval = null

  const isAttacking = computed(() => myCombatTargetId.value !== null)
  const attackersOnMe = computed(() => activeCombats.value.filter(c => !c.is_attacker))
  const myAttack = computed(() => activeCombats.value.find(c => c.is_attacker))
  const hasActiveCombat = computed(() => activeCombats.value.length > 0)

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
        myCombatTargetId.value = targetId
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
   * Attacker withdraws from a siege. Pays 50% of remaining
   * tick gold cost + -5 karma. Combat ends as defender_win.
   */
  async function cancelCombat(sessionId) {
    try {
      error.value = null
      lastResult.value = null

      const { data, error: rpcError } = await supabase.rpc('cancel_combat', {
        p_session_id: sessionId,
      })

      if (rpcError) throw rpcError

      lastResult.value = { type: 'cancelled', ...data }

      if (data?.success) {
        await fetchActiveCombats()
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useCombat] Cancel error:', err)
      throw err
    }
  }

  /**
   * Defender surrenders immediately. Becomes attacker's vassal.
   * Combat ends as attacker_win.
   */
  async function surrenderCombat(sessionId) {
    try {
      error.value = null
      lastResult.value = null

      const { data, error: rpcError } = await supabase.rpc('surrender_combat', {
        p_session_id: sessionId,
      })

      if (rpcError) throw rpcError

      lastResult.value = { type: 'surrendered', ...data }

      if (data?.success) {
        await fetchActiveCombats()
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useCombat] Surrender error:', err)
      throw err
    }
  }

  async function fetchActiveCombats() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_active_combats')

      if (rpcError) throw rpcError

      activeCombats.value = data || []

      // Sync myCombatTargetId: if no active combat where I'm attacker, clear it
      const myAtk = activeCombats.value.find(c => c.is_attacker)
      if (!myAtk) {
        myCombatTargetId.value = null
      } else if (myAtk.defender_id !== myCombatTargetId.value) {
        myCombatTargetId.value = myAtk.defender_id
      }
    } catch (err) {
      error.value = err.message
      console.error('[useCombat] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  function startPolling() {
    stopPolling()
    fetchActiveCombats()
    pollInterval = setInterval(() => fetchActiveCombats(), 5000)
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
    myCombatTargetId.value = null
    error.value = null
  }

  return reactive({
    activeCombats,
    initiating,
    loading,
    error,
    lastResult,
    myCombatTargetId,
    isAttacking,
    attackersOnMe,
    myAttack,
    hasActiveCombat,
    initiateCombat,
    cancelCombat,
    surrenderCombat,
    fetchActiveCombats,
    startPolling,
    stopPolling,
    resetState,
  })
}

export function useCombat() {
  if (!sharedState) sharedState = createCombatState()
  return sharedState
}