import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useVassalage Composable
 *
 * Manages the Vassalage system state:
 * - Suzerain info (who you bow to)
 * - Vassals list (who bows to you)
 * - Daily tithes received
 * - Divine Shield status
 * - Crusade, Schism, and Plague combat actions
 * - Akashic log feed
 */

let sharedState = null

function createVassalageState() {
  const economy = useEconomy()

  // -- Vassalage state --
  const suzerain = ref(null) // { id, username, faith } or null if free
  const vassals = ref([]) // array of { id, username, faith }
  const vassalCount = ref(0)
  const dailyTithes = ref({ mana_per_day: 0, gold_per_day: 0, food_per_day: 0 })
  const isProtected = ref(false) // divine shield active
  const chainDepth = ref(0) // 0 = free, 1 = vassal of free player, etc.

  // -- Akashic logs --
  const akashicLogs = ref([])
  const logsLoading = ref(false)

  // -- Combat state --
  const crusadeLoading = ref(false)
  const schismLoading = ref(false)
  const plagueLoading = ref(false)
  const combatResult = ref(null)
  const combatError = ref(null)

  // -- Loading / error --
  const loading = ref(false)
  const error = ref(null)

  // Computed: Is the player currently a vassal?
  const isVassal = computed(() => suzerain.value !== null && suzerain.value !== undefined)

  // Computed: Does the player have any vassals?
  const hasVassals = computed(() => vassalCount.value > 0)

  // Computed: Total daily tithes as formatted string
  const totalTithesPerDay = computed(() => {
    const t = dailyTithes.value
    const parts = []
    if (t.mana_per_day > 0) parts.push(`${t.mana_per_day} mana`)
    if (t.gold_per_day > 0) parts.push(`${t.gold_per_day} gold`)
    if (t.food_per_day > 0) parts.push(`${t.food_per_day} food`)
    return parts.length > 0 ? parts.join(', ') : 'none'
  })

  // Computed: Schism cost (exponential scaling)
  const schismCost = computed(() => {
    const baseCost = 100
    const scalingFactor = 2
    const count = economy.schismCount || 0
    return Math.floor(baseCost * Math.pow(scalingFactor, count))
  })

  // Computed: Crusade attack power estimate
  const crusadeAttackPower = computed(() => {
    const mana = economy.mana || 0
    const clericCount = economy.buildingCounts?.cleric || 0
    const ratingPerCleric = 10
    return Math.max(1, mana) + (clericCount * ratingPerCleric)
  })

  // Computed: Defense power estimate
  const defensePower = computed(() => {
    const churchCount = economy.buildingCounts?.church || 0
    const cathedralCount = economy.buildingCounts?.cathedral || 0
    return (churchCount * 15) + (cathedralCount * 40)
  })

  // Computed: Divine shield remaining time
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

  /**
   * Fetch full vassalage info from RPC
   */
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
      }
    } catch (err) {
      error.value = err.message
      console.error('[useVassalage] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Launch a crusade against a target player
   */
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

      // Refresh economy and vassalage state
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

  /**
   * Declare schism - break free from suzerain
   */
  async function declareSchism() {
    try {
      schismLoading.value = true
      combatError.value = null
      combatResult.value = null

      const { data, error: rpcError } = await supabase.rpc('declare_schism')

      if (rpcError) throw rpcError

      combatResult.value = { type: 'schism', ...data }

      // Refresh economy and vassalage state
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

  /**
   * Cast plague on a target player
   */
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

      // Refresh economy
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

  /**
   * Fetch akashic logs for this player
   */
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

  /**
   * Look up a player by username (for targeting crusades/plagues)
   */
  async function lookupPlayer(username) {
    try {
      const { data, error: queryError } = await supabase
        .from('profiles')
        .select('id, username, faith')
        .ilike('username', username)
        .limit(5)

      if (queryError) throw queryError
      return data || []
    } catch (err) {
      console.error('[useVassalage] Lookup error:', err)
      return []
    }
  }

  /**
   * Clear combat result/error state
   */
  function clearCombatState() {
    combatResult.value = null
    combatError.value = null
  }

  return reactive({
    // Vassalage state
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

    // Akashic logs
    akashicLogs,
    logsLoading,

    // Combat state
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