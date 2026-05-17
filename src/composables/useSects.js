import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useSects Composable
 *
 * Manages sect selection and sect modifier state:
 * - Choose sect on first login (one-time, irreversible)
 * - Fetch sect info and modifiers
 * - Sect display names and icons
 */

let sharedState = null

function createSectsState() {
  const sectType = ref(null)
  const modifiers = ref([])
  const loading = ref(false)
  const error = ref(null)
  const choosing = ref(false)

  const sectInfo = {
    prosperity_gospel: {
      name: 'The Prosperity Gospel',
      icon: '💰',
      description: '+50% Gold generation, -20% Mana generation, +100% Cathedral upkeep',
      color: 'text-yellow-500',
      bg: 'bg-yellow-500/10 border-yellow-500/30',
    },
    ascetic_order: {
      name: 'The Ascetic Order',
      icon: '🕊️',
      description: '-50% Food consumption, +20% Mana generation, Cannot build Temple/Church/Cathedral',
      color: 'text-blue-400',
      bg: 'bg-blue-500/10 border-blue-500/30',
    },
    doomsday_preppers: {
      name: 'The Doomsday Preppers',
      icon: '🛡️',
      description: '+50% Food generation, +50% Crusade defense, -25% Gold generation',
      color: 'text-green-500',
      bg: 'bg-green-500/10 border-green-500/30',
    },
    inquisition: {
      name: 'The Inquisition',
      icon: '🔥',
      description: '+100% Heresy generation, -30% Mana generation, Inquisitions cost 50% less Gold',
      color: 'text-red-400',
      bg: 'bg-red-500/10 border-red-500/30',
    },
  }

  const sectList = computed(() => {
    return Object.entries(sectInfo).map(([key, info]) => ({
      key,
      ...info,
    }))
  })

  const currentSectInfo = computed(() => {
    if (!sectType.value) return null
    return sectInfo[sectType.value] || null
  })

  /**
   * Choose a sect (one-time, irreversible)
   */
  async function chooseSect(type) {
    try {
      choosing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('choose_sect', {
        p_sect_type: type,
      })

      if (rpcError) throw rpcError

      if (data?.success) {
        sectType.value = type
        await fetchSectInfo()
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSects] Choose sect error:', err)
      throw err
    } finally {
      choosing.value = false
    }
  }

  /**
   * Fetch sect info from RPC
   */
  async function fetchSectInfo() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_sect_info')

      if (rpcError) throw rpcError

      if (data) {
        sectType.value = data.sect_type
        modifiers.value = data.modifiers || []
      }
    } catch (err) {
      error.value = err.message
      console.error('[useSects] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Set sect type from economy data (no RPC call)
   */
  function setSectType(type) {
    sectType.value = type
  }

  return reactive({
    sectType,
    modifiers,
    loading,
    error,
    choosing,
    sectInfo,
    sectList,
    currentSectInfo,
    chooseSect,
    fetchSectInfo,
    setSectType,
  })
}

export function useSects() {
  if (!sharedState) {
    sharedState = createSectsState()
  }
  return sharedState
}