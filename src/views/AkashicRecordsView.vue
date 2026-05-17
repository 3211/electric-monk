<template>
  <div>
    <header class="akashic-header border-b surface-divider bg-theme-panel/55 backdrop-blur-[16px]">
      <div class="app-frame py-6">
        <div class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="relative">
              <div class="akashic-header-glow"></div>
              <h1 class="ritual-heading relative text-3xl font-bold text-theme-accent sm:text-4xl">📜 Akashic Records</h1>
            </div>
            <div class="chip gap-2 self-start px-4 py-2 text-sm text-theme-text-dim shadow-[0_12px_24px_rgba(48,38,21,0.08)] lg:self-auto">
              <span class="text-lg">{{ prayers.karmaEmoji }}</span>
              <span>Karma: <span :class="karmaClass" class="font-semibold">{{ prayers.karma }}</span></span>
            </div>
          </div>

          <div class="segmented-shell self-start">
            <button
              @click="activeSubTab = 'prayers'"
              class="pill-tab"
              :class="activeSubTab === 'prayers' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              📿 Prayers
            </button>
            <button
              @click="switchToSinners"
              class="pill-tab"
              :class="activeSubTab === 'sinners' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              😈 Sinners
            </button>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <div v-if="activeSubTab === 'prayers'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            All approved prayers from the community
          </p>
          <div class="segmented-shell self-start sm:self-auto">
            <button
              @click="akashic.setSortBy('newest')"
              class="pill-tab"
              :class="akashic.sortBy === 'newest' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              Newest
            </button>
            <button
              @click="akashic.setSortBy('most_prayed')"
              class="pill-tab"
              :class="akashic.sortBy === 'most_prayed' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              Most Prayed
            </button>
          </div>
        </div>

        <div v-if="akashic.loading && akashic.publicPrayers.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">📜</div>
          <p>Loading the Akashic Records...</p>
        </div>

        <div v-else-if="akashic.publicPrayers.length === 0 && !akashic.loading" class="glass-panel glass-panel-strong glass-gloss border-2 border-dashed border-theme-border p-12 text-center">
          <div class="mb-4 text-6xl">🕊️</div>
          <h3 class="mb-2 text-lg font-medium text-theme-text">No Prayers Yet</h3>
          <p class="text-theme-text-dim">The Akashic Records are empty. Be the first to submit a prayer.</p>
        </div>

        <div v-else class="space-y-5">
          <AkashicPrayerCard
            v-for="prayer in akashic.publicPrayers"
            :key="prayer.id"
            :prayer="prayer"
            :blessings="getBlessingsForPrayer(prayer.id)"
            :is-active="isPrayerActive(prayer.id)"
            :displayed-count="getPrayerDisplayedCount(prayer.id)"
            :cycle-progress="getPrayerCycleProgress(prayer.id)"
            :animating="counterAnimating"
            :disabled="akashic.altruisticLoading || !!akashic.activeAltruisticPrayer"
            @pray="handlePrayForPrayer"
            @stop="handleStopPraying"
            @bless="handleBlessPrayer"
            @show-blessing-detail="handleShowBlessingDetail"
          />
        </div>

        <div v-if="akashic.hasMorePrayers" class="pt-2 text-center">
          <button
            @click="akashic.loadMorePrayers()"
            :disabled="akashic.loading"
            class="btn-secondary px-6 py-3 text-sm disabled:opacity-50"
          >
            {{ akashic.loading ? 'Loading...' : 'Load More Prayers' }}
          </button>
        </div>
      </div>

      <div v-if="activeSubTab === 'sinners'" class="space-y-6">
        <div v-if="akashic.sinnersLoading && akashic.sinners.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">😈</div>
          <p>Scanning for souls in purgatory...</p>
        </div>

        <div v-else-if="akashic.sinners.length === 0 && !akashic.sinnersLoading" class="glass-panel glass-panel-strong glass-gloss border-2 border-dashed border-theme-border p-12 text-center">
          <div class="mb-4 text-6xl">😇</div>
          <h3 class="mb-2 text-lg font-medium text-theme-text">No Souls in Purgatory</h3>
          <p class="text-theme-text-dim">All is well in the spiritual realm. No one is currently condemned.</p>
        </div>

        <div v-else class="space-y-5">
          <div class="glass-panel glass-panel-soft glass-gloss p-4 sm:p-5">
            <p class="text-sm text-theme-text-muted">
              Pray for these souls to earn karma (+1 per 100 prays). The Electric Monk will generate an intercessory prayer on their behalf.
            </p>
          </div>
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

      <div v-if="akashic.error" class="glass-panel glass-panel-soft mt-6 border border-theme-purgatory/30 bg-theme-purgatory/10 p-4 text-sm text-theme-purgatory-dark shadow-[0_14px_30px_rgba(168,93,50,0.1)]">
        {{ akashic.error }}
      </div>
    </main>

    <Transition name="slide-up">
      <div v-if="akashic.activeAltruisticPrayer && showActiveOverlay" class="active-overlay-shell fixed bottom-5 left-4 right-4 z-50 md:left-auto md:right-6 md:w-[25rem]">
        <div class="active-overlay-card glass-panel glass-panel-strong glass-gloss border border-theme-accent/40 p-4 shadow-glow-accent sm:p-5">
          <div class="mb-3 flex items-start justify-between gap-4">
            <div class="flex min-w-0 items-center gap-3">
              <span class="chip h-10 w-10 flex-none text-lg text-theme-accent-dark shadow-[0_10px_20px_rgba(213,154,23,0.12)]">{{ activePrayerTypeIcon }}</span>
              <div class="min-w-0">
                <p class="text-sm font-semibold text-theme-text">{{ activePrayerTypeLabel }}</p>
                <p v-if="activeTargetName" class="truncate text-xs text-theme-text-muted">{{ activeTargetName }}</p>
              </div>
            </div>
            <div class="rounded-[18px] border border-theme-accent/20 bg-white/55 px-3 py-2 text-right shadow-[inset_0_1px_0_rgba(255,255,255,0.6)] backdrop-blur-sm">
              <span class="block text-2xl font-bold text-theme-accent font-mono">{{ counterDisplayedCount }}</span>
              <span class="text-[0.7rem] uppercase tracking-[0.18em] text-theme-text-muted">prays</span>
            </div>
          </div>

          <div class="prayer-progress-track">
            <div
              class="prayer-progress-fill transition-none"
              :style="{
                width: (counterCycleProgress * 100) + '%'
              }"
            ></div>
          </div>

          <div class="mt-3 flex justify-end">
            <button
              @click="handleStopPraying"
              class="btn-ghost px-3 py-2 text-xs"
            >
              Stop Praying
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <KarmaToast
      :amount="karmaToastAmount"
      :type="karmaToastType"
      :label="karmaToastLabel"
      @dismiss="karmaToastAmount = 0"
    />

    <!-- Blessing Picker Modal -->
    <BlessingPicker
      :visible="blessingPickerVisible"
      :prayer-username="blessingTargetPrayer?.username || ''"
      :user-karma="prayers.karma"
      :existing-blessing-type-ids="existingBlessingTypeIds"
      @close="blessingPickerVisible = false"
      @select="handleBlessingSelect"
    />

    <!-- Blessing Detail Modal -->
    <BlessingDetailModal
      :visible="blessingDetailVisible"
      :blessings="blessingDetailData"
      @close="blessingDetailVisible = false"
    />
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useAkashicRecords } from '@/composables/useAkashicRecords'
import { usePrayerCounter } from '@/composables/usePrayerCounter'
import { useBlessings } from '@/composables/useBlessings'
import { useKarmaShop } from '@/composables/useKarmaShop'
import AkashicPrayerCard from '@/components/organisms/AkashicPrayerCard.vue'
import SinnerCard from '@/components/organisms/SinnerCard.vue'
import KarmaToast from '@/components/molecules/KarmaToast.vue'
import BlessingPicker from '@/components/organisms/BlessingPicker.vue'
import BlessingDetailModal from '@/components/organisms/BlessingDetailModal.vue'

const prayers = usePrayers()
const akashic = useAkashicRecords()
const blessings = useBlessings()
const shop = useKarmaShop()

const activeSubTab = ref('prayers')
const sinnerPrayerLoading = ref(null) // sinner ID being loaded
const showActiveOverlay = ref(true)
const counterAnimating = ref(false)

// Karma toast state
const karmaToastAmount = ref(0)
const karmaToastType = ref('positive')
const karmaToastLabel = ref('')

// Blessing state
const blessingPickerVisible = ref(false)
const blessingTargetPrayer = ref(null)
const blessingDetailVisible = ref(false)
const blessingDetailData = ref([])

// Computed: existing blessing type IDs for the target prayer (to disable already-granted blessings)
const existingBlessingTypeIds = computed(() => {
  if (!blessingTargetPrayer.value) return []
  const prayerBlessings = blessings.getBlessingsForPrayer(blessingTargetPrayer.value.id)
  return prayerBlessings.map(b => b.blessing_type_id)
})

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

// Get blessings for a specific prayer (from cached blessing data)
function getBlessingsForPrayer(prayerId) {
  // First check if blessings come embedded from the RPC (updated get_public_prayers)
  const prayer = akashic.publicPrayers.find(p => p.id === prayerId)
  if (prayer?.blessings && prayer.blessings.length > 0) {
    return prayer.blessings
  }
  // Fallback to blessing composable cache
  return blessings.getBlessingsForPrayer(prayerId)
}

// Handle "Bless" button click on prayer card — open BlessingPicker
function handleBlessPrayer(prayer) {
  blessingTargetPrayer.value = prayer
  blessingPickerVisible.value = true
}

// Handle blessing selection from BlessingPicker
async function handleBlessingSelect(blessingTypeId) {
  if (!blessingTargetPrayer.value) return

  try {
    const result = await shop.purchaseBlessing(blessingTargetPrayer.value.id, blessingTypeId)

    // Show success toast
    const blessingDef = blessings.getBlessingById(blessingTypeId)
    karmaToastAmount.value = result.karma_spent
    karmaToastType.value = 'positive'
    karmaToastLabel.value = `${blessingDef?.emoji || '✨'} ${blessingDef?.name || 'Blessing'} granted!`

    // Close the picker
    blessingPickerVisible.value = false
    blessingTargetPrayer.value = null

    // Refresh blessing data for all visible prayers
    await refreshBlessingData()

    // Refresh profile to get updated karma
    await prayers.fetchProfile()
  } catch (err) {
    console.error('[AkashicRecordsView] Error granting blessing:', err)
    // Show error toast
    karmaToastAmount.value = 1
    karmaToastType.value = 'negative'
    karmaToastLabel.value = err.message || 'Failed to grant blessing'
  }
}

// Handle "showBlessingDetail" event from AkashicPrayerCard
function handleShowBlessingDetail(prayer) {
  blessingDetailData.value = getBlessingsForPrayer(prayer.id)
  blessingDetailVisible.value = true
}

// Refresh blessing data for all visible prayers
async function refreshBlessingData() {
  const prayerIds = akashic.publicPrayers.map(p => p.id)
  if (prayerIds.length > 0) {
    await blessings.fetchPrayerBlessings(prayerIds)
  }
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

    // Check for sinner redemption (intercessory prayer bonus)
    if (finalResult?.sinner_redeemed) {
      karmaToastAmount.value = 5
      karmaToastType.value = 'positive'
      karmaToastLabel.value = 'Sinner redeemed! +5 bonus karma!'
      // Refresh sinners list to remove the redeemed sinner
      await akashic.fetchSinners()
    } else if (finalResult?.karma_change && finalResult.karma_change > 0) {
      // Check for karma milestone in the final sync
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

// Watch for sinner redemption during intercessory prayer
watch(() => counter.sinnerRedeemed?.value, (val) => {
  if (val) {
    // Sinner was redeemed! Show +5 bonus karma toast
    karmaToastAmount.value = 5
    karmaToastType.value = 'positive'
    karmaToastLabel.value = 'Sinner redeemed! +5 bonus karma!'
    counter.resetSinnerRedeemed()
    // Clear the active prayer since it was auto-deactivated
    akashic.clearActiveAltruisticPrayer()
    // Refresh sinners list to remove the redeemed sinner
    akashic.fetchSinners()
    // Refresh profile to get updated karma
    prayers.fetchProfile()
  }
})

// Load data on mount and subscribe to realtime
onMounted(async () => {
  await akashic.fetchPublicPrayers()
  await prayers.fetchProfile()
  // Fetch blessing data for loaded prayers
  await refreshBlessingData()
  // Subscribe to realtime updates for sinners and intercessory prayers
  akashic.subscribeToRealtime()
})

// Cleanup on unmount - stop counting and unsubscribe from realtime
onUnmounted(() => {
  // Stop the counter if active
  if (akashic.activeAltruisticPrayer) {
    counter.stopCounting()
  }
  // Unsubscribe from realtime channels to prevent memory leaks and conflicts
  akashic.unsubscribeFromRealtime()
})

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
}
</script>

<style scoped>
.akashic-header {
  position: relative;
  overflow: clip;
}

.akashic-header::after {
  content: "";
  position: absolute;
  inset: auto 0 -1px 0;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(213, 154, 23, 0.28), transparent);
}

.akashic-header-glow {
  position: absolute;
  inset: -1.1rem auto auto -1rem;
  width: 12rem;
  height: 5.5rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.28) 0%, rgba(255, 223, 147, 0.1) 42%, transparent 74%);
  filter: blur(12px);
  pointer-events: none;
}

.active-overlay-shell {
  pointer-events: none;
}

.active-overlay-card {
  position: relative;
  overflow: hidden;
  border-radius: 26px;
  pointer-events: auto;
}

.active-overlay-card::before {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.18), transparent 28%),
    radial-gradient(circle at 12% 12%, rgba(255, 223, 147, 0.18), transparent 34%);
}

.slide-up-enter-active {
  animation: overlayDockIn var(--dur-enter) var(--ease-silk-settle);
}

.slide-up-leave-active {
  animation: overlayDockOut 220ms ease;
}

@keyframes overlayDockIn {
  from {
    opacity: 0;
    transform: translateY(1.25rem) scale(0.98);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

@keyframes overlayDockOut {
  from {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
  to {
    opacity: 0;
    transform: translateY(1rem) scale(0.98);
  }
}
</style>