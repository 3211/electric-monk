<template>
  <div class="bg-theme-wash">
    <!-- Header -->
    <header class="border-b border-theme-border bg-theme-panel/50 backdrop-blur-sm">
      <div class="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
        <h1 class="text-2xl font-bold text-theme-accent">📜 Akashic Records</h1>
        <div class="flex items-center gap-4">
          <!-- Karma Display -->
          <div class="text-sm text-theme-text-dim flex items-center gap-2">
            <span class="text-lg">{{ prayers.karmaEmoji }}</span>
            <span>Karma: <span :class="karmaClass">{{ prayers.karma }}</span></span>
          </div>
        </div>
      </div>

      <!-- Sub-tabs -->
      <div class="max-w-4xl mx-auto px-4 flex gap-1">
        <button
          @click="activeSubTab = 'prayers'"
          :class="activeSubTab === 'prayers' ? 'subtab-active' : 'subtab-inactive'"
        >
          📿 Prayers
        </button>
        <button
          @click="switchToSinners"
          :class="activeSubTab === 'sinners' ? 'subtab-active' : 'subtab-inactive'"
        >
          😈 Sinners
        </button>
      </div>
    </header>

    <main class="max-w-4xl mx-auto px-4 py-6">
      <!-- Prayers Sub-tab -->
      <div v-if="activeSubTab === 'prayers'">
        <!-- Sort Controls -->
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-theme-text-muted">
            All approved prayers from the community
          </p>
          <div class="flex gap-2">
            <button
              @click="akashic.setSortBy('newest')"
              :class="akashic.sortBy === 'newest' ? 'sort-active' : 'sort-inactive'"
            >
              Newest
            </button>
            <button
              @click="akashic.setSortBy('most_prayed')"
              :class="akashic.sortBy === 'most_prayed' ? 'sort-active' : 'sort-inactive'"
            >
              Most Prayed
            </button>
          </div>
        </div>

        <!-- Loading State -->
        <div v-if="akashic.loading && akashic.publicPrayers.length === 0" class="text-center py-12 text-theme-text-dim">
          <div class="text-4xl mb-3 animate-pulse">📜</div>
          <p>Loading the Akashic Records...</p>
        </div>

        <!-- Empty State -->
        <div v-else-if="akashic.publicPrayers.length === 0 && !akashic.loading" class="glass-panel glass-gloss p-12 text-center border-dashed border-2 border-theme-border">
          <div class="text-6xl mb-4">🕊️</div>
          <h3 class="text-lg font-medium text-theme-text mb-2">No Prayers Yet</h3>
          <p class="text-theme-text-dim">The Akashic Records are empty. Be the first to submit a prayer.</p>
        </div>

        <!-- Prayer Cards -->
        <div v-else class="space-y-4">
          <AkashicPrayerCard
            v-for="prayer in akashic.publicPrayers"
            :key="prayer.id"
            :prayer="prayer"
            :is-active="isPrayerActive(prayer.id)"
            :displayed-count="getPrayerDisplayedCount(prayer.id)"
            :cycle-progress="getPrayerCycleProgress(prayer.id)"
            :animating="counterAnimating"
            :disabled="akashic.altruisticLoading || !!akashic.activeAltruisticPrayer"
            @pray="handlePrayForPrayer"
            @stop="handleStopPraying"
          />
        </div>

        <!-- Load More -->
        <div v-if="akashic.hasMorePrayers" class="mt-6 text-center">
          <button
            @click="akashic.loadMorePrayers()"
            :disabled="akashic.loading"
            class="px-6 py-2.5 text-sm text-theme-accent hover:text-theme-accent-dark transition-colors border border-theme-border/50 rounded-xl hover:border-theme-accent/30 hover:bg-theme-accent/5 disabled:opacity-50"
          >
            {{ akashic.loading ? 'Loading...' : 'Load More Prayers' }}
          </button>
        </div>
      </div>

      <!-- Sinners Sub-tab -->
      <div v-if="activeSubTab === 'sinners'">
        <!-- Loading State -->
        <div v-if="akashic.sinnersLoading && akashic.sinners.length === 0" class="text-center py-12 text-theme-text-dim">
          <div class="text-4xl mb-3 animate-pulse">😈</div>
          <p>Scanning for souls in purgatory...</p>
        </div>

        <!-- Empty State -->
        <div v-else-if="akashic.sinners.length === 0 && !akashic.sinnersLoading" class="glass-panel glass-gloss p-12 text-center border-dashed border-2 border-theme-border">
          <div class="text-6xl mb-4">😇</div>
          <h3 class="text-lg font-medium text-theme-text mb-2">No Souls in Purgatory</h3>
          <p class="text-theme-text-dim">All is well in the spiritual realm. No one is currently condemned.</p>
        </div>

        <!-- Sinner Cards -->
        <div v-else class="space-y-4">
          <p class="text-sm text-theme-text-muted mb-2">
            Pray for these souls to earn karma (+1 per 100 prays). The Electric Monk will generate an intercessory prayer on their behalf.
          </p>
          <SinnerCard
            v-for="sinner in akashic.sinners"
            :key="sinner.id"
            :sinner="sinner"
            :is-active="isSinnerActive(sinner.id)"
            :displayed-count="getSinnerDisplayedCount(sinner.id)"
            :cycle-progress="getSinnerCycleProgress(sinner.id)"
            :animating="counterAnimating"
            :disabled="akashic.altruisticLoading || !!akashic.activeAltruisticPrayer"
            :loading="sinnerPrayerLoading === sinner.id"
            @pray="handlePrayForSinner"
            @stop="handleStopPraying"
          />
        </div>
      </div>

      <!-- Error Display -->
      <div v-if="akashic.error" class="mt-4 p-3 bg-theme-purgatory/20 border border-theme-purgatory rounded text-theme-purgatory-dark text-sm glass-gloss">
        {{ akashic.error }}
      </div>
    </main>

    <!-- Active Altruistic Prayer Overlay (floating counter at bottom) -->
    <Transition name="slide-up">
      <div v-if="akashic.activeAltruisticPrayer && showActiveOverlay" class="fixed bottom-4 left-4 right-4 md:left-auto md:right-4 md:w-96 z-50">
        <div class="glass-panel glass-gloss p-4 border border-theme-accent/50 shadow-glow-accent rounded-xl">
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-2">
              <span class="text-lg">{{ activePrayerTypeIcon }}</span>
              <div>
                <p class="text-sm font-medium text-theme-text">{{ activePrayerTypeLabel }}</p>
                <p v-if="activeTargetName" class="text-xs text-theme-text-muted">{{ activeTargetName }}</p>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-2xl font-bold text-theme-accent font-mono">{{ counterDisplayedCount }}</span>
              <span class="text-xs text-theme-text-muted">prays</span>
            </div>
          </div>
          <!-- Progress Bar -->
          <div class="w-full h-1.5 bg-theme-border/30 rounded-full overflow-hidden">
            <div
              class="h-full rounded-full transition-none"
              :style="{
                width: (counterCycleProgress * 100) + '%',
                background: 'linear-gradient(90deg, #c9a84c, #f5e6a3, #c9a84c)',
                boxShadow: '0 0 8px rgba(201, 168, 76, 0.5)'
              }"
            ></div>
          </div>
          <div class="mt-2 flex justify-end">
            <button
              @click="handleStopPraying"
              class="px-3 py-1 text-xs text-theme-text-dim hover:text-theme-purgatory border border-theme-border rounded hover:border-theme-purgatory/50 transition-colors"
            >
              Stop Praying
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Karma Toast -->
    <KarmaToast
      :amount="karmaToastAmount"
      :type="karmaToastType"
      :label="karmaToastLabel"
      @dismiss="karmaToastAmount = 0"
    />
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useAkashicRecords } from '@/composables/useAkashicRecords'
import { usePrayerCounter } from '@/composables/usePrayerCounter'
import AkashicPrayerCard from '@/components/organisms/AkashicPrayerCard.vue'
import SinnerCard from '@/components/organisms/SinnerCard.vue'
import KarmaToast from '@/components/molecules/KarmaToast.vue'

const prayers = usePrayers()
const akashic = useAkashicRecords()

const activeSubTab = ref('prayers')
const sinnerPrayerLoading = ref(null) // sinner ID being loaded
const showActiveOverlay = ref(true)
const counterAnimating = ref(false)

// Karma toast state
const karmaToastAmount = ref(0)
const karmaToastType = ref('positive')
const karmaToastLabel = ref('')

// Altruistic prayer counter - uses the same usePrayerCounter composable
const activeAltruisticPrayerRef = computed(() => akashic.activeAltruisticPrayer)
const counter = usePrayerCounter(activeAltruisticPrayerRef)

// Expose counter values for template
const counterDisplayedCount = computed(() => counter.displayedCount.value)
const counterCycleProgress = computed(() => counter.cycleProgress.value)

// Watch counter animations
watch(counter.isAnimating, (val) => {
  counterAnimating.value = val
})

// Computed labels for the active overlay
const activePrayerTypeIcon = computed(() => {
  const prayer = akashic.activeAltruisticPrayer
  if (!prayer) return ''
  if (prayer.prayer_type === 'intercessory') return '🕯️'
  return '🙏'
})

const activePrayerTypeLabel = computed(() => {
  const prayer = akashic.activeAltruisticPrayer
  if (!prayer) return ''
  if (prayer.prayer_type === 'intercessory') return 'Intercessory Prayer'
  return 'Altruistic Prayer'
})

const activeTargetName = computed(() => {
  // This would need to be populated from the prayer data
  return ''
})

// Check if a specific prayer is the one being prayed altruistically
function isPrayerActive(prayerId) {
  return akashic.activeAltruisticPrayer?.source_prayer_id === prayerId
}

function isSinnerActive(sinnerId) {
  return akashic.activeAltruisticPrayer?.source_sinner_id === sinnerId
}

function getPrayerDisplayedCount(prayerId) {
  if (isPrayerActive(prayerId)) return counterDisplayedCount.value
  return 0
}

function getPrayerCycleProgress(prayerId) {
  if (isPrayerActive(prayerId)) return counterCycleProgress.value
  return 0
}

function getSinnerDisplayedCount(sinnerId) {
  if (isSinnerActive(sinnerId)) return counterDisplayedCount.value
  return 0
}

function getSinnerCycleProgress(sinnerId) {
  if (isSinnerActive(sinnerId)) return counterCycleProgress.value
  return 0
}

// Switch to sinners tab and load data
async function switchToSinners() {
  activeSubTab.value = 'sinners'
  await akashic.fetchSinners()
}

// Handle "Pray for this prayer" button click
async function handlePrayForPrayer(prayer) {
  try {
    // Start altruistic prayer - the RPC will create/activate the prayer row
    const result = await akashic.startAltruisticPrayer(prayer.id, prayer.response_content)
    
    // The counter will automatically pick up the new active prayer via the reactive ref
    // since akashic.activeAltruisticPrayer is updated by startAltruisticPrayer
    
    // Refresh own prayer state since our active prayer on the Altar was deactivated
    await prayers.fetchPrayers()
  } catch (err) {
    console.error('[AkashicRecordsView] Error starting altruistic prayer:', err)
  }
}

// Handle "Pray for sinner" button click
async function handlePrayForSinner(sinner) {
  try {
    sinnerPrayerLoading.value = sinner.id

    // Step 1: Generate the intercessory prayer via Edge Function
    const result = await akashic.generateSinnerPrayer(sinner.id)

    if (!result.success) {
      throw new Error(result.error || 'Failed to generate intercessory prayer')
    }

    // Step 2: Start the intercessory prayer session
    await akashic.startIntercessoryPrayer(sinner.id, result.response)

    // Refresh own prayer state since our active prayer on the Altar was deactivated
    await prayers.fetchPrayers()
  } catch (err) {
    console.error('[AkashicRecordsView] Error starting intercessory prayer:', err)
  } finally {
    sinnerPrayerLoading.value = null
  }
}

// Handle stopping the active altruistic prayer
async function handleStopPraying() {
  try {
    if (!akashic.activeAltruisticPrayer) return

    // finalSync() calls deactivate_prayer RPC which handles both
    // the final count sync AND deactivation — no need for a second call
    const finalResult = await counter.finalSync()

    // Clear local active prayer state (no second deactivate call)
    akashic.clearActiveAltruisticPrayer()

    // Check for karma milestone in the final sync
    if (finalResult?.karma_change && finalResult.karma_change > 0) {
      karmaToastAmount.value = finalResult.karma_change
      karmaToastType.value = 'positive'
      karmaToastLabel.value = 'Prayer milestone!'
    }

    // Refresh profile to get updated karma
    await prayers.fetchProfile()
  } catch (err) {
    console.error('[AkashicRecordsView] Error stopping altruistic prayer:', err)
  }
}

// Watch for karma milestones from sync operations
watch(() => counter.karmaMilestoneEarned?.value, (val) => {
  if (val && val > 0) {
    karmaToastAmount.value = val
    karmaToastType.value = 'positive'
    karmaToastLabel.value = akashic.activeAltruisticPrayer?.prayer_type === 'intercessory'
      ? 'Intercessory milestone!'
      : 'Altruistic milestone!'
    counter.resetKarmaMilestone()
  }
})

// Load data on mount
onMounted(async () => {
  await akashic.fetchPublicPrayers()
  await prayers.fetchProfile()
})

// Cleanup on unmount
onUnmounted(() => {
  // Stop the counter if active
  if (akashic.activeAltruisticPrayer) {
    counter.stopCounting()
  }
})

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
}
</script>

<style scoped>
/* Sub-tab styles */
.subtab-active {
  @apply px-4 py-2 text-sm font-medium border-b-2 border-theme-accent text-theme-accent transition-colors;
}

.subtab-inactive {
  @apply px-4 py-2 text-sm font-medium border-b-2 border-transparent text-theme-text-muted hover:text-theme-text transition-colors;
}

/* Sort button styles */
.sort-active {
  @apply px-3 py-1 text-xs font-medium rounded-lg bg-theme-accent/15 text-theme-accent border border-theme-accent/30 transition-colors;
}

.sort-inactive {
  @apply px-3 py-1 text-xs font-medium rounded-lg text-theme-text-muted hover:text-theme-text border border-transparent hover:border-theme-border transition-colors;
}

/* Glow effect for active prayer card */
.shadow-glow-accent {
  box-shadow: 0 0 20px color-mix(in srgb, var(--theme-accent) 15%, transparent),
              0 0 40px color-mix(in srgb, var(--theme-accent) 5%, transparent);
}

/* Slide-up transition for active overlay */
.slide-up-enter-active {
  animation: slideUp 0.3s ease-out;
}

.slide-up-leave-active {
  animation: slideDown 0.3s ease-in;
}

@keyframes slideUp {
  from {
    opacity: 0;
    transform: translateY(100%);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes slideDown {
  from {
    opacity: 1;
    transform: translateY(0);
  }
  to {
    opacity: 0;
    transform: translateY(100%);
  }
}
</style>