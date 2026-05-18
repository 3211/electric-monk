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
              :disabled="leaderboard.globalLoading"
              class="btn-secondary flex items-center gap-2 px-4 py-2 text-sm"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" :class="{ 'animate-spin': leaderboard.globalLoading }" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              {{ leaderboard.globalLoading ? 'Loading...' : 'Refresh' }}
            </button>
          </div>
          <p class="text-sm text-theme-text-muted">The holiest souls, ranked by faith and divine favor.</p>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Loading State -->
      <div v-if="isInitialLoading" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
        <div class="mb-3 text-4xl animate-pulse">Loading rankings...</div>
        <p>Summoning the divine ledger...</p>
      </div>

      <!-- Error State -->
      <div v-else-if="leaderboard.error" class="glass-panel glass-panel-soft p-8 text-center text-red-500">
        <p class="mb-2 font-semibold">Failed to load rankings</p>
        <p class="text-sm text-theme-text-muted">{{ leaderboard.error }}</p>
        <button @click="handleRefresh" class="btn-secondary mt-4 px-4 py-2 text-sm">Try Again</button>
      </div>

      <template v-else>
        <!-- ===== Global Top 5 Card ===== -->
        <div class="glass-panel glass-panel-soft glass-gloss mb-8 p-5 sm:p-6">
          <h2 class="ritual-heading text-xl font-bold text-theme-accent mb-4 text-center">🏆 Top 5 Overall</h2>
          <div
            ref="globalScrollRef"
            @scroll="onGlobalScroll"
            class="glass-bead-scroll max-h-[310px] overflow-y-auto pr-1"
          >
            <div
              v-for="player in leaderboard.globalTop5"
              :key="player.id"
              class="flex items-center gap-3 py-2.5 px-3 rounded-xl transition-colors duration-200 hover:bg-theme-accent/5"
              :class="{ 'bg-theme-accent/10 ring-1 ring-theme-accent/20': isCurrentUser(player.id) }"
            >
              <span class="leaderboard-rank-badge" :class="rankBadgeClass(player.rank)">
                {{ player.rank }}
              </span>
              <span class="text-sm font-semibold text-theme-text flex-1 truncate">
                {{ isCurrentUser(player.id) ? 'You' : (player.username || 'Anonymous') }}
              </span>
              <span v-if="player.divine_shield_until && new Date(player.divine_shield_until) > new Date()" class="text-amber-500 text-xs flex-shrink-0" title="Divine Shield active">🛡</span>
              <span class="text-xs text-theme-text-muted flex-shrink-0">{{ player.faith || '--' }}</span>
            </div>
            <div v-if="leaderboard.globalLoading" class="text-center py-3 text-sm text-theme-text-muted">
              <span class="animate-pulse">Loading more...</span>
            </div>
            <div v-if="!leaderboard.globalHasMore && leaderboard.globalTop5.length === 0" class="text-center py-6 text-sm text-theme-text-muted">
              No rankings yet
            </div>
          </div>
        </div>

        <!-- ===== Faith Columns Grid ===== -->
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-5 mb-8">
          <div
            v-for="faith in leaderboard.FAITH_KEYS"
            :key="faith"
            class="glass-panel glass-panel-soft glass-gloss faith-column-panel p-4 sm:p-5"
            :class="{ 'faith-column--player': userFaith === faith }"
          >
            <!-- Column Header -->
            <h3 class="ritual-heading text-base font-bold text-theme-accent mb-3 text-center flex items-center justify-center gap-2">
              <span class="text-lg">{{ leaderboard.FAITH_ICONS[faith] }}</span>
              <span class="truncate">{{ leaderboard.FAITH_NAMES[faith] }}</span>
            </h3>

            <!-- Scrollable entries -->
            <div
              :ref="el => setFaithScrollRef(faith, el)"
              @scroll="e => onFaithScroll(faith, e)"
              class="glass-bead-scroll max-h-[340px] overflow-y-auto pr-1"
            >
              <div
                v-for="player in leaderboard.faithColumns[faith].entries"
                :key="player.id"
                class="flex items-center gap-2.5 py-2.5 px-3 rounded-xl transition-colors duration-200 hover:bg-theme-accent/5"
                :class="{ 'bg-theme-accent/10 ring-1 ring-theme-accent/20': isCurrentUser(player.id) }"
              >
                <span class="leaderboard-rank-badge leaderboard-rank-badge--sm" :class="rankBadgeClass(player.faith_rank)">
                  {{ player.faith_rank }}
                </span>
                <span class="text-sm font-semibold text-theme-text flex-1 truncate">
                  {{ player.username || 'Anonymous' }}
                </span>
                <span class="text-xs text-theme-text-muted flex-shrink-0" :title="'Global rank ' + player.global_rank">
                  🌐{{ player.global_rank }}
                </span>
                <span v-if="player.divine_shield_until && new Date(player.divine_shield_until) > new Date()" class="text-amber-500 text-xs flex-shrink-0" title="Divine Shield active">🛡</span>
              </div>

              <div v-if="leaderboard.faithColumns[faith].loading" class="text-center py-3 text-sm text-theme-text-muted">
                <span class="animate-pulse">Loading more...</span>
              </div>

              <div
                v-if="leaderboard.faithColumns[faith].entries.length === 0 && !leaderboard.faithColumns[faith].loading"
                class="text-center py-6 text-sm text-theme-text-muted"
              >
                No members yet
              </div>
            </div>
          </div>
        </div>

        <!-- ===== Your Position ===== -->
        <div
          v-if="leaderboard.userRanks || leaderboard.userRanksLoading"
          class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8 text-center your-position-card"
        >
          <!-- Loading -->
          <div v-if="leaderboard.userRanksLoading && !leaderboard.userRanks" class="text-theme-text-muted">
            <span class="animate-pulse">Consulting the divine ledger...</span>
          </div>

          <!-- Error -->
          <div v-else-if="leaderboard.userRanksError" class="text-red-500 text-sm">
            <p class="font-semibold mb-1">Could not determine your position</p>
            <p class="text-xs text-theme-text-muted">{{ leaderboard.userRanksError }}</p>
          </div>

          <!-- Top 5 Podium -->
          <div v-else-if="leaderboard.userIsTop5">
            <p class="text-lg font-bold text-theme-accent ritual-heading mb-5">
              🏆 Your Position: <span class="text-2xl">Top 5</span>
            </p>
            <div class="max-w-md mx-auto space-y-1">
              <div
                v-for="player in leaderboard.globalTop5.slice(0, 5)"
                :key="player.id"
                class="flex items-center gap-3 py-2.5 px-4 rounded-xl transition-colors duration-200"
                :class="{ 'bg-theme-accent/15 ring-1 ring-theme-accent/35 scale-105': isCurrentUser(player.id) }"
              >
                <span class="leaderboard-rank-badge" :class="rankBadgeClass(player.rank)">
                  {{ player.rank }}
                </span>
                <span class="text-sm font-semibold text-theme-text flex-1 text-left">
                  {{ isCurrentUser(player.id) ? 'You' : (player.username || 'Anonymous') }}
                </span>
                <span v-if="player.divine_shield_until && new Date(player.divine_shield_until) > new Date()" class="text-amber-500 text-xs flex-shrink-0" title="Divine Shield active">🛡</span>
              </div>
            </div>
          </div>

          <!-- Normal Position -->
          <div v-else>
            <p class="text-sm text-theme-text-muted uppercase tracking-wider mb-3">Your Position</p>
            <p class="text-3xl font-bold text-theme-text ritual-heading mb-5">You</p>
            <div class="flex items-center justify-center gap-8">
              <div class="text-center">
                <p class="text-xs text-theme-text-muted uppercase tracking-wider mb-1">Faith Rank</p>
                <p class="text-2xl font-bold text-theme-accent ritual-heading">
                  #{{ leaderboard.userRanks.faith_rank }}
                </p>
                <p class="text-xs text-theme-text-muted mt-1">
                  <span class="mr-1">{{ leaderboard.FAITH_ICONS[leaderboard.userRanks.faith] || '' }}</span>
                  {{ leaderboard.FAITH_NAMES[leaderboard.userRanks.faith] || leaderboard.userRanks.faith || '--' }}
                </p>
              </div>
              <div class="w-px h-14 bg-theme-border"></div>
              <div class="text-center">
                <p class="text-xs text-theme-text-muted uppercase tracking-wider mb-1">Global Rank</p>
                <p class="text-2xl font-bold text-theme-accent ritual-heading">
                  #{{ leaderboard.userRanks.global_rank }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </template>
    </main>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue'
import { useLeaderboard } from '@/composables/useLeaderboard'
import { supabase } from '@/lib/supabase'

const leaderboard = useLeaderboard()
const currentUserId = ref(null)

// Scroll refs
const globalScrollRef = ref(null)
const faithScrollRefs = reactive({})

function setFaithScrollRef(faith, el) {
  faithScrollRefs[faith] = el
}

// Derived
const isInitialLoading = computed(() => {
  return leaderboard.globalLoading && leaderboard.globalTop5.length === 0
})

const userFaith = computed(() => {
  return leaderboard.userRanks?.faith || null
})

function isCurrentUser(playerId) {
  return currentUserId.value && playerId === currentUserId.value
}

function rankBadgeClass(rank) {
  if (rank === 1) return 'rank-gold'
  if (rank === 2) return 'rank-silver'
  if (rank === 3) return 'rank-bronze'
  return 'rank-default'
}

// Scroll handlers
function onGlobalScroll() {
  const el = globalScrollRef.value
  if (!el) return
  if (el.scrollTop + el.clientHeight >= el.scrollHeight - 12) {
    leaderboard.onGlobalScrollToBottom()
  }
}

function onFaithScroll(faith, event) {
  const el = event.target
  if (!el) return
  if (el.scrollTop + el.clientHeight >= el.scrollHeight - 12) {
    leaderboard.onFaithScrollToBottom(faith)
  }
}

async function handleRefresh() {
  await leaderboard.initAll()
}

onMounted(async () => {
  const { data: { user } } = await supabase.auth.getUser()
  if (user) {
    currentUserId.value = user.id
  }
  await leaderboard.initAll()
})

onBeforeUnmount(() => {
  // Clean up refs
  globalScrollRef.value = null
  for (const key of Object.keys(faithScrollRefs)) {
    delete faithScrollRefs[key]
  }
})
</script>

<style scoped>
/* ===== Preserved: Header Glow ===== */
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

/* ===== Rank Badges ===== */
.leaderboard-rank-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  flex-shrink: 0;
  border-radius: 999px;
  font-size: 0.82rem;
  font-weight: 700;
  color: var(--theme-text-dim);
  background: rgba(139, 125, 91, 0.12);
  border: 1px solid rgba(139, 125, 91, 0.14);
}

.leaderboard-rank-badge--sm {
  width: 1.85rem;
  height: 1.85rem;
  font-size: 0.72rem;
}

.rank-gold {
  color: #5c3d0a;
  background: linear-gradient(145deg, rgba(255, 193, 59, 0.95), rgba(213, 154, 23, 0.88));
  border-color: rgba(213, 154, 23, 0.42);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), 0 8px 16px rgba(213, 154, 23, 0.18);
}

.rank-silver {
  color: #3a3f48;
  background: linear-gradient(145deg, rgba(192, 200, 212, 0.92), rgba(156, 164, 176, 0.84));
  border-color: rgba(156, 164, 176, 0.36);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.32), 0 8px 16px rgba(156, 164, 176, 0.14);
}

.rank-bronze {
  color: #4a2e1a;
  background: linear-gradient(145deg, rgba(196, 138, 88, 0.9), rgba(168, 108, 58, 0.82));
  border-color: rgba(168, 108, 58, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28), 0 8px 16px rgba(168, 108, 58, 0.12);
}

/* ===== Faith Column Panel ===== */
.faith-column-panel {
  display: flex;
  flex-direction: column;
  min-height: 360px;
}

.faith-column-panel > :last-child {
  flex: 1 1 auto;
  min-height: 0;
}

.faith-column--player {
  border-color: rgba(213, 154, 23, 0.24) !important;
  box-shadow:
    var(--theme-shadow-soft),
    0 18px 36px rgba(48, 38, 21, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.65),
    0 0 0 1px rgba(213, 154, 23, 0.06) !important;
}

/* ===== Your Position Card ===== */
.your-position-card {
  border-color: rgba(213, 154, 23, 0.28) !important;
  animation: position-card-rise 480ms var(--ease-silk-settle);
}

@keyframes position-card-rise {
  from {
    opacity: 0;
    transform: translateY(16px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* ===== Glass Bead Scrollbar ===== */
.glass-bead-scroll {
  scrollbar-width: thin;
  scrollbar-color: rgba(185, 197, 207, 0.32) rgba(139, 125, 91, 0.06);
}

.glass-bead-scroll::-webkit-scrollbar {
  width: 7px;
}

.glass-bead-scroll::-webkit-scrollbar-track {
  background: rgba(139, 125, 91, 0.06);
  border-radius: 999px;
  margin: 4px 0;
}

.glass-bead-scroll::-webkit-scrollbar-thumb {
  background: linear-gradient(
    180deg,
    rgba(185, 197, 207, 0.42),
    rgba(161, 173, 183, 0.32) 35%,
    rgba(139, 125, 91, 0.28) 65%,
    rgba(185, 197, 207, 0.38)
  );
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.15);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.28),
    inset 0 -1px 0 rgba(0, 0, 0, 0.06),
    0 1px 3px rgba(0, 0, 0, 0.08);
  min-height: 28px;
}

.glass-bead-scroll::-webkit-scrollbar-thumb:hover {
  background: linear-gradient(
    180deg,
    rgba(213, 154, 23, 0.30),
    rgba(185, 197, 207, 0.42) 35%,
    rgba(161, 173, 183, 0.36) 65%,
    rgba(213, 154, 23, 0.26)
  );
  border-color: rgba(255, 255, 255, 0.22);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.35),
    inset 0 -1px 0 rgba(0, 0, 0, 0.04),
    0 2px 6px rgba(0, 0, 0, 0.1);
}

.glass-bead-scroll::-webkit-scrollbar-thumb:active {
  background: linear-gradient(
    180deg,
    rgba(213, 154, 23, 0.38),
    rgba(185, 197, 207, 0.5) 40%,
    rgba(213, 154, 23, 0.34)
  );
}

/* ===== Responsive ===== */
@media (max-width: 768px) {
  .faith-column-panel {
    min-height: 280px;
  }

  .leaderboard-rank-badge {
    width: 2rem;
    height: 2rem;
    font-size: 0.75rem;
  }

  .leaderboard-rank-badge--sm {
    width: 1.7rem;
    height: 1.7rem;
    font-size: 0.68rem;
  }
}
</style>