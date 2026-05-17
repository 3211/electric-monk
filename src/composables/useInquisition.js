import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useInquisition Composable
 *
 * Manages the Inquisition (Espionage) system:
 * - Launch inquisitions against targets
 * - Reveals heresy, active miracles
 * - Assassinates high-tier workers
 */

let sharedState = null

function createInquisitionState() {
  const economy = useEconomy()

  const loading = ref(false)
  const error = ref(null)
  const lastResult = ref(null)

  /**
   * Launch an Inquisition against a target player
   */
  async function launchInquisition(targetId) {
    try {
      loading.value = true
      error.value = null
      lastResult.value = null

      const { data, error: rpcError } = await supabase.rpc('launch_inquisition', {
        p_target_id: targetId,
      })

      if (rpcError) throw rpcError

      lastResult.value = data

      // Refresh economy (gold was spent)
      await economy.fetchEconomy()

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useInquisition] Launch error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Clear the last result
   */
  function clearResult() {
    lastResult.value = null
    error.value = null
  }

  return reactive({
    loading,
    error,
    lastResult,
    launchInquisition,
    clearResult,
  })
}

export function useInquisition() {
  if (!sharedState) {
    sharedState = createInquisitionState()
  }
  return sharedState
}