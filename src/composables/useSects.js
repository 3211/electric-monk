import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useSects Composable
 *
 * Manages sect selection and sect modifier state:
 * - Choose sect on first login (one-time, irreversible)
 * - Fetch sect info and modifiers
 * - Sect display names and icons (updated nomenclature)
 *
 * Sect key mapping (Rapture Subsequent):
 *   gilded_path    -> The Gilded Path
 *   holy_way       -> The Holy Way
 *   final_watch    -> The Final Watch
 *   black_tribunal -> The Black Tribunal
 */

let sharedState = null

function createSectsState() {
  const sectType = ref(null)
  const modifiers = ref([])
  const loading = ref(false)
  const error = ref(null)
  const choosing = ref(false)

  const sectInfo = {
    gilded_path: {
      name: 'The Gilded Path',
      icon: '\u{1F4B0}',
      description: '+50% Gold generation, -20% Mana generation, +100% Cathedral upkeep',
      color: 'text-yellow-500',
      bg: 'bg-yellow-500/10 border-yellow-500/30',
    },
    holy_way: {
      name: 'The Holy Way',
      icon: '\u{1F54A}',
      description: '-50% Food consumption, +20% Mana generation, Cannot build Temple/Church/Cathedral',
      color: 'text-blue-400',
      bg: 'bg-blue-500/10 border-blue-500/30',
    },
    final_watch: {
      name: 'The Final Watch',
      icon: '\u{1F6E1}',
      description: '+50% Food generation, +50% Crusade defense, -25% Gold generation',
      color: 'text-green-500',
      bg: 'bg-green-500/10 border-green-500/30',
    },
    black_tribunal: {
      name: 'The Black Tribunal',
      icon: '\u{2697}',
      description: '+100% Heresy generation, -30% Mana generation, Inquisitions cost 50% less Gold',
      color: 'text-red-400',
      bg: 'bg-red-500/10 border-red-500/30',
    },
  }

  const availableFactions = ref([])
  const loadingFactions = ref(false)

  const sectList = computed(() => {
    if (availableFactions.value.length > 0) {
      return availableFactions.value.map(f => ({
        key: f.sect_key,
        ...sectInfo[f.sect_key],
        memberCount: f.member_count,
      }))
    }
    // Fallback: show all if RPC hasn't loaded yet
    return Object.entries(sectInfo).map(([key, info]) => ({
      key,
      ...info,
      memberCount: 0,
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
   * Fetch available factions for balanced onboarding (lowest member count)
   */
  async function fetchAvailableFactions() {
    try {
      loadingFactions.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_available_factions')

      if (rpcError) throw rpcError

      if (data) {
        availableFactions.value = data || []
      }
    } catch (err) {
      error.value = err.message
      console.error('[useSects] Fetch available factions error:', err)
    } finally {
      loadingFactions.value = false
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
      console.error('[useSects] Fetch sect info error:', err)
    } finally {
      loading.value = false
    }
  }

  return reactive({
    sectType,
    sectList,
    sectInfo,
    availableFactions,
    loadingFactions,
    currentSectInfo,
    modifiers,
    loading,
    error,
    choosing,
    chooseSect,
    fetchSectInfo,
    fetchAvailableFactions,
  })
}

export function useSects() {
  if (!sharedState) {
    sharedState = createSectsState()
  }
  return sharedState
}