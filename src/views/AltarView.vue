<template>
  <div class="min-h-screen bg-gradient-to-b from-gray-900 to-gray-800">
    <!-- Header -->
    <header class="border-b border-gray-700 bg-gray-900/50 backdrop-blur-sm">
      <div class="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
        <h1 class="text-2xl font-bold text-amber-500">The Altar</h1>
        <div class="flex items-center gap-4">
          <!-- Daily Prayer Counter -->
          <div class="text-sm text-gray-400">
            <span class="text-amber-500 font-semibold">{{ prayers.prayersRemaining }}</span>
            prayers remaining today
          </div>
          <!-- Logout Button -->
          <button
            @click="handleLogout"
            class="px-3 py-1 text-sm text-gray-400 hover:text-white transition-colors"
          >
            Logout
          </button>
        </div>
      </div>
    </header>

    <main class="max-w-4xl mx-auto px-4 py-8">
      <!-- Prayer Submission Form -->
      <div class="bg-gray-800/50 rounded-lg p-6 mb-8 border border-gray-700">
        <h2 class="text-xl font-semibold text-gray-200 mb-4">Submit Your Prayer</h2>
        
        <!-- Error Message -->
        <div v-if="prayers.error" class="mb-4 p-3 bg-red-900/50 border border-red-700 rounded text-red-200 text-sm">
          {{ prayers.error }}
        </div>

        <form @submit.prevent="handleSubmit">
          <textarea
            v-model="prayerContent"
            :disabled="!prayers.canPray || prayers.loading"
            rows="4"
            class="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded text-white placeholder-gray-500 focus:outline-none focus:border-amber-500 focus:ring-1 focus:ring-amber-500 disabled:opacity-50 disabled:cursor-not-allowed"
            placeholder="Speak your prayer into the void..."
          ></textarea>
          
          <div class="mt-4 flex items-center justify-between">
            <p v-if="!prayers.canPray" class="text-sm text-gray-400">
              Daily limit reached. Return tomorrow.
            </p>
            <button
              type="submit"
              :disabled="!prayerContent.trim() || !prayers.canPray || prayers.loading"
              class="px-6 py-2 bg-amber-600 hover:bg-amber-700 disabled:bg-amber-800 disabled:cursor-not-allowed text-white font-semibold rounded transition-colors"
            >
              {{ prayers.loading ? 'Submitting...' : 'Send Prayer' }}
            </button>
          </div>
        </form>
      </div>

      <!-- Prayer History -->
      <div class="space-y-4">
        <h2 class="text-xl font-semibold text-gray-200">Prayer History</h2>
        
        <div v-if="prayers.loading && prayers.prayers.length === 0" class="text-center py-8 text-gray-400">
          Loading prayers...
        </div>

        <div v-else-if="prayers.prayers.length === 0" class="text-center py-8 text-gray-500">
          No prayers yet. Submit your first prayer above.
        </div>

        <div v-else class="space-y-3">
          <div
            v-for="prayer in prayers.prayers"
            :key="prayer.id"
            class="bg-gray-800/30 rounded-lg p-4 border"
            :class="{
              'border-red-700': prayer.is_rejected,
              'border-amber-700': prayer.is_praying && !prayer.is_rejected,
              'border-gray-700': !prayer.is_rejected && !prayer.is_praying
            }"
          >
            <div class="flex items-start justify-between gap-4">
              <p class="text-gray-300 flex-1">{{ prayer.content }}</p>
              
              <!-- Status Badge -->
              <span
                class="px-2 py-1 text-xs font-medium rounded whitespace-nowrap"
                :class="{
                  'bg-red-900 text-red-200': prayer.is_rejected,
                  'bg-amber-900 text-amber-200': prayer.is_praying && !prayer.is_rejected,
                  'bg-gray-700 text-gray-300': !prayer.is_rejected && !prayer.is_praying
                }"
              >
                {{ getStatusText(prayer) }}
              </span>
            </div>
            
            <!-- Rejection Reason -->
            <p v-if="prayer.rejection_reason" class="mt-2 text-sm text-red-400 italic">
              Rejected: {{ prayer.rejection_reason }}
            </p>
            
            <!-- Timestamp -->
            <p class="mt-2 text-xs text-gray-500">
              {{ formatDate(prayer.created_at) }}
            </p>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useAuth } from '@/composables/useAuth'
import { useBanTimer } from '@/composables/useBanTimer'

const prayers = usePrayers()
const auth = useAuth()
const banTimer = useBanTimer()

const prayerContent = ref('')

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
    // Error is captured in prayers.error
  }
}

async function handleLogout() {
  await auth.signOut()
}
</script>
