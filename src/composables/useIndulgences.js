import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useIndulgences Composable
 *
 * Manages the premium currency (Indulgences) system:
 * - Activate Papal Bull of Protection (12h immunity)
 * - Activate Divine Architect (build queue)
 * - Track active miracles
 * - Custom titles/avatars (future Stripe integration)
 */

let sharedState = null

function createIndulgencesState() {
  const economy = useEconomy()

  const activeMiracles = ref([])
  const loading = ref(false)
  const activating = ref(false)
  const error = ref(null)

  const hasPapalBull = computed(() => {
    if (!economy.papalBullUntil) return false
    return new Date(economy.papalBullUntil) > new Date()
  })

  const hasDivineArchitect = computed(() => {
    return activeMiracles.value.some(m => m.miracle_type === 'divine_architect' && new Date(m.expires_at) > new Date())
  })

  const papalBullRemaining = computed(() => {
    if (!economy.papalBullUntil) return null
    const until = new Date(economy.papalBullUntil)
    const now = new Date()
    if (until <= now) return null
    const diffMs = until - now
    const hours = Math.floor(diffMs / (1000 * 60 * 60))
    const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60))
    return `${hours}h ${minutes}m`
  })

  /**
   * Fetch active miracles for current user
   */
  async function fetchActiveMiracles() {
    try {
      const { data, error: queryError } = await supabase
        .from('active_miracles')
        .select('*')
        .order('expires_at', { ascending: true })

      if (queryError) throw queryError
      activeMiracles.value = data || []
    } catch (err) {
      console.error('[useIndulgences] Fetch miracles error:', err)
    }
  }

  /**
   * Activate Papal Bull of Protection
   */
  async function activatePapalBull() {
    try {
      activating.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('consume_indulgence', {
        p_action_type: 'papal_bull',
      })

      if (rpcError) throw rpcError

      await Promise.all([
        economy.fetchEconomy(),
        fetchActiveMiracles(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useIndulgences] Papal Bull error:', err)
      throw err
    } finally {
      activating.value = false
    }
  }

  /**
   * Activate Divine Architect (build queue)
   */
  async function activateDivineArchitect() {
    try {
      activating.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('consume_indulgence', {
        p_action_type: 'divine_architect',
      })

      if (rpcError) throw rpcError

      await Promise.all([
        economy.fetchEconomy(),
        fetchActiveMiracles(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useIndulgences] Divine Architect error:', err)
      throw err
    } finally {
      activating.value = false
    }
  }

  return reactive({
    activeMiracles,
    loading,
    activating,
    error,
    hasPapalBull,
    hasDivineArchitect,
    papalBullRemaining,
    fetchActiveMiracles,
    activatePapalBull,
    activateDivineArchitect,
  })
}

export function useIndulgences() {
  if (!sharedState) {
    sharedState = createIndulgencesState()
  }
  return sharedState
}