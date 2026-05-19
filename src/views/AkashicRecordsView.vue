<template>
  <div :class="activeSubTab === 'sinners' ? 'evil-shell' : ''">
    <header class="akashic-header border-b surface-divider bg-theme-panel/55 backdrop-blur-[16px]">
      <div class="app-frame py-6">
        <div class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="relative">
              <div class="akashic-header-glow"></div>
              <h1 class="ritual-heading relative text-3xl font-bold text-theme-accent sm:text-4xl">📜 Akashic Records</h1>
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <div class="mb-8 flex justify-center">
        <div class="segmented-shell">
          <button
            @click="activeSubTab = 'prayers'"
            class="pill-tab"
            :class="activeSubTab === 'prayers' ? 'pill-tab-active' : 'pill-tab-inactive'"
          >
            📿 Prayers
          </button>
          <button
            @click="switchToShouts"
            class="pill-tab"
            :class="activeSubTab === 'shouts' ? 'pill-tab-active' : 'pill-tab-inactive'"
          >
            📢 Shouts
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
          <div class="mb-4 text-6xl">🕊️🙏</div>
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
            :is-own-prayer="isOwnPrayer(prayer)"
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
            @click="handleLoadMorePrayers"
            :disabled="akashic.loading"
            class="btn-secondary px-6 py-3 text-sm disabled:opacity-50"
          >
            {{ akashic.loading ? 'Loading...' : 'Load More Prayers' }}
          </button>
        </div>
      </div>

      <!-- ==================== SHOUTS TAB ==================== -->
      <div v-if="activeSubTab === 'shouts'" class="space-y-6">
        <!-- Shout Sub-tabs: Global / Sect -->
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Messages from the faithful, filtered through the Town Crier
          </p>
          <div class="segmented-shell self-start sm:self-auto">
            <button
              @click="shoutFilter = 'global'; shouts.fetchShouts(false, 'global')"
              class="pill-tab"
              :class="shoutFilter === 'global' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              🌍 Global
            </button>
            <button
              @click="shoutFilter = 'sect'; shouts.fetchShouts(false, 'sect')"
              class="pill-tab"
              :class="shoutFilter === 'sect' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              ⛪ My Sect
            </button>
          </div>
        </div>

        <!-- Shout Submission Form -->
        <div class="glass-panel glass-panel-strong glass-gloss p-5 sm:p-6">
          <div v-if="shouts.submitError" class="mb-3 rounded-xl border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark">
            {{ shouts.submitError }}
          </div>

          <form @submit.prevent="handleShoutSubmit" class="flex flex-col gap-3">
            <textarea
              v-model="shoutContent"
              :disabled="shouts.submitting"
              rows="3"
              class="form-field resize-none px-4 py-3 text-sm"
              placeholder="Hear ye, hear ye! What tidings do you bring?"
              maxlength="500"
            ></textarea>

            <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <div class="flex items-center gap-3">
                <span class="text-xs text-theme-text-muted">
                  {{ shoutContent.length }} / 500
                </span>
                <span class="text-xs font-medium text-theme-accent">
                  💰 100 Gold
                </span>
                <!-- Sect-Only Toggle -->
                <label class="flex items-center gap-1.5 cursor-pointer select-none" :class="{ 'opacity-50 pointer-events-none': shoutFilter === 'sect' }">
                  <input
                    type="checkbox"
                    v-model="isSectOnly"
                    :disabled="shoutFilter === 'sect'"
                    class="sr-only peer"
                  />
                  <div class="relative w-8 h-4 rounded-full transition-colors duration-200 peer-focus-visible:ring-2 peer-focus-visible:ring-theme-accent/40"
                    :class="isSectOnly ? 'bg-theme-accent' : 'bg-theme-border'"
                  >
                    <div class="absolute top-0.5 left-0.5 w-3 h-3 rounded-full bg-white shadow-sm transition-transform duration-200"
                      :class="isSectOnly ? 'translate-x-4' : 'translate-x-0'"
                    ></div>
                  </div>
                  <span class="text-xs text-theme-text-muted">🔒 Sect Only</span>
                </label>
              </div>
              <button
                type="submit"
                :disabled="!shoutContent.trim() || shouts.submitting || economy.gold < 100"
                class="btn-primary px-6 py-2 text-sm"
              >
                {{ shouts.submitting ? 'Crier is announcing...' : '📢 Shout It!' }}
              </button>
            </div>

            <p v-if="isSectOnly" class="text-xs text-theme-accent/80">Only members of your sect will see this shout.</p>
            <p v-if="economy.gold < 100" class="text-xs text-theme-purgatory-dark">Insufficient gold (need 100).</p>
          </form>
        </div>

        <!-- Shouts Feed -->
        <div v-if="shouts.loading && shouts.shouts.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">📢</div>
          <p>Hark! The Town Crier approaches...</p>
        </div>

        <div v-else-if="shouts.shouts.length === 0 && !shouts.loading" class="glass-panel glass-panel-strong glass-gloss border-2 border-dashed border-theme-border p-12 text-center">
          <div class="mb-4 text-6xl">🔔</div>
          <h3 class="mb-2 text-lg font-medium text-theme-text">No Shouts Yet</h3>
          <p class="text-theme-text-dim">The town square is quiet. Be the first to make your voice heard!</p>
        </div>

        <div v-else class="grid gap-3 sm:grid-cols-2">
          <ShoutCard
            v-for="shout in shouts.shouts"
            :key="shout.id"
            :shout="shout"
            @select="openShoutDetail"
          />
        </div>

        <!-- Load More -->
        <div v-if="shouts.hasMore" class="pt-2 text-center">
          <button
            @click="shouts.loadMoreShouts()"
            :disabled="shouts.loading"
            class="btn-secondary px-6 py-3 text-sm disabled:opacity-50"
          >
            {{ shouts.loading ? 'Loading...' : 'Load More Shouts' }}
          </button>
        </div>
      </div>

      <div v-if="activeSubTab === 'sinners'" class="space-y-6">
        <div v-if="akashic.sinnersLoading && akashic.sinners.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">😈</div>
          <p>Scanning for souls in purgatory...</p>
        </div>

        <div v-else-if="akashic.sinners.length === 0 && !akashic.sinnersLoading" class="glass-panel glass-panel-strong glass-gloss border-2 border-dashed border-theme-border p-12 text-center">
          <div class="mb-4 text-6xl">😈</div>
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
            <div class="rounded-lg border border-theme-accent/20 bg-white/55 px-3 py-2 text-right shadow-[inset_0_1px_0_rgba(255,255,255,0.6)] backdrop-blur-sm">
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

    <!-- Shout Detail Modal -->
    <ShoutDetailModal
      :visible="shoutDetailVisible"
      :shout="shouts.currentShout"
      :replies="shouts.replies"
      :total-replies="shouts.totalReplies"
      :has-more-replies="shouts.repliesHasMore"
      :loading="shoutDetailLoading"
      :replies-loading="shouts.repliesLoading"
      :submitting="shouts.submitting"
      :submit-error="shouts.submitError"
      :blessing-loading="shouts.blessingLoading"
      :blessing-error="shouts.blessingError"
      :blessing-types="blessings.blessingTypes"
      @close="shoutDetailVisible = false"
      @submit-reply="handleShoutReplySubmit"
      @grant-blessing="handleShoutBlessing"
      @load-more-replies="shouts.loadMoreReplies()"
    />

    <!-- Town Crier Aether Modal (mirrors AltarView's Aether modal) -->
    <Teleport to="body">
      <Transition name="fade">
        <div v-if="shouts.isCrierProcessing || shouts.crierResult" class="aether-modal-overlay">
          <div class="aether-modal-container glass-panel glass-panel-strong glass-gloss">
            <!-- Processing State -->
            <div v-if="shouts.isCrierProcessing" class="aether-processing-state">
              <div class="aether-icon animate-pulse">
                <img
                  src="@/assets/icons/town_crier_icon.png"
                  alt="The Town Crier"
                  class="crier-icon-img"
                />
              </div>
              <h3 class="aether-title text-theme-accent">Hear ye, hear ye!</h3>
              <p class="aether-description text-theme-text-dim">The Town Crier is proclaiming your message...</p>
              <div class="aether-loader">
                <div class="aether-loader-bar"></div>
              </div>
            </div>

            <!-- Result State -->
            <div v-else-if="shouts.crierResult" class="aether-result-state">
              <!-- Judgment Icon -->
              <div class="aether-judgment-icon" :class="shouts.crierResult.success ? (shouts.crierResult.judgment === 'approved' ? 'approved' : 'rejected') : 'error'">
                <svg v-if="shouts.crierResult.success && shouts.crierResult.judgment === 'approved'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <svg v-else-if="shouts.crierResult.success && shouts.crierResult.judgment === 'rejected'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <svg v-else class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                </svg>
              </div>

              <!-- Title -->
              <h3 class="aether-title font-bold" :class="shouts.crierResult.success ? (shouts.crierResult.judgment === 'approved' ? 'text-theme-accent' : 'text-theme-purgatory') : 'text-theme-accent-dark'">
                {{ crierStatusTitle }}
              </h3>

              <!-- Response Content (Success) — typewriter reveal -->
              <div v-if="shouts.crierResult.response" class="aether-response-content glass-panel glass-gloss p-4 my-4">
                <p class="text-theme-text font-semibold leading-relaxed">
                  {{ displayedCrierResponse }}<span v-if="!crierTypewriterFinished" class="typewriter-cursor">▊</span>
                </p>
              </div>

              <!-- Error Content (Failure) -->
              <div v-else class="aether-error-content glass-panel glass-gloss p-4 my-4 border-2 border-theme-purgatory">
                <p class="text-theme-purgatory-dark font-bold mb-2">⚠️ Town Crier Unavailable</p>
                <p class="text-theme-text text-sm leading-relaxed">
                  {{ shouts.crierResult.error || 'The Town Crier could not proclaim your message.' }}
                </p>
              </div>

              <!-- Rejection Reason (if applicable) -->
              <div v-if="shouts.crierResult.rejection_reason" class="aether-rejection-reason text-sm text-theme-purgatory mb-3">
                <span class="font-semibold">Reason:</span> {{ shouts.crierResult.rejection_reason }}
              </div>

              <!-- Continue Button -->
              <button
                @click="handleCrierContinue"
                :disabled="!crierTypewriterFinished"
                class="btn-primary w-full mt-2"
              >
                <span class="relative z-10 font-medium">
                  {{ crierTypewriterFinished ? 'Continue' : 'The Crier is speaking...' }}
                </span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted, inject } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useAkashicRecords } from '@/composables/useAkashicRecords'
import { usePrayerCounter } from '@/composables/usePrayerCounter'
import { useBlessings } from '@/composables/useBlessings'
import { useKarmaShop } from '@/composables/useKarmaShop'
import { useAuth } from '@/composables/useAuth'
import { useShouts } from '@/composables/useShouts'
import { useEconomy } from '@/composables/useEconomy'
import AkashicPrayerCard from '@/components/organisms/AkashicPrayerCard.vue'
import SinnerCard from '@/components/organisms/SinnerCard.vue'
import KarmaToast from '@/components/molecules/KarmaToast.vue'
import BlessingPicker from '@/components/organisms/BlessingPicker.vue'
import BlessingDetailModal from '@/components/organisms/BlessingDetailModal.vue'
import ShoutCard from '@/components/molecules/ShoutCard.vue'
import ShoutDetailModal from '@/components/organisms/ShoutDetailModal.vue'
import { useBanTimer } from '@/composables/useBanTimer'

// Inject forceEvilTheme from App.vue for sinners tab
const forceEvilTheme = inject('forceEvilTheme', ref(false))

const prayers = usePrayers()
const akashic = useAkashicRecords()
const blessings = useBlessings()
const shop = useKarmaShop()
const auth = useAuth()
const shouts = useShouts()
const economy = useEconomy()
const banTimer = useBanTimer()

const activeSubTab = ref('prayers')
const sinnerPrayerLoading = ref(null) // sinner ID being loaded

// Toggle evil theme when viewing sinners tab
watch(activeSubTab, (tab) => {
  forceEvilTheme.value = (tab === 'sinners')
}, { immediate: true })
const showActiveOverlay = ref(true)
const counterAnimating = ref(false)

// Karma toast state
const karmaToastAmount = ref(0)
const karmaToastType = ref('positive')
const karmaToastLabel = ref('')

// Shout state
const shoutContent = ref('')
const shoutFilter = ref('global')
const isSectOnly = ref(false)
const shoutDetailVisible = ref(false)
const shoutDetailLoading = ref(false)

// Auto-toggle sect-only when switching shout filter tabs
watch(shoutFilter, (filter) => {
  if (filter === 'sect') {
    isSectOnly.value = true
  } else {
    isSectOnly.value = false
  }
})

// Town Crier typewriter state
const displayedCrierResponse = ref('')
const crierTypewriterFinished = ref(false)
let crierTypewriterInterval = null

const crierStatusTitle = computed(() => {
  if (!shouts.crierResult?.success) return 'Town Crier Unavailable'
  if (shouts.crierResult.judgment === 'approved') return 'Proclamation Announced!'
  return 'Proclamation Rejected'
})

// Blessing state
const blessingPickerVisible = ref(false)
const blessingTargetPrayer = ref(null)
const blessingDetailVisible = ref(false)
const blessingDetailData = ref([])

// Computed: blessing type IDs the CURRENT USER has already granted to the target prayer
// (not all blessings  Eother users' blessings should NOT block the current user from also blessing)
const existingBlessingTypeIds = computed(() => {
  if (!blessingTargetPrayer.value) return []
  return blessings.getMyBlessingTypeIdsForPrayer(blessingTargetPrayer.value.id)
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

// Check if a prayer belongs to the current user (cannot bless your own prayer)
function isOwnPrayer(prayer) {
  return auth.user?.id && prayer.user_id === auth.user.id
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

// Switch to shouts tab and load data
async function switchToShouts() {
  activeSubTab.value = 'shouts'
  await shouts.fetchShouts(false, shoutFilter.value)
  await economy.fetchEconomy()
}

// Watch for crier result to trigger typewriter effect (mirrors AltarView's aetherResult watcher)
watch(() => shouts.crierResult, (result) => {
  if (crierTypewriterInterval) {
    clearInterval(crierTypewriterInterval)
    crierTypewriterInterval = null
  }
  displayedCrierResponse.value = ''
  crierTypewriterFinished.value = false

  if (result?.response) {
    let i = 0
    const text = result.response
    crierTypewriterInterval = setInterval(() => {
      if (i < text.length) {
        displayedCrierResponse.value += text[i]
        i++
      } else {
        clearInterval(crierTypewriterInterval)
        crierTypewriterInterval = null
        crierTypewriterFinished.value = true
      }
    }, 25)
  } else {
    crierTypewriterFinished.value = true
  }
})

// Handle Continue button in Town Crier modal
async function handleCrierContinue() {
  if (crierTypewriterInterval) {
    clearInterval(crierTypewriterInterval)
    crierTypewriterInterval = null
  }
  const result = shouts.crierResult
  shouts.clearCrierResult()

  // Refresh the feed to show the new shout (approved -> posted, rejected -> failed)
  await shouts.fetchShouts(false, shoutFilter.value)
  await economy.fetchEconomy()
  await prayers.fetchProfile()

  // If rejected, check ban status for Purgatory redirect
  if (result?.judgment === 'rejected') {
    await banTimer.checkBanStatus()
  }
}

// Handle shout submission (modal handles the result display now)
async function handleShoutSubmit() {
  if (!shoutContent.value.trim()) return
  const result = await shouts.submitShout(shoutContent.value.trim(), 'global', isSectOnly.value)
  if (result?.success) {
    shoutContent.value = ''
    // Feed refresh and economy update happen in handleCrierContinue after modal dismiss
  }
}

// Open shout detail modal
async function openShoutDetail(shout) {
  shoutDetailVisible.value = true
  shoutDetailLoading.value = true
  await shouts.fetchShoutDetail(shout.id)
  shoutDetailLoading.value = false
}

// Handle shout reply submission
async function handleShoutReplySubmit(content) {
  if (!shouts.currentShout) return
  const result = await shouts.submitReply(shouts.currentShout.id, content)
  if (result?.success) {
    await economy.fetchEconomy()
  }
}

// Handle shout blessing
async function handleShoutBlessing({ blessingTypeId, replyId }) {
  if (!shouts.currentShout) return
  const result = await shouts.grantShoutBlessing(shouts.currentShout.id, blessingTypeId, replyId)
  if (result?.success) {
    karmaToastAmount.value = 1
    karmaToastType.value = 'positive'
    karmaToastLabel.value = '✨ Blessing granted!'
    await prayers.fetchProfile()
  }
}

// Load more prayers and refresh blessing data for new prayers
async function handleLoadMorePrayers() {
  await akashic.loadMorePrayers()
  await refreshBlessingData()
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

// Handle "Bless" button click on prayer card  Eopen BlessingPicker
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

// Refresh blessing data for all visible prayers (both aggregated counts and current user's own blessings)
async function refreshBlessingData() {
  const prayerIds = akashic.publicPrayers.map(p => p.id)
  if (prayerIds.length > 0) {
    await Promise.all([
      blessings.fetchPrayerBlessings(prayerIds),
      blessings.fetchMyBlessingsForPrayers(prayerIds),
    ])
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
    // the final count sync AND deactivation  Eno need for a second call
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
  // CRITICAL: Initialize the realtime channels FIRST. 
  // This ensures the channel object exists and callbacks are locked in before async fetches fire 
  // and trigger reactive UI changes or component watchers.
  akashic.subscribeToRealtime()

  // Execute data fetches safely in the background
  await akashic.fetchPublicPrayers()
  await prayers.fetchProfile()
  await economy.fetchEconomy()
  
  // Fetch blessing data for loaded prayers
  await refreshBlessingData()
  
  // Fetch blessing types (for shout blessings too)
  await blessings.fetchBlessingTypes()
})

// Cleanup on unmount - stop counting and unsubscribe from realtime
onUnmounted(() => {
  // Stop the counter if active
  if (akashic.activeAltruisticPrayer) {
    counter.stopCounting()
  }
  // Clean up typewriter interval
  if (crierTypewriterInterval) {
    clearInterval(crierTypewriterInterval)
    crierTypewriterInterval = null
  }
  // Unsubscribe from realtime channels to prevent memory leaks and conflicts
  akashic.unsubscribeFromRealtime()
})

</script>

<style scoped>
.evil-shell .pill-tab-active {
  color: #f2f5f7;
  border-color: rgba(126, 255, 161, 0.24);
  background:
    linear-gradient(180deg, rgba(233, 241, 247, 0.16), rgba(233, 241, 247, 0.06)),
    linear-gradient(180deg, rgba(38, 40, 48, 0.94), rgba(21, 24, 31, 0.94));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.18),
    0 14px 28px rgba(0, 0, 0, 0.32),
    0 0 22px rgba(126, 255, 161, 0.08);
}

.evil-shell .pill-tab-inactive {
  color: #a9b6c4;
  border-color: rgba(137, 108, 178, 0.18);
  background: rgba(255, 255, 255, 0.04);
  backdrop-filter: blur(10px);
}

.evil-shell .pill-tab-inactive:hover {
  color: #d5ffe0;
  border-color: rgba(126, 255, 161, 0.18);
  background: rgba(126, 255, 161, 0.08);
  transform: translateY(-1px);
}
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
  border-radius: 12px;
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

.crier-icon-img {
  width: 5rem;
  height: 5rem;
  object-fit: contain;
  border-radius: 999px;
}

/* Town Crier Aether Modal (mirrors AltarView) */
.aether-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1.25rem;
  background:
    radial-gradient(circle at 50% 20%, rgba(255, 223, 147, 0.18), transparent 28%),
    linear-gradient(180deg, rgba(48, 38, 21, 0.68), rgba(48, 38, 21, 0.8));
  backdrop-filter: blur(14px);
  animation: overlay-fade var(--dur-enter) var(--ease-standard);
}

.aether-modal-container {
  width: min(92vw, 34rem);
  max-height: min(84vh, 48rem);
  overflow-y: auto;
  padding: clamp(1.5rem, 2vw, 2rem);
  border: 1px solid rgba(213, 154, 23, 0.36);
  border-radius: var(--radius-panel);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.18), transparent 18%),
    linear-gradient(135deg, rgba(255, 250, 241, 0.97), rgba(255, 244, 220, 0.94));
  box-shadow:
    0 24px 70px rgba(48, 38, 21, 0.2),
    0 0 60px rgba(240, 182, 59, 0.14);
  animation: modal-rise var(--dur-hero) var(--ease-silk-settle);
}

.aether-processing-state,
.aether-result-state {
  text-align: center;
  padding: 0.5rem 0;
}

.aether-icon {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 5rem;
  height: 5rem;
  margin: 0 auto 1.5rem;
  border-radius: 999px;
  color: var(--theme-accent);
  background: rgba(255, 248, 228, 0.8);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.72), 0 18px 30px rgba(213, 154, 23, 0.16);
  filter: drop-shadow(0 0 8px rgba(213, 154, 23, 0.24));
}

.aether-title {
  margin-bottom: 0.75rem;
  color: var(--theme-accent);
  font-family: var(--font-display);
  font-size: clamp(1.85rem, 4vw, 2.25rem);
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.02;
}

.aether-description {
  margin-bottom: 1.5rem;
  color: var(--theme-text);
  font-size: 0.98rem;
  line-height: 1.65;
  font-weight: 500;
}

.aether-loader {
  width: 100%;
  height: 0.5rem;
  margin-top: 1.5rem;
  overflow: hidden;
  border-radius: 999px;
  background: linear-gradient(180deg, rgba(139, 125, 91, 0.12), rgba(255, 255, 255, 0.45));
  box-shadow: inset 0 1px 1px rgba(48, 38, 21, 0.08), inset 0 -1px 0 rgba(255, 255, 255, 0.6);
}

.aether-loader-bar {
  height: 100%;
  width: 38%;
  border-radius: inherit;
  background: linear-gradient(90deg, #c79a2c 0%, #f6d980 34%, #fff1bd 52%, #d7a42a 100%);
  animation: loaderShimmer 2.2s var(--ease-silk-settle) infinite;
  box-shadow: 0 0 12px rgba(201, 168, 76, 0.38);
}

.aether-judgment-icon {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 4.5rem;
  height: 4.5rem;
  margin: 0 auto 1.25rem;
  border-radius: 999px;
  background: rgba(255, 249, 235, 0.82);
  border: 1px solid rgba(213, 154, 23, 0.22);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), 0 16px 28px rgba(48, 38, 21, 0.12);
}

.aether-judgment-icon.approved {
  color: #3aa76d;
  border-color: rgba(58, 167, 109, 0.36);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.78), 0 0 24px rgba(58, 167, 109, 0.14);
}

.aether-judgment-icon.rejected {
  color: var(--theme-purgatory);
  border-color: rgba(168, 93, 50, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.78), 0 0 24px rgba(168, 93, 50, 0.14);
}

.aether-judgment-icon.error {
  color: #d18a16;
  border-color: rgba(209, 138, 22, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.78), 0 0 24px rgba(209, 138, 22, 0.14);
}

.aether-response-content {
  margin: 1.25rem 0;
  text-align: left;
  border-radius: 12px;
  border: 1px solid rgba(213, 154, 23, 0.26);
  background: linear-gradient(180deg, rgba(255, 252, 244, 0.84), rgba(255, 247, 228, 0.78));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), inset 0 -1px 0 rgba(213, 154, 23, 0.08);
}

.aether-error-content {
  margin: 1.25rem 0;
  text-align: left;
  border-radius: 12px;
  border: 1px solid rgba(168, 93, 50, 0.28);
  background: linear-gradient(180deg, rgba(255, 248, 242, 0.82), rgba(247, 227, 211, 0.78));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), inset 0 -1px 0 rgba(168, 93, 50, 0.08);
}

.aether-rejection-reason {
  text-align: center;
  font-style: italic;
  color: var(--theme-purgatory);
  font-weight: 500;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity var(--dur-standard) var(--ease-standard);
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.typewriter-cursor {
  animation: blink 0.7s infinite;
  color: var(--theme-accent);
  font-weight: 100;
}

@keyframes loaderShimmer {
  0% {
    transform: translateX(-100%);
  }
  100% {
    transform: translateX(280%);
  }
}

@keyframes blink {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: 0;
  }
}

@keyframes overlay-fade {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes modal-rise {
  from {
    opacity: 0;
    transform: translateY(1.5rem) scale(0.96);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}
</style>