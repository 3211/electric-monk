<template>
  <div class="min-h-screen bg-theme-wash">
    <!-- Header -->
    <header class="border-b border-theme-border bg-theme-panel/50 backdrop-blur-sm">
      <div class="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
        <h1 class="text-2xl font-bold text-theme-accent">The Altar</h1>
        <div class="flex items-center gap-4">
          <!-- Daily Token Budget Counter -->
          <div class="text-sm text-theme-text-dim">
            <span class="text-theme-accent font-semibold">{{ prayers.tokensRemaining }}</span>
            tokens remaining today
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

        <form @submit.prevent="handleSubmit">
          <textarea
            v-model="prayerContent"
            :disabled="!prayers.canPray || prayers.loading"
            rows="4"
            class="w-full px-4 py-3 bg-theme-panel border border-theme-border rounded text-theme-text placeholder-theme-text-muted focus:outline-none focus:border-theme-accent focus:ring-1 focus:ring-theme-accent disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            placeholder="Speak your prayer into the void..."
          ></textarea>
          
          <!-- Character Count & Token Cost -->
          <div class="mt-2 flex items-center justify-between text-xs">
            <span class="text-theme-text-muted">
              {{ prayerContent.length }} / {{ maxPrayerChars }} chars
            </span>
            <span class="text-theme-accent font-medium">
              ~{{ estimatedTokenCost }} tokens
            </span>
          </div>
          
          <div class="mt-4 flex items-center justify-between">
            <p v-if="!prayers.canPray" class="text-sm text-theme-text-dim">
              Daily token budget exhausted. Return tomorrow.
            </p>
            <button
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

      <!-- Prayer History -->
      <div class="space-y-4">
        <h2 class="text-xl font-semibold text-theme-text">Prayer History</h2>
        
        <div v-if="prayers.loading && prayers.prayers.length === 0" class="text-center py-8 text-theme-text-dim">
          Loading prayers...
        </div>

        <div v-else-if="prayers.prayers.length === 0" class="text-center py-8 text-theme-text-muted">
          No prayers yet. Submit your first prayer above.
        </div>

        <div v-else class="space-y-3">
          <div
            v-for="prayer in prayers.prayers"
            :key="prayer.id"
            class="glass-panel glass-gloss p-4"
            :class="{
              'border-theme-purgatory': prayer.is_rejected,
              'border-theme-accent': prayer.is_praying && !prayer.is_rejected,
              'border-theme-border': !prayer.is_rejected && !prayer.is_praying
            }"
          >
            <div class="flex items-start justify-between gap-4">
              <p class="text-theme-text flex-1">{{ prayer.content }}</p>
              
              <!-- Status Badge -->
              <span
                class="px-2 py-1 text-xs font-medium rounded whitespace-nowrap"
                :class="{
                  'bg-theme-purgatory/30 text-theme-purgatory-dark': prayer.is_rejected,
                  'bg-theme-accent/30 text-theme-accent-dark': prayer.is_praying && !prayer.is_rejected,
                  'bg-theme-panel text-theme-text-dim': !prayer.is_rejected && !prayer.is_praying
                }"
              >
                {{ getStatusText(prayer) }}
              </span>
            </div>
            
            <!-- Rejection Reason -->
            <p v-if="prayer.rejection_reason" class="mt-2 text-sm text-theme-purgatory-dark italic">
              Rejected: {{ prayer.rejection_reason }}
            </p>
            
            <!-- Timestamp -->
            <p class="mt-2 text-xs text-theme-text-muted">
              {{ formatDate(prayer.created_at) }}
            </p>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useAuth } from '@/composables/useAuth'
import { useBanTimer } from '@/composables/useBanTimer'

// Environment variable for max prayer characters
const maxPrayerChars = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)
const tokenRatio = parseInt(import.meta.env.VITE_PRAYER_TOKEN_RATIO || '5', 10)

const prayers = usePrayers()
const auth = useAuth()
const banTimer = useBanTimer()

const prayerContent = ref('')

// Computed for character count and token cost
const estimatedTokenCost = computed(() => {
  if (!prayerContent.value) return 0
  return Math.ceil(prayerContent.value.length / tokenRatio)
})

onMounted(async () => {
  // Fetch prayers
  await prayers.fetchPrayers()
  await prayers.fetchDailyCount()
})

function getStatusText(prayer) {
  if (prayer.is_rejected) return 'Rejected'
  if (prayer.is_praying) return 'Being Prayed'
  return 'Pending'
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
  try {
    await prayers.submitPrayer(prayerContent.value)
    prayerContent.value = ''
  } catch (err) {
    // Error is already captured in prayers.error
  }
}

async function handleLogout() {
  await auth.signOut()
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
</style>
