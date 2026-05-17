import { ref, computed, watch, onUnmounted } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * Configurable: milliseconds per character of the monk's response.
 * ~200 chars (short prayer) ≈ 40s, ~300 chars (average) ≈ 60s, ~500 chars (long) ≈ 100s
 * Adjust this single value to speed up or slow down the prayer cycle.
 * NOTE: This must match the server-side calculation in calculate_automated_karma()
 */
const TIME_PER_CHAR_MS = 200
const MIN_CYCLE_MS = 15_000   // 15 seconds minimum
const MAX_CYCLE_MS = 180_000  // 3 minutes maximum
const DEFAULT_CYCLE_MS = 60_000 // 1 minute fallback when no content

const SYNC_INTERVAL_MS = 15_000 // Snap to server truth every 15 seconds

/**
 * usePrayerCounter Composable - SERVER-AUTHORITATIVE VERSION
 *
 * The server (pg_cron) is now the source of truth for prayer counts and karma.
 * This composable:
 * - Locally "fake counts" for smooth UI animation between server syncs
 * - Snaps to the server's actual count every 15 seconds
 * - No longer sends increments to the server
 * - Detects sinner redemption for intercessory prayers
 *
 * @param {Object} prayer - Reactive prayer object with response_content, content, prayer_count, activated_at, last_counted_at, is_praying
 * @returns {Object} Counter state and methods
 */
export function usePrayerCounter(prayer) {
  const displayedCount = ref(0)
  const isAnimating = ref(false)
  const cycleProgress = ref(0)
  const karmaMilestoneEarned = ref(0)
  const sinnerRedeemed = ref(false)

  let cycleTimer = null
  let syncTimer = null
  let progressRaf = null
  let cycleStartTime = null
  let serverBaseCount = 0 // The last known server count
  let localIncrement = 0  // Local fake increments since last server sync

  /**
   * Get the text used for cycle time calculation.
   */
  function getCycleText() {
    if (!prayer.value) return ''
    return prayer.value.response_content || prayer.value.content || ''
  }

  /**
   * Calculate the cycle time in ms for a prayer.
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
   * Animate the progress bar smoothly.
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
   */
  function initializeCount() {
    if (!prayer.value) {
      displayedCount.value = 0
      return
    }
    
    if (!prayer.value.is_praying) {
      displayedCount.value = prayer.value.prayer_count || 0
      serverBaseCount = displayedCount.value
      localIncrement = 0
      return
    }

    const cycleText = getCycleText()
    const cycleTimeMs = calculateCycleTimeMs(cycleText)
    const lastCountedAt = prayer.value.last_counted_at || prayer.value.activated_at
    const baseCount = prayer.value.prayer_count || 0

    // Calculate how many cycles have elapsed since last_counted_at
    const elapsedCycles = calculateElapsedCycles(lastCountedAt, new Date().toISOString(), cycleTimeMs)
    
    serverBaseCount = baseCount
    localIncrement = elapsedCycles
    displayedCount.value = baseCount + elapsedCycles

    // Start progress bar from where we are in the current cycle
    const elapsedInCurrentCycle = lastCountedAt
      ? (Date.now() - new Date(lastCountedAt).getTime()) % cycleTimeMs
      : 0
    cycleStartTime = Date.now() - elapsedInCurrentCycle
    startProgressAnimation()
  }

  /**
   * Sync to backend - READ ONLY. Fetches server truth and snaps local count to it.
   */
  async function syncToBackend() {
    if (!prayer.value?.is_praying) return

    try {
      // NEW: sync_prayer_count is now read-only, no p_elapsed_counts parameter
      const { data, error } = await supabase.rpc('sync_prayer_count', {
        p_prayer_id: prayer.value.id,
      })

      if (error) {
        console.error('[usePrayerCounter] Sync error:', error)
        return
      }

      if (data) {
        // Snap to server truth
        const cycleText = getCycleText()
        const cycleTimeMs = calculateCycleTimeMs(cycleText)
        const lastCountedAt = data.last_counted_at || data.activated_at
        const baseCount = data.prayer_count || 0
        
        // Recalculate local elapsed since server's last_counted_at
        const elapsedCycles = calculateElapsedCycles(lastCountedAt, new Date().toISOString(), cycleTimeMs)
        
        serverBaseCount = baseCount
        localIncrement = elapsedCycles
        displayedCount.value = baseCount + elapsedCycles

        // Check if sinner was redeemed (intercessory prayer)
        if (data.sinner_redeemed) {
          sinnerRedeemed.value = true
          stopCounting()
          if (prayer.value) prayer.value.is_praying = false
        }
      }
    } catch (err) {
      console.error('[usePrayerCounter] Sync failed:', err)
    }
  }

  /**
   * Start the counting cycle and sync timers.
   */
  function startCounting() {
    stopCounting()

    if (!prayer.value || !prayer.value.is_praying) return

    const cycleTimeMs = calculateCycleTimeMs(getCycleText())

    // Initialize count from server data
    initializeCount()

    // Cycle timer: increment displayed count each cycle (LOCAL ONLY - for smooth UI)
    cycleTimer = setInterval(() => {
      if (!prayer.value?.is_praying) {
        stopCounting()
        return
      }
      displayedCount.value++
      localIncrement++
      isAnimating.value = true
      setTimeout(() => { isAnimating.value = false }, 200)
      cycleStartTime = Date.now()
      startProgressAnimation()
    }, cycleTimeMs)

    // Sync timer: periodically snap to server truth (no longer sends increments)
    syncTimer = setInterval(() => {
      syncToBackend()
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
   * Just calls deactivate_prayer - server handles final count.
   */
  async function finalSync() {
    stopCounting()

    if (!prayer.value) return null

    try {
      // Server calculates final count based on time elapsed
      const { data, error } = await supabase.rpc('deactivate_prayer', {
        p_prayer_id: prayer.value.id,
        p_elapsed_counts: localIncrement, // Still pass local increment as hint
      })

      if (error) {
        console.error('[usePrayerCounter] Final sync error:', error)
        return null
      }

      localIncrement = 0
      return data
    } catch (err) {
      console.error('[usePrayerCounter] Final sync failed:', err)
      return null
    }
  }

  /**
   * Activate a prayer.
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

  // Handler: sync before page unload
  function handleBeforeUnload() {
    if (!prayer.value?.is_praying) return
    // Fire-and-forget sync
    syncToBackend()
  }

  // Handler: sync when tab becomes hidden
  function handleVisibilityChange() {
    if (document.hidden && prayer.value?.is_praying) {
      syncToBackend()
    }
  }

  // Watch for prayer deactivation
  watch(
    () => prayer.value?.is_praying,
    (newValue, oldValue) => {
      if (newValue && !oldValue) {
        startCounting()
      } else if (!newValue && oldValue) {
        stopCounting()
        displayedCount.value = prayer.value?.prayer_count || 0
      }
    }
  )

  // Watch for prayer ID changes
  watch(
    () => prayer.value?.id,
    (newId, oldId) => {
      if (newId !== oldId && newId) {
        if (oldId) {
          syncToBackend()
        }
        stopCounting()
        if (prayer.value?.is_praying) {
          startCounting()
        } else {
          initializeCount()
        }
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

  // Clean up on unmount
  onUnmounted(() => {
    if (prayer.value?.is_praying) {
      syncToBackend()
    }
    stopCounting()
    window.removeEventListener('beforeunload', handleBeforeUnload)
    document.removeEventListener('visibilitychange', handleVisibilityChange)
  })

  function resetKarmaMilestone() {
    karmaMilestoneEarned.value = 0
  }

  function resetSinnerRedeemed() {
    sinnerRedeemed.value = false
  }

  return {
    displayedCount: computed(() => displayedCount.value),
    isAnimating: computed(() => isAnimating.value),
    cycleProgress: computed(() => cycleProgress.value),
    karmaMilestoneEarned: computed(() => karmaMilestoneEarned.value),
    sinnerRedeemed: computed(() => sinnerRedeemed.value),
    resetKarmaMilestone,
    resetSinnerRedeemed,
    startCounting,
    stopCounting,
    syncToBackend,
    finalSync,
    activatePrayer,
    calculateCycleTimeMs,
  }
}