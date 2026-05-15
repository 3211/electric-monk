import { ref, computed, onMounted, onUnmounted, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useBanTimer Composable (Singleton Pattern)
 * 
 * Manages the ban timer system for users who submit malicious prayers.
 * - Tracks ban status and countdown
 * - Provides method to watch "Indulgence" ad to reduce ban time
 * - Uses shared state so all components see the same ban status
 * 
 * @returns {Object} Ban timer state and methods
 */

// Shared state — created once, reused by all useBanTimer() calls
let sharedState = null

function createBanTimerState() {
  const banUntil = ref(null)
  const isBanned = ref(false)
  const timeRemaining = ref(null)
  const loading = ref(false)
  const error = ref(null)
  const countdownInterval = ref(null)

  // Computed properties
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

  /**
   * Update ban state based on current time
   */
  function updateBanState() {
    if (!banUntil.value) {
      isBanned.value = false
      timeRemaining.value = null
      return
    }

    const now = new Date()
    const banEnd = new Date(banUntil.value)
    const diff = Math.floor((banEnd - now) / 1000) // seconds

    if (diff > 0) {
      isBanned.value = true
      timeRemaining.value = diff
    } else {
      isBanned.value = false
      timeRemaining.value = null
      // Auto-clear expired ban
      clearBan()
    }
  }

  /**
   * Start countdown timer
   */
  function startCountdown() {
    if (countdownInterval.value) {
      clearInterval(countdownInterval.value)
    }

    countdownInterval.value = setInterval(() => {
      updateBanState()
      if (isBanned.value && timeRemaining.value > 0) {
        timeRemaining.value--
      }
    }, 1000)
  }

  /**
   * Fetch current ban status from profile
   */
  async function checkBanStatus() {
    try {
      error.value = null
      
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        banUntil.value = null
        isBanned.value = false
        timeRemaining.value = null
        return
      }

      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('ban_until')
        .eq('id', user.id)
        .single()

      if (profileError) throw profileError

      banUntil.value = profile?.ban_until || null
      updateBanState()
    } catch (err) {
      error.value = err.message
      console.error('[useBanTimer] Check ban status error:', err)
    }
  }

  /**
   * Clear ban from database (called when timer expires)
   */
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
    } catch (err) {
      console.error('[useBanTimer] Clear ban error:', err)
    }
  }

  /**
   * Watch indulgence ad to reduce ban time by 15 minutes
   */
  async function watchIndulgence() {
    if (!canWatchIndulgence.value) return

    try {
      loading.value = true
      error.value = null

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Call the database function to reduce ban time
      const { data, error: rpcError } = await supabase.rpc('reduce_ban_time', {
        p_user_id: user.id
      })

      if (rpcError) throw rpcError

      // Refresh ban status after reduction
      await checkBanStatus()

      return { success: true, timeRemoved: data }
    } catch (err) {
      error.value = err.message
      console.error('[useBanTimer] Indulgence error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Manually set a ban (for testing or admin purposes)
   * @param {number} hours - Hours to ban for
   */
  async function setBan(hours = 2) {
    try {
      loading.value = true
      error.value = null

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      const banEnd = new Date()
      banEnd.setHours(banEnd.getHours() + hours)

      const { error: updateError } = await supabase
        .from('profiles')
        .update({ ban_until: banEnd.toISOString() })
        .eq('id', user.id)

      if (updateError) throw updateError

      await checkBanStatus()
    } catch (err) {
      error.value = err.message
      console.error('[useBanTimer] Set ban error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  return reactive({
    // State
    banUntil,
    isBanned,
    timeRemaining,
    loading,
    error,
    // Computed
    formattedTimeRemaining,
    canWatchIndulgence,
    // Methods
    checkBanStatus,
    watchIndulgence,
    setBan,
    // Lifecycle
    startCountdown,
    countdownInterval,
  })
}

// Module-level flag to ensure initialization happens only once
let initialized = false

export function useBanTimer() {
  // Create shared state on first call, reuse on subsequent calls
  if (!sharedState) {
    sharedState = createBanTimerState()
  }

  // Initialize ban check and countdown only once across all component instances
  if (!initialized) {
    initialized = true
    sharedState.checkBanStatus()
    sharedState.startCountdown()
  }

  return sharedState
}