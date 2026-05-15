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
          <div class="text-sm text-theme-text-dim">
            <span class="text-theme-accent font-semibold">{{ prayers.activePrayerCount }}</span>
            / {{ prayers.maxPrayerSlots }} slots
          </div>
          <!-- Daily Mana Budget Counter -->
          <div class="text-sm text-theme-text-dim">
            <span class="text-theme-accent font-semibold">{{ prayers.tokensRemaining }}</span>
            Mana remaining
          </div>
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
            placeholder="Speak your prayer into the void..."
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
          <p class="text-theme-text-dim mb-6">No active prayers. Speak your prayer into the void above, and the Electric Monk shall listen.</p>
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
            <div>
              <p class="text-xs text-theme-text-muted uppercase tracking-wider">Times Prayed</p>
              <p class="text-xs text-theme-accent/70">~{{ cycleTimeDisplay }} cycle</p>
            </div>
          </div>

          <!-- Prayer Content -->
          <div class="flex items-start justify-between gap-4 pr-8">
            <div class="flex-1">
              <p v-if="prayers.currentActivePrayer.response_content" class="text-theme-text font-medium mb-1">
                {{ prayers.currentActivePrayer.response_content }}
              </p>
              <p class="text-theme-text-dim italic text-sm">
                "{{ prayers.currentActivePrayer.content }}"
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

      <!-- Inactive Prayers (can be reactivated) -->
      <div v-if="prayers.inactivePrayers.length > 0" class="space-y-4 mb-8">
        <h2 class="text-xl font-semibold text-theme-text-dim">Inactive Prayers</h2>
        
        <div class="space-y-3">
          <div
            v-for="prayer in prayers.inactivePrayers"
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
              <!-- Prayer Content -->
              <div class="flex-1">
                <p v-if="prayer.response_content" class="text-theme-text font-medium mb-1">
                  {{ prayer.response_content }}
                </p>
                <p class="text-theme-text-dim italic text-sm">
                  "{{ prayer.content }}"
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
      </div>

      <!-- Archived Prayers Section (Scrollable) -->
      <div v-if="prayers.archivedPrayers.length > 0" class="space-y-4">
        <h2 class="text-xl font-semibold text-theme-text-dim">Archived Prayers</h2>
        
        <div class="glass-panel glass-gloss p-4 max-h-64 overflow-y-auto space-y-3 custom-scrollbar">
          <div
            v-for="prayer in prayers.archivedPrayers"
            :key="prayer.id"
            class="p-3 border border-theme-border/30 rounded opacity-60 hover:opacity-80 transition-opacity"
            :class="{
              'bg-theme-purgatory/10': prayer.is_rejected,
              'bg-theme-panel': prayer.is_archived
            }"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <p class="text-sm text-theme-text-dim truncate">
                  {{ prayer.content }}
                </p>
                <p v-if="prayer.response_content" class="text-xs text-theme-text-muted mt-1">
                  → {{ prayer.response_content }}
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
      </div>
    </main>

    <!-- Profile Completion Modal -->
    <ProfileCompletionModal
      v-model="showProfileModal"
      :initial-username="prayers.username"
      :initial-faith="prayers.faith"
      @submitted="handleProfileSubmit"
    />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { usePrayerCounter } from '@/composables/usePrayerCounter'
import { useAuth } from '@/composables/useAuth'
import { useBanTimer } from '@/composables/useBanTimer'
import ProfileCompletionModal from '@/components/organisms/ProfileCompletionModal.vue'

// Environment variable for max prayer characters
const maxPrayerChars = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)
const manaRatio = parseInt(import.meta.env.VITE_PRAYER_TOKEN_RATIO || '5', 10)

const prayers = usePrayers()
const auth = useAuth()
const banTimer = useBanTimer()

const prayerContent = ref('')
const showProfileModal = ref(false)
const counterAnimating = ref(false)

// Create a computed ref for the current active prayer to pass to usePrayerCounter
const currentActivePrayerRef = computed(() => prayers.currentActivePrayer)

// Initialize the prayer counter composable
const counter = usePrayerCounter(currentActivePrayerRef)

// Watch for counter animations
watch(counter.isAnimating, (val) => {
  counterAnimating.value = val
})

// Displayed count for the active prayer
const activeCounterDisplay = computed(() => counter.displayedCount.value)

// Calculate cycle time display string
const cycleTimeDisplay = computed(() => {
  if (!prayers.currentActivePrayer) return '0ms'
  const content = prayers.currentActivePrayer.content || ''
  const cycleMs = Math.max(150, Math.ceil(content.length / 5) * 150)
  if (cycleMs < 1000) return `${cycleMs}ms`
  return `${(cycleMs / 1000).toFixed(1)}s`
})

// Computed for character count and mana cost
const estimatedManaCost = computed(() => {
  if (!prayerContent.value) return 0
  return Math.ceil(prayerContent.value.length / manaRatio)
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
  try {
    await prayers.updateProfile(username, faith)
    showProfileModal.value = false
  } catch (err) {
    // Error is already captured in prayers.error
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
</style>