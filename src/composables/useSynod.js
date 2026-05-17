import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useSynod Composable
 *
 * Manages the Synod (Alliance) system:
 * - Create, join, leave synods
 * - View synod info, members, vault
 * - Promote, demote, kick members
 * - Declare Holy Wars
 * - Synod tax management
 */

let sharedState = null

function createSynodState() {
  const economy = useEconomy()

  const inSynod = ref(false)
  const synodInfo = ref(null)
  const members = ref([])
  const memberCount = ref(0)
  const wars = ref([])
  const synodRelics = ref([])
  const loading = ref(false)
  const creating = ref(false)
  const joining = ref(false)
  const declaring = ref(false)
  const managing = ref(false)
  const error = ref(null)

  const isLeader = computed(() => {
    if (!synodInfo.value || !economy.user) return false
    return synodInfo.value.leader_id === economy.user?.id
  })

  const currentUserRole = computed(() => {
    if (!economy.user) return null
    const member = members.value.find(m => m.user_id === economy.user.id)
    return member?.role || null
  })

  /**
   * Fetch full synod info from RPC
   */
  async function fetchSynodInfo() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_synod_info')

      if (rpcError) throw rpcError

      if (data) {
        inSynod.value = data.in_synod
        synodInfo.value = data.synod
        members.value = data.members || []
        memberCount.value = data.member_count || 0
        wars.value = data.wars || []
        synodRelics.value = data.synod_relics || []
      }
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Create a new Synod
   */
  async function createSynod(name) {
    try {
      creating.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('create_synod', {
        p_name: name,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Create error:', err)
      throw err
    } finally {
      creating.value = false
    }
  }

  /**
   * Join an existing Synod
   */
  async function joinSynod(synodId) {
    try {
      joining.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('join_synod', {
        p_synod_id: synodId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Join error:', err)
      throw err
    } finally {
      joining.value = false
    }
  }

  /**
   * Leave current Synod
   */
  async function leaveSynod() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('leave_synod')

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Leave error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Promote a synod member (member -> officer, officer -> leader with transfer)
   */
  async function promoteMember(targetUserId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('promote_synod_member', {
        p_target_id: targetUserId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Promote error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Demote a synod member (officer -> member)
   */
  async function demoteMember(targetUserId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('demote_synod_member', {
        p_target_id: targetUserId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Demote error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Kick a synod member
   */
  async function kickMember(targetUserId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('kick_synod_member', {
        p_target_id: targetUserId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Kick error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Declare Holy War on another Synod (by UUID)
   */
  async function declareHolyWar(targetSynodId) {
    try {
      declaring.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('declare_holy_war', {
        p_target_synod_id: targetSynodId,
      })

      if (rpcError) throw rpcError

      await fetchSynodInfo()
      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Holy War error:', err)
      throw err
    } finally {
      declaring.value = false
    }
  }

  /**
   * Search for synods by name (for joining)
   */
  async function searchSynods(query) {
    try {
      const { data, error: queryError } = await supabase
        .from('synods')
        .select('id, name, leader_id, tax_rate, created_at')
        .ilike('name', `%${query}%`)
        .limit(10)

      if (queryError) throw queryError
      return data || []
    } catch (err) {
      console.error('[useSynod] Search error:', err)
      return []
    }
  }

  /**
   * Reset all state (used on sign-out)
   */
  function resetState() {
    inSynod.value = false
    synodInfo.value = null
    members.value = []
    memberCount.value = 0
    wars.value = []
    synodRelics.value = []
    error.value = null
  }

  return reactive({
    inSynod,
    synodInfo,
    members,
    memberCount,
    wars,
    synodRelics,
    loading,
    creating,
    joining,
    declaring,
    managing,
    error,
    isLeader,
    currentUserRole,
    fetchSynodInfo,
    createSynod,
    joinSynod,
    leaveSynod,
    promoteMember,
    demoteMember,
    kickMember,
    declareHolyWar,
    searchSynods,
    resetState,
  })
}

export function useSynod() {
  if (!sharedState) {
    sharedState = createSynodState()
  }
  return sharedState
}