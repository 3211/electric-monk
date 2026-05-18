<template>
  <div class="min-h-screen">
    <!-- Header -->
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="relative min-w-0">
            <div class="merged-header-glow" aria-hidden="true"></div>
            <h1 class="ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">🏛️ The Four Factions</h1>
            <p class="relative mt-1 text-sm text-theme-text-muted">Know thy allies. Fear thy enemies.</p>
          </div>
          <div v-if="playerSect && factionData[playerSect]" class="flex items-center gap-3">
            <div class="chip status-chip gap-2 px-4 py-2 text-sm">
              <span class="text-lg">{{ FACTION_ICONS[playerSect] }}</span>
              <span>{{ FACTION_NAMES[playerSect] }}</span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <div class="mb-8 flex justify-center">
        <div class="segmented-shell">
          <button
            @click="activeTab = 'overview'"
            :class="activeTab === 'overview' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            🏛️ Overview
          </button>
          <button
            @click="activeTab = 'rankings'"
            :class="activeTab === 'rankings' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            🏆 Rankings
          </button>
        </div>
      </div>

      <!-- ===== OVERVIEW TAB ===== -->
      <div v-if="activeTab === 'overview'">
        <!-- Loading -->
        <div v-if="factions.loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">🏛️</div>
          <p class="text-theme-text-dim">Consulting the archives...</p>
        </div>

        <!-- Error -->
        <div v-else-if="factions.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="text-theme-purgatory-dark">{{ factions.error }}</p>
          <button @click="factions.fetchFactions()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
        </div>

        <!-- Main Content -->
        <div v-else class="space-y-10">
          <!-- Diamond Layout -->
          <div class="faction-diamond-wrapper">
            <div class="faction-diamond">
              <!-- SVG Relationship Lines -->
              <svg class="relationship-svg" viewBox="0 0 400 400" preserveAspectRatio="xMidYMid meet" fill="none">
                <!-- Top → Bottom (enemy or vertical axis) -->
                <line x1="200" y1="40" x2="200" y2="360"
                  :stroke="lineStyles.topBottom.color"
                  :stroke-width="lineStyles.topBottom.opacity > 0.5 ? 2.5 : 1"
                  :stroke-opacity="lineStyles.topBottom.opacity"
                  stroke-linecap="round"
                  :stroke-dasharray="lineStyles.topBottom.opacity < 0.3 ? '8 8' : 'none'" />
                <!-- Top → Right (ally or diagonal) -->
                <line x1="200" y1="40" x2="360" y2="200"
                  :stroke="lineStyles.topRight.color"
                  :stroke-width="lineStyles.topRight.opacity > 0.5 ? 2.5 : 1"
                  :stroke-opacity="lineStyles.topRight.opacity"
                  stroke-linecap="round"
                  :stroke-dasharray="lineStyles.topRight.opacity < 0.3 ? '8 8' : 'none'" />
                <!-- Top → Left (neutral) -->
                <line x1="200" y1="40" x2="40" y2="200"
                  :stroke="lineStyles.topLeft.color"
                  :stroke-width="1.5"
                  :stroke-opacity="lineStyles.topLeft.opacity"
                  stroke-linecap="round"
                  stroke-dasharray="6 6" />
                <!-- Cross lines (faded by default) -->
                <line x1="200" y1="360" x2="360" y2="200"
                  stroke="#4a4a5a" stroke-width="1"
                  :stroke-opacity="lineStyles.cross.opacity"
                  stroke-dasharray="4 8" />
                <line x1="200" y1="360" x2="40" y2="200"
                  stroke="#4a4a5a" stroke-width="1"
                  :stroke-opacity="lineStyles.cross.opacity"
                  stroke-dasharray="4 8" />
                <line x1="40" y1="200" x2="360" y2="200"
                  stroke="#4a4a5a" stroke-width="1"
                  :stroke-opacity="lineStyles.cross.opacity"
                  stroke-dasharray="4 8" />
              </svg>

              <!-- Faction Nodes -->
              <div
                v-for="pos in diamondPositions"
                :key="pos.key"
                class="faction-node"
                :class="`faction-node--${pos.slot}`"
                @mouseenter="hoveredFaction = pos.key"
                @mouseleave="hoveredFaction = null"
                @click="selectedFaction = pos.key"
              >
                <div
                  class="faction-node-card glass-panel glass-panel-soft p-3 sm:p-4 cursor-pointer transition-all duration-200"
                  :class="[
                    pos.data ? FACTION_COLORS[pos.key]?.bg : '',
                    pos.data ? FACTION_COLORS[pos.key]?.border : '',
                    pos.key === playerSect ? 'ring-2 ring-theme-accent/40' : '',
                    selectedFaction === pos.key ? 'ring-2 ring-theme-accent/60 shadow-lg' : '',
                  ]"
                >
                  <div class="text-center">
                    <span class="text-2xl sm:text-3xl block mb-1">{{ FACTION_ICONS[pos.key] }}</span>
                    <h3 :class="[pos.data ? FACTION_COLORS[pos.key]?.text : 'text-theme-text-muted', 'font-bold text-xs sm:text-sm leading-tight']">
                      {{ FACTION_NAMES[pos.key] }}
                    </h3>
                    <span v-if="pos.data" class="chip text-xs mt-1 inline-block">
                      {{ pos.data.member_count || 0 }} members
                    </span>
                    <span v-else class="text-xs text-theme-text-muted">No data</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Relationship Legend -->
          <div class="flex flex-wrap items-center justify-center gap-4 text-xs text-theme-text-muted">
            <span class="flex items-center gap-1.5">
              <span class="inline-block w-5 h-0.5 rounded" style="background: #22c55e;"></span> Ally
            </span>
            <span class="flex items-center gap-1.5">
              <span class="inline-block w-5 h-0.5 rounded" style="background: #ef4444;"></span> Enemy
            </span>
            <span class="flex items-center gap-1.5">
              <span class="inline-block w-5 h-0.5 rounded" style="background: #eab308; opacity: 0.5;"></span> Neutral
            </span>
          </div>

          <!-- Selected Faction Detail Panel -->
          <div v-if="selectedFaction && factionData[selectedFaction]" class="faction-detail glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <!-- Header -->
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
              <div class="flex items-center gap-3">
                <span class="text-4xl">{{ FACTION_ICONS[selectedFaction] }}</span>
                <div>
                  <h2 :class="[FACTION_COLORS[selectedFaction]?.text, 'ritual-heading text-2xl font-bold']">
                    {{ FACTION_NAMES[selectedFaction] }}
                  </h2>
                  <p class="text-sm text-theme-text-muted italic mt-1">"{{ factionData[selectedFaction].mission }}"</p>
                </div>
              </div>
              <div v-if="selectedFaction === playerSect" class="chip status-chip text-xs self-start sm:self-center">Your Faction</div>
            </div>

            <!-- Economic Modifiers -->
            <div v-if="factionData[selectedFaction].modifiers && Object.keys(factionData[selectedFaction].modifiers).length > 0" class="mb-6">
              <h3 class="ritual-heading text-lg font-bold text-theme-text mb-3">Economic Modifiers</h3>
              <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                <div
                  v-for="(value, key) in factionData[selectedFaction].modifiers"
                  :key="key"
                  class="rounded-[14px] border border-theme-border/50 bg-theme-panel/30 p-3 text-center"
                >
                  <div class="text-xs text-theme-text-muted">{{ getModifierLabel(key) }}</div>
                  <div class="text-sm font-semibold" :class="parseFloat(value) >= 1 ? 'text-green-600' : 'text-red-400'">
                    {{ formatModifier(value) }}
                  </div>
                </div>
              </div>
            </div>

            <!-- Relationships -->
            <div class="mb-6">
              <h3 class="ritual-heading text-lg font-bold text-theme-text mb-3">Relationships</h3>
              <div class="flex flex-wrap gap-2">
                <span class="chip bg-green-500/10 border border-green-500/30 text-green-600 text-xs py-2 px-3">
                  🟢 Ally: {{ FACTION_NAMES[factionData[selectedFaction].ally] }}
                  <span v-if="factionData[selectedFaction].rationale_ally" class="text-theme-text-muted ml-1">— {{ factionData[selectedFaction].rationale_ally }}</span>
                </span>
                <span class="chip bg-red-500/10 border border-red-500/30 text-red-400 text-xs py-2 px-3">
                  🔴 Enemy: {{ FACTION_NAMES[factionData[selectedFaction].enemy] }}
                  <span v-if="factionData[selectedFaction].rationale_enemy" class="text-theme-text-muted ml-1">— {{ factionData[selectedFaction].rationale_enemy }}</span>
                </span>
                <span class="chip bg-yellow-500/10 border border-yellow-500/30 text-yellow-500 text-xs py-2 px-3">
                  🟡 Neutral: {{ FACTION_NAMES[factionData[selectedFaction].neutral] }}
                  <span v-if="factionData[selectedFaction].rationale_neutral" class="text-theme-text-muted ml-1">— {{ factionData[selectedFaction].rationale_neutral }}</span>
                </span>
              </div>
            </div>

            <!-- Top 5 Members -->
            <div>
              <h3 class="ritual-heading text-lg font-bold text-theme-text mb-3">Top Members</h3>
              <div v-if="(factionData[selectedFaction].top_members || []).length === 0" class="text-center py-6 text-theme-text-muted text-sm">
                No members yet.
              </div>
              <div v-else class="space-y-1">
                <div
                  v-for="(member, i) in factionData[selectedFaction].top_members"
                  :key="member.id"
                  class="flex items-center justify-between p-2.5 rounded-[14px] border border-theme-border/30 bg-theme-panel/20 hover:bg-theme-panel/40 transition-colors duration-150"
                >
                  <div class="flex items-center gap-3">
                    <span class="text-xs text-theme-text-muted w-6 text-right font-mono">{{ i + 1 }}</span>
                    <span class="font-medium text-sm text-theme-text">{{ member.username || 'Unknown' }}</span>
                  </div>
                  <span class="chip text-xs">{{ member.karma }} ⚡</span>
                </div>
              </div>
            </div>
          </div>

          <!-- No faction selected prompt -->
          <div v-else class="glass-panel glass-panel-soft p-8 text-center">
            <p class="text-theme-text-muted text-sm">Click a faction above to see its details.</p>
          </div>
        </div>
      </div>

      <!-- ===== RANKINGS TAB ===== -->
      <div v-if="activeTab === 'rankings'">
        <!-- Loading State -->
        <div v-if="leaderboard.loading && leaderboard.rankings.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading rankings...</div>
          <p>Summoning the divine ledger...</p>
        </div>

        <!-- Error State -->
        <div v-else-if="leaderboard.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="font-semibold text-red-500 mb-2">Failed to load rankings</p>
          <p class="text-sm text-theme-text-muted">{{ leaderboard.error }}</p>
          <button @click="handleRefreshRankings" class="btn-secondary mt-4 px-4 py-2 text-sm">Try Again</button>
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

        <!-- Refresh Button -->
        <div class="mt-6 flex justify-center">
          <button
            @click="handleRefreshRankings"
            :disabled="leaderboard.loading"
            class="btn-secondary flex items-center gap-2 px-4 py-2 text-sm"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" :class="{ 'animate-spin': leaderboard.loading }" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            {{ leaderboard.loading ? 'Loading...' : 'Refresh' }}
          </button>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useFactions, FACTION_ICONS, FACTION_NAMES, FACTION_COLORS, formatModifier, getModifierLabel } from '@/composables/useFactions'
import { useLeaderboard } from '@/composables/useLeaderboard'
import { useAuth } from '@/composables/useAuth'

const factions = useFactions()
const leaderboard = useLeaderboard()
const auth = useAuth()

const {
  factionData,
  loading,
  error,
  hoveredFaction,
  selectedFaction,
  playerSect,
  diamondPositions,
  lineStyles,
  fetchFactions,
  autoSelectPlayerFaction,
} = factions

const activeTab = ref('overview')
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

async function handleRefreshRankings() {
  await leaderboard.fetchLeaderboard()
}

onMounted(async () => {
  // Fetch current user
  const { data: { user } } = await auth.session
    ? { data: { user: auth.user } }
    : import('@/lib/supabase').then(m => m.supabase.auth.getUser())
  if (user) {
    currentUserId.value = user.id
  }

  // Fetch both faction data and leaderboard
  await Promise.all([
    fetchFactions(),
    leaderboard.fetchLeaderboard(),
  ])

  autoSelectPlayerFaction()
})
</script>

<style scoped>
.nav-tab-active,
.nav-tab-inactive {
  @apply pill-tab;
  min-width: 10rem;
}

.nav-tab-active {
  @apply pill-tab-active;
}

.nav-tab-inactive {
  @apply pill-tab-inactive;
}

.faction-diamond-wrapper {
  max-width: 560px;
  margin: 0 auto;
}

.faction-diamond {
  position: relative;
  width: 100%;
  aspect-ratio: 1;
}

.relationship-svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 0;
}

.faction-node {
  position: absolute;
  width: 38%;
  transform: translate(-50%, -50%);
  z-index: 1;
  transition: transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-node:hover {
  transform: translate(-50%, -50%) scale(1.06);
  z-index: 2;
}

.faction-node--top {
  top: 6%;
  left: 50%;
}

.faction-node--right {
  top: 50%;
  left: 94%;
}

.faction-node--bottom {
  top: 94%;
  left: 50%;
}

.faction-node--left {
  top: 50%;
  left: 6%;
}

.faction-node-card {
  transition: all 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-detail {
  animation: detail-rise 320ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

@keyframes detail-rise {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.merged-header-glow {
  position: absolute;
  inset: -1rem auto auto -1rem;
  width: 13rem;
  height: 6rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.28) 0%, rgba(255, 223, 147, 0.1) 42%, transparent 74%);
  filter: blur(12px);
  pointer-events: none;
}

@media (max-width: 640px) {
  .faction-diamond-wrapper {
    max-width: 340px;
  }

  .faction-node {
    width: 42%;
  }

  .faction-node--top {
    top: 5%;
  }

  .faction-node--bottom {
    top: 95%;
  }

  .faction-node--left {
    left: 5%;
  }

  .faction-node--right {
    left: 95%;
  }

  .nav-tab-active,
  .nav-tab-inactive {
    min-width: 0;
    width: 100%;
  }
}
</style>