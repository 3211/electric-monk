import { ref, computed, watch, onUnmounted } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * usePrayerCounter Composable
 *
 * Manages real-time prayer counting for the active prayer.
 * - Calculates cycle time from prayer content length: ceil(len/5) * 150ms
 * - Increments displayed count each cycle
 * - Syncs to backend every 10 seconds via sync_prayer_count RPC
 * - Stops and cleans up on deactivation/unmount
 *
 * @param {Object} prayer - Reactive prayer object with content, prayer_count, activated_at, last_counted_at, is_praying
 * @returns {Object} Counter state and methods
 */
export function usePrayerCounter(prayer) {
  const displayedCount = ref(0)
  const isAnimating = ref(false)

  const SYNC_INTERVAL_MS = 10_000 // Ping backend every 10 seconds

  let cycleTimer = null
  let syncTimer = null
  let lastLocalCount = 0 // Tracks counts since last sync

  /**
   * Calculate the cycle time in ms for a prayer based on its content length.
   * Formula: ceil(content.length / 5) * 150ms, minimum 150ms
   */
  function calculateCycleTimeMs(content) {
    if (!content) return 150
    return Math.max(150, Math.ceil(content.length / 5) * 150)
  }

  /**
   * Calculate how many cycles have elapsed between two timestamps.
   */
  function calculateElapsedCycles(fromTime, toTime, cycleTimeMs) {
    if (!fromTime || !toTime || cycleTimeMs <= 0) return 0
    const elapsedMs = new Date(toTime).getTime() - new Date(fromTime).getTime()
    return Math.max(0, Math.floor(elapsedMs / cycleTimeMs))
  }

  /**
   * Initialize the displayed count from prayer data.
   * Called when a prayer becomes active or on mount if already active.
   */
  function initializeCount() {
    if (!prayer.value || !prayer.value.is_praying) {
      displayedCount.value = prayer.value?.prayer_count || 0
      return
    }

    const content = prayer.value.content || ''
    const cycleTimeMs = calculateCycleTimeMs(content)
    const lastCountedAt = prayer.value.last_counted_at || prayer.value.activated_at
    const baseCount = prayer.value.prayer_count || 0

    // Calculate how many cycles have elapsed since last_counted_at
    const elapsedCycles = calculateElapsedCycles(lastCountedAt, new Date().toISOString(), cycleTimeMs)
    displayedCount.value = baseCount + elapsedCycles
    lastLocalCount = 0 // Reset local delta since we just recalibrated
  }

  /**
   * Start the counting cycle and sync timers.
   */
  function startCounting() {
    stopCounting() // Clear any existing timers

    if (!prayer.value || !prayer.value.is_praying) return

    const content = prayer.value.content || ''
    const cycleTimeMs = calculateCycleTimeMs(content)

    // Initialize count from server data
    initializeCount()

    // Cycle timer: increment displayed count each cycle
    cycleTimer = setInterval(() => {
      if (!prayer.value?.is_praying) {
        stopCounting()
        return
      }
      displayedCount.value++
      lastLocalCount++
      isAnimating.value = true
      // Reset animation flag after a short delay
      setTimeout(() => { isAnimating.value = false }, 200)
    }, cycleTimeMs)

    // Sync timer: push accumulated counts to backend periodically
    syncTimer = setInterval(async () => {
      if (!prayer.value?.is_praying || lastLocalCount === 0) return

      try {
        const { data, error } = await supabase.rpc('sync_prayer_count', {
          p_prayer_id: prayer.value.id,
          p_elapsed_counts: lastLocalCount,
        })

        if (error) {
          console.error('[usePrayerCounter] Sync error:', error)
          return
        }

        // Recalibrate local count from server response
        if (data) {
          const content = prayer.value.content || ''
          const cycleTimeMs = calculateCycleTimeMs(content)
          const lastCountedAt = data.last_counted_at || data.activated_at
          const baseCount = data.prayer_count || 0
          const elapsedCycles = calculateElapsedCycles(lastCountedAt, new Date().toISOString(), cycleTimeMs)

          displayedCount.value = baseCount + elapsedCycles
          lastLocalCount = 0
        }
      } catch (err) {
        console.error('[usePrayerCounter] Sync failed:', err)
      }
    }, SYNC_INTERVAL_MS)
  }

  /**
   * Stop the counting cycle and sync timers.
   */
  function stopCounting() {
    if (cycleTimer) {
      clearInterval(cycleTimer)
      cycleTimer = null
    }
    if (syncTimer) {
      clearInterval(syncTimer)
      syncTimer = null
    }
    isAnimating.value = false
  }

  /**
   * Final sync before deactivating a prayer.
   * Pushes remaining accumulated counts to backend.
   * @returns {Object} Updated prayer data from server
   */
  async function finalSync() {
    stopCounting()

    if (!prayer.value || lastLocalCount === 0) return null

    try {
      const { data, error } = await supabase.rpc('deactivate_prayer', {
        p_prayer_id: prayer.value.id,
        p_elapsed_counts: lastLocalCount,
      })

      if (error) {
        console.error('[usePrayerCounter] Final sync error:', error)
        return null
      }

      lastLocalCount = 0
      return data
    } catch (err) {
      console.error('[usePrayerCounter] Final sync failed:', err)
      return null
    }
  }

  /**
   * Activate a prayer (re-activate an inactive one).
   * Calls the activate_prayer RPC which deactivates current active first.
   * @param {string} prayerId - The prayer to activate
   * @returns {Object} Result with activated and deactivated prayer data
   */
  async function activatePrayer(prayerId) {
    stopCounting()

    try {
      const { data, error } = await supabase.rpc('activate_prayer', {
        p_prayer_id: prayerId,
      })

      if (error) {
        console.error('[usePrayerCounter] Activate error:', error)
        throw error
      }

      return data
    } catch (err) {
      console.error('[usePrayerCounter] Activate failed:', err)
      throw err
    }
  }

  // Watch for prayer deactivation (is_praying changes to false)
  watch(
    () => prayer.value?.is_praying,
    (newValue, oldValue) => {
      if (newValue && !oldValue) {
        // Prayer was activated — start counting
        startCounting()
      } else if (!newValue && oldValue) {
        // Prayer was deactivated — stop counting
        stopCounting()
        displayedCount.value = prayer.value?.prayer_count || 0
      }
    }
  )

  // Auto-start if prayer is already active on mount
  if (prayer.value?.is_praying) {
    startCounting()
  } else {
    initializeCount()
  }

  // Clean up timers on unmount
  onUnmounted(() => {
    stopCounting()
  })

  return {
    displayedCount: computed(() => displayedCount.value),
    isAnimating: computed(() => isAnimating.value),
    startCounting,
    stopCounting,
    finalSync,
    activatePrayer,
    calculateCycleTimeMs,
  }
}