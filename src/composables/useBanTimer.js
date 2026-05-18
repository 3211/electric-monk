import { ref, computed, onMounted, onUnmounted, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useBanTimer Composable (Exodus 2 — faster polling, ban reason display)
 */

let sharedState = null

function createBanTimerState() {
  const banUntil = ref(null)
  const isBanned = ref(false)
  const timeRemaining = ref(null)
  const loading = ref(false)
  const error = ref(null)
  const banReason = ref(null)
  const countdownInterval = ref(null)
  const banPollInterval = ref(null)

  const formattedTimeRemaining = computed(() => {
    if (!timeRemaining.value || timeRemaining.value <= 0) return null
    const hours = Math.floor(timeRemaining.value / 3600)
    const minutes = Math.floor((timeRemaining.value % 3600) / 60)
    const seconds = timeRemaining.value % 60
    const parts = []
    if (hours > 0) parts.push(`${hours}h`)
    if (minutes > 0) parts.push(`${minutes}m`)
    parts.push(`${seconds}s`)
    return parts.join(' ')
  })

  const canWatchIndulgence = computed(() => isBanned.value && !loading.value)

  function updateBanState() {
    if (!banUntil.value) {
      isBanned.value = false
      timeRemaining.value = null
      return
    }
    const now = new Date()
    const banEnd = new Date(banUntil.value)
    const diff = Math.floor((banEnd - now) / 1000)
    if (diff > 0) {
      isBanned.value = true
      timeRemaining.value = diff
    } else {
      isBanned.value = false
      timeRemaining.value = null
      banReason.value = null
      clearBan()
    }
  }

  function startCountdown() {
    if (countdownInterval.value) clearInterval(countdownInterval.value)
    if (banPollInterval.value) clearInterval(banPollInterval.value)

    countdownInterval.value = setInterval(() => {
      updateBanState()
      if (isBanned.value && timeRemaining.value > 0) {
        timeRemaining.value--
      }
    }, 1000)

    // Exodus 2: Poll ban status every 10 seconds (was 30s)
    banPollInterval.value = setInterval(() => {
      if (isBanned.value) {
        checkBanStatus()
      } else {
        // Also check even when not banned — catch mid-session bans
        checkBanStatus()
      }
    }, 10000)
  }

  async function checkBanStatus() {
    try {
      error.value = null
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        banUntil.value = null
        isBanned.value = false
        timeRemaining.value = null
        banReason.value = null
        return
      }

      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('ban_until')
        .eq('id', user.id)
        .single()

      if (profileError) throw profileError

      const wasBanned = isBanned.value
      banUntil.value = profile?.ban_until || null
      updateBanState()

      // Exodus 2: If just got banned mid-session, fetch reason
      if (!wasBanned && isBanned.value) {
        await fetchBanReason()
        // Emit custom event so App.vue can redirect to Purgatory
        window.dispatchEvent(new CustomEvent('ban-detected', {
          detail: { reason: banReason.value }
        }))
      }
    } catch (err) {
      error.value = err.message
      console.error('[useBanTimer] Check ban status error:', err)
    }
  }

  async function fetchBanReason() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data } = await supabase
        .from('betrayal_punishments')
        .select('betrayal_type, created_at')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(1)

      if (data && data.length > 0) {
        const bt = data[0].betrayal_type
        if (bt === 'ally') banReason.value = 'Attacked ally faction'
        else if (bt === 'own_faction') banReason.value = 'Attacked own faction'
        else banReason.value = bt
      }
    } catch {
      banReason.value = null
    }
  }

  async function clearBan() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return
      const { error: updateError } = await supabase
        .from('profiles')
        .update({ ban_until: null })
        .eq('id', user.id)
      if (updateError) throw updateError
      banUntil.value = null
      isBanned.value = false
      timeRemaining.value = null
      banReason.value = null
    } catch (err) {
      console.error('[useBanTimer] Clear ban error:', err)
    }
  }

  async function watchIndulgence() {
    if (!canWatchIndulgence.value) return
    try {
      loading.value = true
      error.value = null
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')
      const { data, error: rpcError } = await supabase.rpc('reduce_ban_time', {
        p_user_id: user.id
      })
      if (rpcError) throw rpcError
      await checkBanStatus()
      return { success: true, timeRemoved: data }
    } catch (err) {
      error.value = err.message
      throw err
    } finally {
      loading.value = false
    }
  }

  return reactive({
    banUntil, isBanned, timeRemaining, loading, error, banReason,
    formattedTimeRemaining, canWatchIndulgence,
    checkBanStatus, watchIndulgence, fetchBanReason,
    startCountdown, countdownInterval,
  })
}

let initialized = false

export function useBanTimer() {
  if (!sharedState) sharedState = createBanTimerState()
  if (!initialized) {
    initialized = true
    sharedState.checkBanStatus()
    sharedState.startCountdown()
  }
  return sharedState
}