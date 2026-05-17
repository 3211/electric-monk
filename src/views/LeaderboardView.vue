<template>
  <div>
    <header class="border-b surface-divider bg-theme-panel/55 backdrop-blur-[16px]">
      <div class="app-frame py-6">
        <div class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="relative">
              <div class="leaderboard-header-glow"></div>
              <h1 class="ritual-heading relative text-3xl font-bold text-theme-accent sm:text-4xl">Divine Rankings</h1>
            </div>
            <button
              @click="handleRefresh"
              :disabled="leaderboard.loading"
              class="btn-secondary flex items-center gap-2 px-4 py-2 text-sm"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" :class="{ 'animate-spin': leaderboard.loading }" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              {{ leaderboard.loading ? 'Loading...' : 'Refresh' }}
            </button>
          </div>
          <p class="text-sm text-theme-text-muted">The holiest souls, ranked by their accumulated Karma and Mana.</p>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Loading State -->
      <div v-if="leaderboard.loading && leaderboard.rankings.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
        <div class="mb-3 text-4xl animate-pulse">Loading rankings...</div>
        <p>Summoning the divine ledger...</p>
      </div>

      <!-- Error State -->
      <div v-else-if="leaderboard.error" class="glass-panel glass-panel-soft p-8 text-center text-red-500">
        <p class="mb-2 font-semibold">Failed to load rankings</p>
        <p class="text-sm text-theme-text-muted">{{ leaderboard.error }}</p>
        <button @click="handleRefresh" class="btn-secondary mt-4 px-4 py-2 text-sm">Try Again</button>
      </div>

      <!-- Empty State -->
      <div v-else-if="leaderboard.rankings.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
        <p class="text-lg font-semibold text-theme-text mb-2">No rankings yet</p>
        <p class="text-sm">The divine ledger is empty. Start praying to earn your place!</p>
      </div>

      <!-- Leaderboard Table -->
      <div v-else class="overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr class="border-b border-theme-border/50 text-left text-xs font-medium text-theme-text-muted uppercase tracking-wider">
              <th class="pb-3 pr-4 pl-4 w-16">Rank</th>
              <th class="pb-3 pr-4">Name</th>
              <th class="pb-3 pr-4 hidden sm:table-cell">Faith</th>
              <th class="pb-3 pr-4 text-right">Karma</th>
              <th class="pb-3 pr-4 text-right">Mana</th>
              <th class="pb-3 pr-4 text-right hidden md:table-cell">Gold</th>
              <th class="pb-3 pr-4 text-right hidden md:table-cell">Food</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="player in leaderboard.rankings"
              :key="player.id"
              class="border-b border-theme-border/30 transition-colors duration-200 hover:bg-theme-accent/5"
              :class="{ 'bg-theme-accent/10': isCurrentUser(player.id) }"
            >
              <td class="py-3 pl-4 pr-4">
                <span v-if="player.rank === 1" class="text-lg font-bold text-amber-400">1st</span>
                <span v-else-if="player.rank === 2" class="text-lg font-bold text-gray-400">2nd</span>
                <span v-else-if="player.rank === 3" class="text-lg font-bold text-amber-700">3rd</span>
                <span v-else class="text-sm font-medium text-theme-text-dim">{{ player.rank }}</span>
              </td>
              <td class="py-3 pr-4">
                <span class="text-sm font-semibold text-theme-text">{{ player.username || 'Anonymous' }}</span>
                <span v-if="player.divine_shield_until && new Date(player.divine_shield_until) > new Date()" class="ml-1 text-amber-500" title="Divine Shield active">🛡</span>
              </td>
              <td class="py-3 pr-4 hidden sm:table-cell">
                <span class="text-xs text-theme-text-muted">{{ player.faith || '--' }}</span>
              </td>
              <td class="py-3 pr-4 text-right">
                <span class="text-sm font-semibold text-theme-accent">{{ formatNumber(player.karma) }}</span>
              </td>
              <td class="py-3 pr-4 text-right">
                <span class="text-sm font-semibold text-blue-500">{{ formatNumber(player.mana) }}</span>
              </td>
              <td class="py-3 pr-4 text-right hidden md:table-cell">
                <span class="text-sm text-amber-600">{{ formatNumber(player.gold) }}</span>
              </td>
              <td class="py-3 pr-4 text-right hidden md:table-cell">
                <span class="text-sm text-emerald-600">{{ formatNumber(player.food) }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Your Position Footer -->
      <div v-if="currentUserRank" class="glass-panel glass-panel-soft glass-gloss mt-6 p-4 text-center">
        <p class="text-sm text-theme-text-muted">
          Your position: <span class="font-semibold text-theme-accent">Rank #{{ currentUserRank }}</span>
        </p>
      </div>
    </main>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { useLeaderboard } from '@/composables/useLeaderboard'
import { useAuth } from '@/composables/useAuth'

const leaderboard = useLeaderboard()
const auth = useAuth()
const currentUserId = ref(null)

const currentUserRank = computed(() => {
  if (!currentUserId.value) return null
  return leaderboard.getUserRank(currentUserId.value)
})

function isCurrentUser(playerId) {
  return currentUserId.value && playerId === currentUserId.value
}

function formatNumber(num) {
  if (num === null || num === undefined) return '0'
  return num.toLocaleString()
}

async function handleRefresh() {
  await leaderboard.fetchLeaderboard()
}

onMounted(async () => {
  const { data: { user } } = await auth.session ? { data: { user: auth.user } } : import('@/lib/supabase').then(m => m.supabase.auth.getUser())
  if (user) {
    currentUserId.value = user.id
  }
  await leaderboard.fetchLeaderboard()
})
</script>

<style scoped>
.leaderboard-header-glow {
  position: absolute;
  inset: -1.1rem auto auto -1rem;
  width: 12rem;
  height: 5.5rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.28) 0%, rgba(255, 223, 147, 0.1) 42%, transparent 74%);
  filter: blur(12px);
  pointer-events: none;
}
</style>