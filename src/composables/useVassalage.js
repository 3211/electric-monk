import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useVassalage Composable (Exodus 1 Overhaul)
 *
 * Manages the Vassalage system state:
 * - Suzerain info (who you bow to)
 * - Vassals list (who bows to you)
 * - Daily tithes received
 * - Divine Shield status
 * - Subjugation timers (168-hour countdown)
 * - Resist subjugation (pay gold tribute)
 * - Rebellion (break free after 3 idle days)
 * - Crusade, Schism, and Plague combat actions
 * - Akashic log feed
 */

let sharedState = null

function createVassalageState() {
  const economy = useEconomy()

  const suzerain = ref(null)
  const vassals = ref([])
  const vassalCount = ref(0)
  const dailyTithes = ref({ mana_per_day: 0, gold_per_day: 0, food_per_day: 0 })
  const isProtected = ref(false)
  const chainDepth = ref(0)

  // Exodus 1: Subjugation timers
  const subjugationAsLiege = ref([])
  const subjugationAsVassal = ref([])

  // Akashic logs
  const akashicLogs = ref([])
  const logsLoading = ref(false)

  // Combat state (legacy)
  const crusadeLoading = ref(false)
  const schismLoading = ref(false)
  const plagueLoading = ref(false)
  const combatResult = ref(null)
  const combatError = ref(null)

  // Subjugation actions
  const subjugating = ref(false)
  const resisting = ref(false)
  const rebelling = ref(false)

  const loading = ref(false)
  const error = ref(null)

  const isVassal = computed(() => suzerain.value !== null && suzerain.value !== undefined)
  const hasVassals = computed(() => vassalCount.value > 0)

  const totalTithesPerDay = computed(() => {
    const t = dailyTithes.value
    const parts = []
    if (t.mana_per_day > 0) parts.push(`${t.mana_per_day} mana`)
    if (t.gold_per_day > 0) parts.push(`${t.gold_per_day} gold`)
    if (t.food_per_day > 0) parts.push(`${t.food_per_day} food`)
    return parts.length > 0 ? parts.join(', ') : 'none'
  })

  const schismCost = computed(() => {
    const baseCost = 100
    const scalingFactor = 2
    const count = economy.schismCount || 0
    return Math.floor(baseCost * Math.pow(scalingFactor, count))
  })

  const crusadeAttackPower = computed(() => {
    const mana = economy.mana || 0
    const clericCount = economy.buildingCounts?.cleric || 0
    const ratingPerCleric = 10
    return Math.max(1, mana) + (clericCount * ratingPerCleric)
  })

  const defensePower = computed(() => {
    const churchCount = economy.buildingCounts?.church || 0
    const cathedralCount = economy.buildingCounts?.cathedral || 0
    return (churchCount * 15) + (cathedralCount * 40)
  })

  const divineShieldRemaining = computed(() => {
    if (!economy.divineShieldUntil) return null
    const until = new Date(economy.divineShieldUntil)
    const now = new Date()
    if (until <= now) return null
    const diffMs = until - now
    const hours = Math.floor(diffMs / (1000 * 60 * 60))
    const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60))
    return `${hours}h ${minutes}m`
  })

  // Exodus 1: Subjugation threat level
  const isBeingSubjugated = computed(() => subjugationAsVassal.value.length > 0)
  const isSubjugatingSomeone = computed(() => subjugationAsLiege.value.length > 0)

  async function fetchVassalageInfo() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_vassalage_info')

      if (rpcError) throw rpcError

      if (data) {
        suzerain.value = data.suzerain
        vassals.value = data.vassals || []
        vassalCount.value = data.vassal_count || 0
        dailyTithes.value = data.daily_tithes || { mana_per_day: 0, gold_per_day: 0, food_per_day: 0 }
        isProtected.value = data.is_protected || false
        chainDepth.value = data.chain_depth || 0
        // Exodus 1: Subjugation timers from updated RPC
        subjugationAsLiege.value = data.subjugation_as_liege || []
        subjugationAsVassal.value = data.subjugation_as_vassal || []
      }
    } catch (err) {
      error.value = err.message
      console.error('[useVassalage] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Start or advance subjugation timer against a target
   */
  async function startSubjugation(targetId) {
    try {
      subjugating.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('start_subjugation', {
        p_target_id: targetId,
      })

      if (rpcError) throw rpcError

      await fetchVassalageInfo()
      return data
    } catch (err) {
      error.value = err.message
      console.error('[useVassalage] Subjugation error:', err)
      throw err
    } finally {
      subjugating.value = false
    }
  }

  /**
   * Resist subjugation: pay 1000 Gold to reduce timer by 24 hours
   */
  async function resistSubjugation(liegeId) {
    try {
      resisting.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('resist_subjugation', {
        p_liege_id: liegeId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchVassalageInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useVassalage] Resist error:', err)
      throw err
    } finally {
      resisting.value = false
    }
  }

  /**
   * Attempt rebellion: break free if liege hasn't attacked for 3+ days
   */
  async function attemptRebellion() {
    try {
      rebelling.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('attempt_rebellion')

      if (rpcError) throw rpcError

      await Promise.all([
        fetchVassalageInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useVassalage] Rebellion error:', err)
      throw err
    } finally {
      rebelling.value = false
    }
  }

  async function launchCrusade(targetId) {
    try {
      crusadeLoading.value = true
      combatError.value = null
      combatResult.value = null

      const { data, error: rpcError } = await supabase.rpc('launch_crusade', {
        p_target_id: targetId
      })

      if (rpcError) throw rpcError

      combatResult.value = { type: 'crusade', ...data }

      await Promise.all([
        economy.fetchEconomy(),
        fetchVassalageInfo()
      ])

      return data
    } catch (err) {
      combatError.value = err.message
      console.error('[useVassalage] Crusade error:', err)
      throw err
    } finally {
      crusadeLoading.value = false
    }
  }

  async function declareSchism() {
    try {
      schismLoading.value = true
      combatError.value = null
      combatResult.value = null

      const { data, error: rpcError } = await supabase.rpc('declare_schism')

      if (rpcError) throw rpcError

      combatResult.value = { type: 'schism', ...data }

      await Promise.all([
        economy.fetchEconomy(),
        fetchVassalageInfo()
      ])

      return data
    } catch (err) {
      combatError.value = err.message
      console.error('[useVassalage] Schism error:', err)
      throw err
    } finally {
      schismLoading.value = false
    }
  }

  async function castPlague(targetId) {
    try {
      plagueLoading.value = true
      combatError.value = null
      combatResult.value = null

      const { data, error: rpcError } = await supabase.rpc('cast_plague', {
        p_target_id: targetId
      })

      if (rpcError) throw rpcError

      combatResult.value = { type: 'plague', ...data }

      await economy.fetchEconomy()

      return data
    } catch (err) {
      combatError.value = err.message
      console.error('[useVassalage] Plague error:', err)
      throw err
    } finally {
      plagueLoading.value = false
    }
  }

  async function fetchAkashicLogs(limit = 50, offset = 0) {
    try {
      logsLoading.value = true

      const { data, error: rpcError } = await supabase.rpc('get_akashic_logs', {
        p_limit: limit,
        p_offset: offset
      })

      if (rpcError) throw rpcError

      if (data) {
        akashicLogs.value = data
      }
    } catch (err) {
      console.error('[useVassalage] Akashic logs error:', err)
    } finally {
      logsLoading.value = false
    }
  }

  async function lookupPlayer(username) {
    try {
      const { data, error: rpcError } = await supabase.rpc('lookup_player', {
        p_search: username
      })

      if (rpcError) throw rpcError
      return data || []
    } catch (err) {
      console.error('[useVassalage] Lookup error:', err)
      return []
    }
  }

  function clearCombatState() {
    combatResult.value = null
    combatError.value = null
  }

  return reactive({
    suzerain,
    vassals,
    vassalCount,
    dailyTithes,
    isProtected,
    chainDepth,
    isVassal,
    hasVassals,
    totalTithesPerDay,
    schismCost,
    crusadeAttackPower,
    defensePower,
    divineShieldRemaining,
    // Exodus 1: Subjugation
    subjugationAsLiege,
    subjugationAsVassal,
    isBeingSubjugated,
    isSubjugatingSomeone,
    subjugating,
    resisting,
    rebelling,
    // Akashic
    akashicLogs,
    logsLoading,
    // Legacy combat
    crusadeLoading,
    schismLoading,
    plagueLoading,
    combatResult,
    combatError,
    // General
    loading,
    error,
    // Methods
    fetchVassalageInfo,
    startSubjugation,
    resistSubjugation,
    attemptRebellion,
    launchCrusade,
    declareSchism,
    castPlague,
    fetchAkashicLogs,
    lookupPlayer,
    clearCombatState,
  })
}

export function useVassalage() {
  if (!sharedState) {
    sharedState = createVassalageState()
  }
  return sharedState
}