import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useRelics Composable
 *
 * Manages the global Relic system:
 * - Fetch all 10 relics with holder info
 * - Track steal progress
 * - Attempt relic steal (coordinated Synod attack)
 */

let sharedState = null

function createRelicsState() {
  const relics = ref([])
  const loading = ref(false)
  const stealing = ref(false)
  const error = ref(null)

  /**
   * Fetch all relics (globally visible)
   */
  async function fetchRelics() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_relics')

      if (rpcError) throw rpcError

      if (data) {
        relics.value = data
      }
    } catch (err) {
      error.value = err.message
      console.error('[useRelics] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Attempt to steal a relic (requires Synod membership)
   */
  async function attemptSteal(relicId) {
    try {
      stealing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('attempt_relic_steal', {
        p_relic_id: relicId,
      })

      if (rpcError) throw rpcError

      // Refresh relics after steal attempt
      await fetchRelics()

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useRelics] Steal error:', err)
      throw err
    } finally {
      stealing.value = false
    }
  }

  /**
   * Get relics held by the current user
   */
  function heldRelics(userId) {
    return relics.value.filter(r => r.holder_id === userId)
  }

  return reactive({
    relics,
    loading,
    stealing,
    error,
    fetchRelics,
    attemptSteal,
    heldRelics,
  })
}

export function useRelics() {
  if (!sharedState) {
    sharedState = createRelicsState()
  }
  return sharedState
}