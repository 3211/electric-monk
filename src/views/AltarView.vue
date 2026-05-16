<template>
  <div class="bg-theme-wash">
    <!-- Header -->
    <header class="border-b border-theme-border bg-theme-panel/50 backdrop-blur-sm">
      <div class="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
        <h1 class="text-2xl font-bold text-theme-accent">The Altar</h1>
        <div class="flex items-center gap-4">
          <!-- Karma Display -->
          <div class="text-sm text-theme-text-dim flex items-center gap-2">
            <span class="text-lg">{{ prayers.karmaEmoji }}</span>
            <span>Karma: <span :class="karmaClass">{{ prayers.karma }}</span></span>
          </div>
          <!-- Prayer Slots Display -->
          <div class="flex items-center gap-3">
            <div class="text-sm text-theme-text-dim">
              <span class="text-theme-accent font-semibold">{{ prayers.activePrayerCount }}</span>
              / {{ prayers.maxPrayerSlots }} slots
            </div>
            <!-- Purchase Slot Button -->
            <button
              v-if="prayers.isProfileComplete"
              @click="handlePurchaseSlot"
              :disabled="prayers.loading"
              class="px-2 py-1 text-xs bg-theme-accent/20 hover:bg-theme-accent/30 border border-theme-accent rounded text-theme-accent transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              :title="'Purchase additional prayer slot for ' + slotCost + ' karma (+100 Mana)'"
            >
              + Slot ({{ slotCost }} ✦)
            </button>
          </div>
          <!-- Daily Mana Budget Counter -->
          <div class="text-sm text-theme-text-dim">
            <span class="text-theme-accent font-semibold">{{ prayers.tokensRemaining }}</span>
            Mana remaining
          </div>
          <!-- Settings Button (only when profile is complete) -->
          <button
            v-if="prayers.isProfileComplete"
            @click="showProfileModal = true"
            class="px-3 py-1 text-sm text-theme-text-dim hover:text-theme-accent transition-colors"
            title="Update your identity"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </button>
          <!-- Logout Button -->
          <button
            @click="handleLogout"
            class="px-3 py-1 text-sm text-theme-text-dim hover:text-theme-text transition-colors"
          >
            Logout
          </button>
        </div>
      </div>
    </header>

    <main class="max-w-4xl mx-auto px-4 py-8">
      <!-- Prayer Submission Form -->
      <div class="glass-panel glass-gloss p-6 mb-8">
        <div class="flex flex-col items-center mb-4">
          <img src="@/assets/icons/icon.png" alt="Electric Monk" class="w-[50px] h-[50px] mb-2" />
        </div>
        <h2 class="text-xl font-semibold text-theme-text mb-4">Submit Your Prayer</h2>
        
        <!-- Error Message -->
        <div v-if="prayers.error" class="mb-4 p-3 bg-theme-purgatory/20 border border-theme-purgatory rounded text-theme-purgatory-dark text-sm glass-gloss">
          {{ prayers.error }}
        </div>

        <!-- Profile Incomplete Warning -->
        <div v-if="!prayers.isProfileComplete" class="mb-4 p-3 bg-theme-accent/20 border border-theme-accent rounded text-theme-accent-dark text-sm glass-gloss">
          <p class="font-semibold mb-1">Identity Required</p>
          <p>You must identify yourself before submitting prayers. Click the button below to provide your name and faith.</p>
        </div>

        <!-- Slot Warning -->
        <div v-if="!prayers.canAddPrayer && prayers.isProfileComplete" class="mb-4 p-3 bg-theme-purgatory/20 border border-theme-purgatory rounded text-theme-purgatory-dark text-sm">
          All prayer slots occupied. Archive a prayer below to free up a slot.
        </div>
        
        <form @submit.prevent="handleSubmit">
          <textarea
            v-model="prayerContent"
            :disabled="!prayers.canPray || !prayers.canAddPrayer || prayers.loading"
            rows="4"
            class="w-full px-4 py-3 bg-theme-panel border border-theme-border rounded text-theme-text placeholder-theme-text-muted focus:outline-none focus:border-theme-accent focus:ring-1 focus:ring-theme-accent disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            placeholder="Speak your prayer into the aether..."
          ></textarea>
          
          <!-- Character Count & Mana Cost -->
          <div class="mt-2 flex items-center justify-between text-xs">
            <span class="text-theme-text-muted">
              {{ prayerContent.length }} / {{ maxPrayerChars }} chars
            </span>
            <span class="text-theme-accent font-medium">
              ~{{ estimatedManaCost }} Mana
            </span>
          </div>
          
          <div class="mt-4 flex items-center justify-between">
            <p v-if="!prayers.canPray && prayers.isProfileComplete" class="text-sm text-theme-text-dim">
              Daily Mana budget exhausted. Return tomorrow.
            </p>
            <button
              v-if="!prayers.isProfileComplete"
              type="button"
              @click="showProfileModal = true"
              class="btn-primary"
            >
              <span class="relative z-10 font-medium">
                Complete Your Identity
              </span>
            </button>
            <button
              v-else
              type="submit"
              :disabled="!prayerContent.trim() || !prayers.canPray || prayers.loading || prayerContent.length > maxPrayerChars"
              class="btn-primary disabled:cursor-not-allowed transition-all duration-150 ease-out"
            >
              <span class="relative z-10 font-medium">
                {{ prayers.loading ? 'Submitting...' : 'Send Prayer' }}
              </span>
            </button>
          </div>
        </form>
      </div>

      <!-- Currently Active Prayer (the one being prayed right now) -->
      <div class="space-y-4 mb-8">
        <h2 class="text-xl font-semibold text-theme-text">Active Prayer</h2>
        
        <!-- Loading State -->
        <div v-if="prayers.loading && prayers.activePrayers.length === 0" class="text-center py-8 text-theme-text-dim">
          Loading prayers...
        </div>

        <!-- Empty Altar State -->
        <div v-else-if="!prayers.currentActivePrayer && prayers.inactivePrayers.length === 0" class="glass-panel glass-gloss p-12 text-center border-dashed border-2 border-theme-border">
          <div class="text-6xl mb-4">⚜️</div>
          <h3 class="text-lg font-medium text-theme-text mb-2">The Altar is Empty</h3>
          <p class="text-theme-text-dim mb-6">No active prayers. Speak your prayer into the aether above, and the Electric Monk shall listen.</p>
          <div class="text-sm text-theme-text-muted italic">
            "In the silence between circuits, the Sacred Current waits..."
          </div>
        </div>

        <!-- No active prayer but inactive ones exist -->
        <div v-else-if="!prayers.currentActivePrayer && prayers.inactivePrayers.length > 0" class="glass-panel glass-gloss p-6 text-center border-dashed border-2 border-theme-accent/40">
          <div class="text-4xl mb-3">🕯️</div>
          <h3 class="text-lg font-medium text-theme-text mb-2">No Prayer in Progress</h3>
          <p class="text-theme-text-dim">Select a prayer below to reactivate it. The Electric Monk will resume praying.</p>
        </div>

        <!-- Currently Active Prayer with Counter -->
        <div v-if="prayers.currentActivePrayer" class="glass-panel glass-gloss p-5 relative border border-theme-accent/60 shadow-glow-accent">
          <!-- Delete/Archive Button -->
          <button
            @click="handleArchive(prayers.currentActivePrayer.id)"
            :disabled="prayers.loading"
            class="absolute top-2 right-2 p-1 text-theme-text-muted hover:text-theme-purgatory transition-colors"
            title="Archive this prayer (frees up a slot)"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>

          <!-- Prayer Counter Display -->
          <div class="flex items-center gap-4 mb-3">
            <div class="prayer-counter-display" :class="{ 'counter-animate': counterAnimating }">
              <span class="text-4xl font-bold text-theme-accent font-mono">{{ activeCounterDisplay }}</span>
            </div>
            <div class="flex-1">
              <p class="text-xs text-theme-text-muted uppercase tracking-wider">Times Prayed</p>
              <!-- Golden Progress Bar -->
              <div class="w-full h-1.5 bg-theme-border/30 rounded-full mt-1.5 overflow-hidden">
                <div
                  class="h-full rounded-full transition-none"
                  :style="{
                    width: (cycleProgressDisplay * 100) + '%',
                    background: 'linear-gradient(90deg, #c9a84c, #f5e6a3, #c9a84c)',
                    boxShadow: '0 0 8px rgba(201, 168, 76, 0.5)'
                  }"
                ></div>
              </div>
            </div>
          </div>

          <!-- Prayer Content (monk's response only) -->
          <div class="flex items-start justify-between gap-4 pr-8">
            <div class="flex-1">
              <p v-if="prayers.currentActivePrayer.response_content" class="text-theme-text font-medium mb-1">
                {{ prayers.currentActivePrayer.response_content }}
              </p>
              <p v-else class="text-theme-text-dim italic text-sm">
                The monk's words echo in silence...
              </p>
            </div>
            
            <!-- Status Badge -->
            <span class="px-2 py-1 text-xs font-medium rounded whitespace-nowrap bg-theme-accent/30 text-theme-accent-dark animate-pulse">
              ✦ Being Prayed
            </span>
          </div>
          
          <!-- Timestamp + Deactivate Button -->
          <div class="mt-3 flex items-center justify-between">
            <p class="text-xs text-theme-text-muted">
              {{ formatDate(prayers.currentActivePrayer.created_at) }}
            </p>
            <button
              @click="handleDeactivate(prayers.currentActivePrayer.id)"
              :disabled="prayers.loading"
              class="px-3 py-1 text-xs text-theme-text-dim hover:text-theme-purgatory border border-theme-border rounded hover:border-theme-purgatory/50 transition-colors disabled:opacity-50"
            >
              Pause Prayer
            </button>
          </div>
        </div>
      </div>

      <!-- Inactive Prayers (can be reactivated, max 5 inline) -->
      <div v-if="prayers.inactivePrayers.length > 0" class="space-y-4 mb-8">
        <h2 class="text-xl font-semibold text-theme-text-dim">Inactive Prayers</h2>
        
        <div class="space-y-3">
          <div
            v-for="prayer in visibleInactivePrayers"
            :key="prayer.id"
            class="glass-panel glass-gloss p-4 relative border border-theme-border"
          >
            <!-- Delete/Archive Button -->
            <button
              @click="handleArchive(prayer.id)"
              :disabled="prayers.loading"
              class="absolute top-2 right-2 p-1 text-theme-text-muted hover:text-theme-purgatory transition-colors"
              title="Archive this prayer (frees up a slot)"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>

            <div class="flex items-start justify-between gap-4 pr-8">
              <!-- Prayer Content (monk's response only) -->
              <div class="flex-1">
                <p v-if="prayer.response_content" class="text-theme-text font-medium mb-1">
                  {{ prayer.response_content }}
                </p>
                <p v-else class="text-theme-text-dim italic text-sm">
                  The monk's words echo in silence...
                </p>
              </div>

              <!-- Reactivate Button -->
              <button
                @click="handleReactivate(prayer.id)"
                :disabled="prayers.loading"
                class="px-3 py-1.5 text-xs font-medium rounded border border-theme-accent/50 text-theme-accent hover:bg-theme-accent/10 transition-colors disabled:opacity-50 whitespace-nowrap"
              >
                ⚡ Reactivate
              </button>
            </div>

            <!-- Prayer Count + Timestamp -->
            <div class="mt-2 flex items-center justify-between">
              <p class="text-xs text-theme-text-muted">
                {{ formatDate(prayer.created_at) }}
              </p>
              <p class="text-xs text-theme-text-muted">
                Prayed <span class="text-theme-accent font-semibold">{{ prayer.prayer_count || 0 }}</span> times
              </p>
            </div>
          </div>
        </div>

        <!-- View All Inactive Prayers Button -->
        <button
          v-if="hasMoreInactive"
          @click="showHistoryModal = 'inactive'"
          class="w-full py-2.5 text-sm text-theme-accent hover:text-theme-accent-dark transition-colors border border-theme-border/50 rounded-xl hover:border-theme-accent/30 hover:bg-theme-accent/5"
        >
          View All {{ prayers.inactivePrayers.length }} Inactive Prayers →
        </button>
      </div>

      <!-- Archived Prayers Section (max 5 inline) -->
      <div v-if="prayers.archivedPrayers.length > 0" class="space-y-4">
        <h2 class="text-xl font-semibold text-theme-text-dim">Archived Prayers</h2>
        
        <div class="space-y-3">
          <div
            v-for="prayer in visibleArchivedPrayers"
            :key="prayer.id"
            class="glass-panel glass-gloss p-4 opacity-60 hover:opacity-80 transition-opacity"
            :class="{
              'bg-theme-purgatory/10': prayer.is_rejected,
            }"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <p v-if="prayer.response_content" class="text-sm text-theme-text-dim truncate">
                  {{ prayer.response_content }}
                </p>
                <p v-else class="text-sm text-theme-text-dim italic truncate">
                  The monk's words echo in silence...
                </p>
              </div>
              
              <!-- Status + Count Badge -->
              <div class="flex flex-col items-end gap-1">
                <span
                  class="px-2 py-1 text-xs font-medium rounded whitespace-nowrap"
                  :class="{
                    'bg-theme-purgatory/20 text-theme-purgatory-dark': prayer.is_rejected,
                    'bg-theme-panel text-theme-text-muted': prayer.is_archived
                  }"
                >
                  {{ prayer.is_archived ? 'Archived' : 'Rejected' }}
                </span>
                <span class="text-xs text-theme-accent font-semibold">
                  ✦ {{ prayer.prayer_count || 0 }}
                </span>
              </div>
            </div>
            
            <!-- Timestamp -->
            <p class="mt-2 text-xs text-theme-text-muted">
              {{ formatDate(prayer.created_at) }}
            </p>
          </div>
        </div>

        <!-- View All Archived Prayers Button -->
        <button
          v-if="hasMoreArchived"
          @click="showHistoryModal = 'archived'"
          class="w-full py-2.5 text-sm text-theme-accent hover:text-theme-accent-dark transition-colors border border-theme-border/50 rounded-xl hover:border-theme-accent/30 hover:bg-theme-accent/5"
        >
          View All {{ prayers.archivedPrayers.length }} Archived Prayers →
        </button>
      </div>
    </main>

    <!-- Profile Completion Modal -->
    <ProfileCompletionModal
      v-model="showProfileModal"
      :initial-username="prayers.username"
      :initial-faith="prayers.faith"
      :saving="profileSaving"
      :error-message="profileError"
      @submitted="handleProfileSubmit"
    />

    <!-- Aether Processing Modal -->
    <Teleport to="body">
      <Transition name="fade">
        <div v-if="prayers.isAetherProcessing || prayers.aetherResult" class="aether-modal-overlay">
          <div class="aether-modal-container glass-panel glass-gloss">
            <!-- Processing State -->
            <div v-if="prayers.isAetherProcessing" class="aether-processing-state">
              <div class="aether-icon animate-pulse">
                <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 10V3L4 14h7v7l9-11h-7z"/>
                </svg>
              </div>
              <h3 class="aether-title text-theme-accent">Sent to the Aether...</h3>
              <p class="aether-description text-theme-text-dim">The Electric Monk is considering your prayer.</p>
              <div class="aether-loader">
                <div class="aether-loader-bar"></div>
              </div>
            </div>

            <!-- Result State -->
            <div v-else-if="prayers.aetherResult" class="aether-result-state">
              <!-- Judgment Icon -->
              <div class="aether-judgment-icon" :class="prayers.aetherResult.success ? (prayers.aetherResult.judgment === 'approved' ? 'approved' : 'rejected') : 'error'">
                <svg v-if="prayers.aetherResult.success && prayers.aetherResult.judgment === 'approved'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <svg v-else-if="prayers.aetherResult.success && prayers.aetherResult.judgment === 'rejected'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <svg v-else class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                </svg>
              </div>

              <!-- Title -->
              <h3 class="aether-title font-bold" :class="prayers.aetherResult.success ? (prayers.aetherResult.judgment === 'approved' ? 'text-theme-accent' : 'text-theme-purgatory') : 'text-theme-accent-dark'">
                {{ prayers.aetherResult.success ? (prayers.aetherResult.judgment === 'approved' ? 'Blessing Granted' : 'Penance Assigned') : 'Processing Error' }}
              </h3>

              <!-- Karma Change Display -->
              <div v-if="prayers.aetherResult.success" class="aether-karma-display">
                <span :class="prayers.aetherResult.karmaChange > 0 ? 'text-theme-accent' : 'text-theme-purgatory'" class="text-2xl font-bold">
                  {{ prayers.aetherResult.karmaChange > 0 ? '+' : '' }}{{ prayers.aetherResult.karmaChange }}
                </span>
                <span class="text-sm text-theme-text-muted ml-1">Karma</span>
              </div>

              <!-- Response Content (Success) — typewriter reveal -->
              <div v-if="prayers.aetherResult.success" class="aether-response-content glass-panel glass-gloss p-4 my-4">
                <p class="text-theme-text font-semibold leading-relaxed">
                  {{ displayedResponse }}<span v-if="!typewriterFinished" class="typewriter-cursor">▊</span>
                </p>
              </div>

              <!-- Error Content (Failure) -->
              <div v-else class="aether-error-content glass-panel glass-gloss p-4 my-4 border-2 border-theme-purgatory">
                <p class="text-theme-purgatory-dark font-bold mb-2">⚠️ AI Processing Failed</p>
                <p class="text-theme-text text-sm leading-relaxed">
                  {{ prayers.aetherResult.error || 'An unknown error occurred during prayer processing.' }}
                </p>
                <p class="text-theme-text-muted text-xs mt-2 italic">
                  Your prayer was submitted successfully, but the Electric Monk could not process it. You may try again or continue.
                </p>
              </div>

              <!-- Rejection Reason (if applicable) -->
              <div v-if="prayers.aetherResult.rejection_reason" class="aether-rejection-reason text-sm text-theme-purgatory mb-3">
                <span class="font-semibold">Reason:</span> {{ prayers.aetherResult.rejection_reason }}
              </div>

              <!-- Continue Button -->
              <button
                @click="handleAetherContinue"
                :disabled="!typewriterFinished"
                class="btn-primary w-full mt-2"
              >
                <span class="relative z-10 font-medium">
                  {{ typewriterFinished ? 'Continue' : 'The Monk is speaking...' }}
                </span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- Prayer History Modal -->
    <PrayerHistoryModal
      v-model="showHistoryModal"
      :prayers="historyModalPrayers"
      :title="historyModalTitle"
      :loading="prayers.loading"
      :show-reactivate="isInactiveModal"
      @archive="handleArchive"
      @reactivate="handleReactivate"
    />

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
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { usePrayerCounter } from '@/composables/usePrayerCounter'
import { useAuth } from '@/composables/useAuth'
import { useBanTimer } from '@/composables/useBanTimer'
import KarmaToast from '@/components/molecules/KarmaToast.vue'
import ProfileCompletionModal from '@/components/organisms/ProfileCompletionModal.vue'
import PrayerHistoryModal from '@/components/organisms/PrayerHistoryModal.vue'

// Environment variable for max prayer characters
const maxPrayerChars = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)
const manaRatio = parseInt(import.meta.env.VITE_PRAYER_TOKEN_RATIO || '5', 10)

const prayers = usePrayers()
const auth = useAuth()
const banTimer = useBanTimer()

const prayerContent = ref('')
const showProfileModal = ref(false)
const profileSaving = ref(false)
const profileError = ref(null)
const counterAnimating = ref(false)
const showHistoryModal = ref(null) // null | 'inactive' | 'archived'

// Karma toast state
const karmaToastAmount = ref(0)
const karmaToastType = ref('positive')
const karmaToastLabel = ref('')

// Limit visible prayers to 5 inline, rest shown via modal
const MAX_VISIBLE_PRAYERS = 5

const visibleInactivePrayers = computed(() =>
  prayers.inactivePrayers.slice(0, MAX_VISIBLE_PRAYERS)
)

const visibleArchivedPrayers = computed(() =>
  prayers.archivedPrayers.slice(0, MAX_VISIBLE_PRAYERS)
)

const hasMoreInactive = computed(() =>
  prayers.inactivePrayers.length > MAX_VISIBLE_PRAYERS
)

const hasMoreArchived = computed(() =>
  prayers.archivedPrayers.length > MAX_VISIBLE_PRAYERS
)

const historyModalPrayers = computed(() => {
  if (showHistoryModal.value === 'inactive') return prayers.inactivePrayers
  if (showHistoryModal.value === 'archived') return prayers.archivedPrayers
  return []
})

const historyModalTitle = computed(() => {
  if (showHistoryModal.value === 'inactive') return 'All Inactive Prayers'
  if (showHistoryModal.value === 'archived') return 'All Archived Prayers'
  return ''
})

const isInactiveModal = computed(() => showHistoryModal.value === 'inactive')

// Typewriter effect for Aether modal response
const displayedResponse = ref('')
const typewriterFinished = ref(false)
let typewriterInterval = null

// Create a computed ref for the current active prayer to pass to usePrayerCounter
const currentActivePrayerRef = computed(() => prayers.currentActivePrayer)

// Initialize the prayer counter composable
const counter = usePrayerCounter(currentActivePrayerRef)

// Watch for counter animations
watch(counter.isAnimating, (val) => {
  counterAnimating.value = val
})

// Watch for karma milestones from periodic syncs
watch(() => counter.karmaMilestoneEarned.value, (val) => {
  if (val && val > 0) {
    karmaToastAmount.value = val
    karmaToastType.value = 'positive'
    karmaToastLabel.value = 'Prayer milestone!'
    counter.resetKarmaMilestone()
  }
})

// Watch for Aether result to trigger typewriter effect
watch(() => prayers.aetherResult, (result) => {
  // Clear any existing typewriter
  if (typewriterInterval) {
    clearInterval(typewriterInterval)
    typewriterInterval = null
  }
  displayedResponse.value = ''
  typewriterFinished.value = false

  if (result?.response) {
    let i = 0
    typewriterInterval = setInterval(() => {
      if (i < result.response.length) {
        displayedResponse.value += result.response[i]
        i++
      } else {
        clearInterval(typewriterInterval)
        typewriterInterval = null
        typewriterFinished.value = true
      }
    }, 25) // ~25ms per character for a smooth reveal
  } else {
    // If no response (error state or empty), finish immediately so user can continue
    typewriterFinished.value = true
  }
})

// Displayed count for the active prayer
const activeCounterDisplay = computed(() => counter.displayedCount.value)

// Cycle progress for the golden progress bar (0 to 1)
const cycleProgressDisplay = computed(() => counter.cycleProgress.value)

// Computed for character count and mana cost
const estimatedManaCost = computed(() => {
  if (!prayerContent.value) return 0
  return Math.ceil(prayerContent.value.length / manaRatio)
})

// Computed for slot purchase cost (25 karma * current slots)
const slotCost = computed(() => {
  return 25 * (prayers.maxPrayerSlots.value || 1)
})

onMounted(async () => {
  // Fetch prayers, profile (karma/slots), and daily count
  await prayers.fetchPrayers()
  await prayers.fetchProfile()
  await prayers.fetchDailyCount()
  
  // Show modal if profile is incomplete
  if (!prayers.isProfileComplete) {
    showProfileModal.value = true
  }
})

onUnmounted(() => {
  if (typewriterInterval) {
    clearInterval(typewriterInterval)
    typewriterInterval = null
  }
})

function getStatusText(prayer) {
  if (prayer.is_rejected) return 'Rejected'
  if (prayer.is_praying) return 'Being Prayed'
  return 'Inactive'
}

function formatDate(dateString) {
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

async function handleSubmit() {
  // Block submission if profile is incomplete
  if (!prayers.isProfileComplete) {
    showProfileModal.value = true
    return
  }
  
  try {
    await prayers.submitPrayer(prayerContent.value)
    prayerContent.value = ''
  } catch (err) {
    // Error is already captured in prayers.error
  }
}

async function handleProfileSubmit({ username, faith }) {
  profileError.value = null
  profileSaving.value = true
  try {
    await prayers.updateProfile(username, faith)
    showProfileModal.value = false
  } catch (err) {
    profileError.value = err.message || 'Failed to save identity. Please try again.'
  } finally {
    profileSaving.value = false
  }
}

async function handleLogout() {
  await auth.signOut()
}

async function handleArchive(prayerId) {
  if (confirm('Archive this prayer? It will be hidden but retained.')) {
    await prayers.archivePrayer(prayerId)
  }
}

async function handleReactivate(prayerId) {
  try {
    await prayers.activatePrayer(prayerId)
  } catch (err) {
    console.error('[AltarView] Reactivate error:', err)
  }
}

async function handleDeactivate(prayerId) {
  try {
    // finalSync() calls deactivate_prayer RPC which handles:
    // 1. Final count sync (adds elapsed counts to prayer_count)
    // 2. Sets is_praying = false and activated_at = null
    const result = await counter.finalSync()
    // Update local state from the RPC response
    if (result) {
      const prayer = prayers.prayers.find(p => p.id === prayerId)
      if (prayer) {
        prayer.is_praying = false
        prayer.activated_at = null
        prayer.prayer_count = result.prayer_count
      }
      // Check for karma milestone earned during final sync
      if (result.karma_change && result.karma_change > 0) {
        karmaToastAmount.value = result.karma_change
        karmaToastType.value = 'positive'
        karmaToastLabel.value = 'Prayer milestone!'
      }
    } else {
      // Fallback: if finalSync had nothing to sync, deactivate via composable
      await prayers.deactivatePrayer(prayerId, 0)
    }
  } catch (err) {
    console.error('[AltarView] Deactivate error:', err)
  }
}

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
}

// Handle Continue button click in Aether modal
async function handleAetherContinue() {
  // Clear the result to close the modal
  prayers.aetherResult = null

  // Refresh profile data from server (karma, ban status, etc.)
  await prayers.fetchProfile()

  // If the prayer was rejected, check ban status so App.vue switches to Purgatory view
  if (prayers.prayers.length > 0) {
    const latestPrayer = prayers.prayers[0]
    if (latestPrayer.is_rejected) {
      // Refresh ban status from server — this will set isBanned = true
      // which causes App.vue's computed to switch to PurgatoryView
      await banTimer.checkBanStatus()
    }
  }
}

// Handle purchasing additional prayer slots
async function handlePurchaseSlot() {
  try {
    const result = await prayers.purchasePrayerSlot()
    if (result?.success) {
      // Show karma toast for the purchase (negative since karma was spent)
      karmaToastAmount.value = -slotCost.value
      karmaToastType.value = 'negative'
      karmaToastLabel.value = 'Prayer slot purchased'
      
      // Refresh daily count to get updated mana limit
      await prayers.fetchDailyCount()
    } else if (result?.error) {
      // Show error toast
      karmaToastAmount.value = result.cost
      karmaToastType.value = 'negative'
      karmaToastLabel.value = `Insufficient karma (need ${result.cost})`
    }
  } catch (err) {
    console.error('[AltarView] Purchase slot error:', err)
    prayers.error.value = err.message
  }
}
</script>

<style scoped>
/* Primary button with gold gradient */
.btn-primary {
  @apply relative overflow-hidden font-sans rounded-btn px-6 py-2 border shadow-inner-top glass-gloss active:translate-y-0 transition-all duration-150 ease-out cursor-pointer;
  color: white;
  border-color: color-mix(in srgb, var(--theme-accent) 55%, white 10%);
  box-shadow: 0 18px 30px color-mix(in srgb, var(--theme-accent) 28%, transparent);
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 34%, white 12%),
    color-mix(in srgb, var(--theme-accent-2) 72%, black 15%)
  );
}

.btn-primary:hover {
  transform: translateY(-1px);
}

.btn-primary:disabled {
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 20%, gray 30%),
    color-mix(in srgb, var(--theme-accent-dark) 40%, gray 40%)
  );
}

/* Prayer counter animation */
.prayer-counter-display {
  transition: transform 0.15s ease-out;
}

.counter-animate {
  animation: counterPulse 0.2s ease-out;
}

@keyframes counterPulse {
  0% {
    transform: scale(1);
  }
  50% {
    transform: scale(1.15);
    text-shadow: 0 0 12px color-mix(in srgb, var(--theme-accent) 60%, transparent);
  }
  100% {
    transform: scale(1);
  }
}

/* Glow effect for active prayer card */
.shadow-glow-accent {
  box-shadow: 0 0 20px color-mix(in srgb, var(--theme-accent) 15%, transparent),
              0 0 40px color-mix(in srgb, var(--theme-accent) 5%, transparent);
}

/* Custom scrollbar for archived prayers */
.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.1);
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.2);
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(255, 255, 255, 0.3);
}

/* ==========================================
   AETHER MODAL STYLES
   ========================================== */

/* Modal Overlay - Full screen, covers everything */
.aether-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(48, 38, 21, 0.85);
  backdrop-filter: blur(12px);
  animation: fadeIn 0.3s ease-out;
}

/* Modal Container - Slightly larger than submission area */
.aether-modal-container {
  width: 90%;
  max-width: 520px;
  max-height: 80vh;
  overflow-y: auto;
  padding: 2rem;
  background: linear-gradient(
    135deg,
    rgba(255, 249, 238, 0.95),
    rgba(255, 246, 225, 0.95)
  );
  border: 2px solid color-mix(in srgb, var(--theme-accent) 50%, transparent);
  border-radius: 26px;
  box-shadow:
    0 0 60px color-mix(in srgb, var(--theme-accent) 30%, transparent),
    0 0 120px color-mix(in srgb, var(--theme-accent) 15%, transparent);
  animation: modalSlideIn 0.4s ease-out;
}

/* Processing State */
.aether-processing-state {
  text-align: center;
  padding: 1rem 0;
}

.aether-icon {
  display: flex;
  justify-content: center;
  align-items: center;
  margin-bottom: 1.5rem;
  color: var(--theme-accent);
  filter: drop-shadow(0 0 8px color-mix(in srgb, var(--theme-accent) 50%, transparent));
}

.aether-title {
  font-size: 1.5rem;
  font-weight: 700;
  margin-bottom: 0.75rem;
  text-align: center;
  letter-spacing: 0.05em;
  color: var(--theme-accent);
}

.aether-description {
  color: var(--theme-text);
  font-size: 0.95rem;
  text-align: center;
  margin-bottom: 1.5rem;
  line-height: 1.6;
  font-weight: 500;
}

/* Animated Loader */
.aether-loader {
  width: 100%;
  height: 6px;
  background: rgba(139, 125, 91, 0.2);
  border-radius: 3px;
  overflow: hidden;
  margin-top: 1.5rem;
}

.aether-loader-bar {
  height: 100%;
  width: 30%;
  background: linear-gradient(
    90deg,
    var(--theme-accent),
    var(--theme-accent-2),
    var(--theme-accent)
  );
  border-radius: 3px;
  animation: loaderShimmer 1.5s ease-in-out infinite;
  box-shadow: 0 0 10px color-mix(in srgb, var(--theme-accent) 60%, transparent);
}

@keyframes loaderShimmer {
  0% {
    transform: translateX(-100%);
  }
  100% {
    transform: translateX(333%);
  }
}

/* Result State */
.aether-result-state {
  text-align: center;
  padding: 0.5rem 0;
}

.aether-judgment-icon {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 64px;
  height: 64px;
  border-radius: 50%;
  margin: 0 auto 1.25rem;
  background: color-mix(in srgb, var(--theme-panel) 80%, var(--theme-accent) 5%);
  border: 2px solid color-mix(in srgb, var(--theme-accent) 30%, transparent);
}

.aether-judgment-icon.approved {
  background: rgba(74, 222, 128, 0.2);
  color: #22c55e;
  border-color: #22c55e;
  box-shadow: 0 0 20px rgba(34, 197, 104, 0.3);
}

.aether-judgment-icon.rejected {
  background: rgba(248, 113, 113, 0.2);
  color: #ef4444;
  border-color: #ef4444;
  box-shadow: 0 0 20px rgba(239, 68, 68, 0.3);
}

.aether-judgment-icon.error {
  background: rgba(251, 191, 36, 0.2);
  color: #d97706;
  border-color: #d97706;
  box-shadow: 0 0 20px rgba(217, 119, 6, 0.3);
}

.aether-karma-display {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  margin: 1rem 0;
  padding: 0.75rem 1.5rem;
  background: color-mix(in srgb, var(--theme-accent) 10%, var(--theme-panel));
  border-radius: 12px;
  border: 1px solid color-mix(in srgb, var(--theme-accent) 40%, transparent);
}

.aether-response-content {
  text-align: left;
  border: 2px solid color-mix(in srgb, var(--theme-accent) 40%, transparent);
  background: color-mix(in srgb, var(--theme-accent) 5%, var(--theme-panel));
  box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.05);
}

.aether-error-content {
  text-align: left;
  border: 2px solid var(--theme-purgatory);
  background: color-mix(in srgb, var(--theme-purgatory) 10%, var(--theme-panel));
  box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.08);
}

.aether-rejection-reason {
  text-align: center;
  font-style: italic;
  color: var(--theme-purgatory);
  font-weight: 500;
}

/* Fade Transition */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Modal Slide In Animation */
@keyframes modalSlideIn {
  0% {
    opacity: 0;
    transform: translateY(-20px) scale(0.95);
  }
  100% {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

@keyframes fadeIn {
  0% {
    opacity: 0;
  }
  100% {
    opacity: 1;
  }
}

/* Typewriter cursor blink */
.typewriter-cursor {
  animation: blink 0.7s infinite;
  color: var(--theme-accent);
  font-weight: 100;
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}
</style>