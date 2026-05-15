import { ref, computed, watch, onUnmounted } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * Configurable: milliseconds per character of the monk's response.
 * ~200 chars (short prayer) ≈ 40s, ~300 chars (average) ≈ 60s, ~500 chars (long) ≈ 100s
 * Adjust this single value to speed up or slow down the prayer cycle.
 */
const TIME_PER_CHAR_MS = 200
const MIN_CYCLE_MS = 15_000   // 15 seconds minimum
const MAX_CYCLE_MS = 180_000  // 3 minutes maximum
const DEFAULT_CYCLE_MS = 60_000 // 1 minute fallback when no content

const SYNC_INTERVAL_MS = 10_000 // Ping backend every 10 seconds

/**
 * usePrayerCounter Composable
 *
 * Manages real-time prayer counting for the active prayer.
 * - Calculates cycle time from monk's response_content length (falls back to user content)
 * - Increments displayed count each cycle
 * - Provides cycleProgress (0–1) for golden progress bar animation
 * - Syncs to backend every 10 seconds via sync_prayer_count RPC
 * - Syncs on beforeunload and visibilitychange to prevent count loss
 * - Stops and cleans up on deactivation/unmount
 *
 * @param {Object} prayer - Reactive prayer object with response_content, content, prayer_count, activated_at, last_counted_at, is_praying
 * @returns {Object} Counter state and methods
 */
export function usePrayerCounter(prayer) {
  const displayedCount = ref(0)
  const isAnimating = ref(false)
  const cycleProgress = ref(0)

  let cycleTimer = null
  let syncTimer = null
  let progressRaf = null
  let lastLocalCount = 0 // Tracks counts since last sync
  let cycleStartTime = null // Timestamp when current cycle started

  /**
   * Get the text used for cycle time calculation.
   * Uses the monk's response_content (what the user sees) with fallback to user content.
   */
  function getCycleText() {
    if (!prayer.value) return ''
    return prayer.value.response_content || prayer.value.content || ''
  }

  /**
   * Calculate the cycle time in ms for a prayer based on the monk's response length.
   * Formula: response_length * TIME_PER_CHAR_MS, clamped between MIN and MAX.
   */
  function calculateCycleTimeMs(text) {
    if (!text) return DEFAULT_CYCLE_MS
    const cycleTime = text.length * TIME_PER_CHAR_MS
    return Math.max(MIN_CYCLE_MS, Math.min(cycleTime, MAX_CYCLE_MS))
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
   * Animate the progress bar smoothly using requestAnimationFrame.
   */
  function startProgressAnimation() {
    if (progressRaf) cancelAnimationFrame(progressRaf)

    function animate() {
      if (!cycleStartTime || !prayer.value?.is_praying) {
        cycleProgress.value = 0
        return
      }
      const cycleTimeMs = calculateCycleTimeMs(getCycleText())
      const elapsed = Date.now() - cycleStartTime
      cycleProgress.value = Math.min(1, elapsed / cycleTimeMs)

      if (cycleProgress.value < 1) {
        progressRaf = requestAnimationFrame(animate)
      }
    }

    progressRaf = requestAnimationFrame(animate)
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

    const cycleText = getCycleText()
    const cycleTimeMs = calculateCycleTimeMs(cycleText)
    const lastCountedAt = prayer.value.last_counted_at || prayer.value.activated_at
    const baseCount = prayer.value.prayer_count || 0

    // Calculate how many cycles have elapsed since last_counted_at
    const elapsedCycles = calculateElapsedCycles(lastCountedAt, new Date().toISOString(), cycleTimeMs)
    displayedCount.value = baseCount + elapsedCycles
    lastLocalCount = 0 // Reset local delta since we just recalibrated

    // Start progress bar from where we are in the current cycle
    const elapsedInCurrentCycle = lastCountedAt
      ? (Date.now() - new Date(lastCountedAt).getTime()) % cycleTimeMs
      : 0
    cycleStartTime = Date.now() - elapsedInCurrentCycle
    startProgressAnimation()
  }

  /**
   * Sync accumulated counts to the backend (fire-and-forget).
   * Used by beforeunload and visibilitychange handlers.
   */
  async function syncToBackend() {
    if (!prayer.value?.is_praying || lastLocalCount === 0) return

    try {
      const { data, error } = await supabase.rpc('sync_prayer_count', {
        p_prayer_id: prayer.value.id,
        p_elapsed_counts: lastLocalCount,
      })

      if (error) {
        console.error('[usePrayerCounter] Background sync error:', error)
        return
      }

      // Recalibrate local count from server response
      if (data) {
        const cycleText = getCycleText()
        const cycleTimeMs = calculateCycleTimeMs(cycleText)
        const lastCountedAt = data.last_counted_at || data.activated_at
        const baseCount = data.prayer_count || 0
        const elapsedCycles = calculateElapsedCycles(lastCountedAt, new Date().toISOString(), cycleTimeMs)

        displayedCount.value = baseCount + elapsedCycles
        lastLocalCount = 0
      }
    } catch (err) {
      console.error('[usePrayerCounter] Background sync failed:', err)
    }
  }

  /**
   * Start the counting cycle and sync timers.
   */
  function startCounting() {
    stopCounting() // Clear any existing timers

    if (!prayer.value || !prayer.value.is_praying) return

    const cycleTimeMs = calculateCycleTimeMs(getCycleText())

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
      // Reset progress bar for new cycle
      cycleStartTime = Date.now()
      startProgressAnimation()
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
          const cycleText = getCycleText()
          const cycleTimeMs = calculateCycleTimeMs(cycleText)
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
    if (progressRaf) {
      cancelAnimationFrame(progressRaf)
      progressRaf = null
    }
    cycleProgress.value = 0
    isAnimating.value = false
  }

  /**
   * Final sync before deactivating a prayer.
   * Pushes remaining accumulated counts to backend.
   * @returns {Object} Updated prayer data from server
   */
  async function finalSync() {
    stopCounting()

    if (!prayer.value) return null

    // Always call deactivate_prayer even if lastLocalCount is 0,
    // to ensure the prayer is properly deactivated in the DB
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

  // Handler: sync before page unload (tab close, navigation)
  // Uses fetch with keepalive for reliable delivery during page unload
  function handleBeforeUnload() {
    if (!prayer.value?.is_praying || lastLocalCount === 0) return
    try {
      // Fire-and-forget sync using fetch with keepalive
      // This ensures the request is sent even if the page is unloading
      supabase.rpc('sync_prayer_count', {
        p_prayer_id: prayer.value.id,
        p_elapsed_counts: lastLocalCount,
      }).then(({ data }) => {
        if (data) {
          lastLocalCount = 0
        }
      }).catch(() => {
        // Best effort — visibilitychange handler is the primary fallback
      })
    } catch {
      // Best effort — periodic syncs every 10s ensure data isn't lost
    }
  }

  // Handler: sync when tab becomes hidden (user switches tabs)
  function handleVisibilityChange() {
    if (document.hidden && prayer.value?.is_praying) {
      syncToBackend()
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

  // Register page unload and visibility handlers
  window.addEventListener('beforeunload', handleBeforeUnload)
  document.addEventListener('visibilitychange', handleVisibilityChange)

  // Clean up timers and event listeners on unmount
  onUnmounted(() => {
    stopCounting()
    window.removeEventListener('beforeunload', handleBeforeUnload)
    document.removeEventListener('visibilitychange', handleVisibilityChange)
  })

  return {
    displayedCount: computed(() => displayedCount.value),
    isAnimating: computed(() => isAnimating.value),
    cycleProgress: computed(() => cycleProgress.value),
    startCounting,
    stopCounting,
    finalSync,
    activatePrayer,
    calculateCycleTimeMs,
  }
}