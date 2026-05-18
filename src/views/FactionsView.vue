<template>
  <div class="min-h-screen">
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

      <div v-if="activeTab === 'overview'">
        <div v-if="factions.loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">🏛️</div>
          <p class="text-theme-text-dim">Consulting the archives...</p>
        </div>

        <div v-else-if="factions.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="text-theme-purgatory-dark">{{ factions.error }}</p>
          <button @click="factions.fetchFactions()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
        </div>

        <div v-else class="space-y-10">
          <section class="factions-stage glass-panel glass-panel-strong glass-gloss p-5 sm:p-6 lg:p-8">
            <div class="factions-stage-grid">
              <div class="factions-roster">
                <button
                  v-for="pos in displayPositions"
                  :key="`${pos.key}-summary`"
                  type="button"
                  class="faction-roster-card"
                  :class="[
                    selectedFaction === pos.key ? 'faction-roster-card--selected' : '',
                    pos.key === playerSect ? 'faction-roster-card--player' : '',
                  ]"
                  :aria-pressed="selectedFaction === pos.key ? 'true' : 'false'"
                  @mouseenter="hoveredFaction = pos.key"
                  @mouseleave="hoveredFaction = null"
                  @click="selectFaction(pos.key)"
                >
                  <div class="faction-roster-orb">
                    <span class="text-2xl">{{ FACTION_ICONS[pos.key] }}</span>
                  </div>
                  <div class="min-w-0 flex-1 text-left">
                    <div class="flex flex-wrap items-center gap-2">
                      <h3 :class="[pos.data ? FACTION_COLORS[pos.key]?.text : 'text-theme-text-muted', 'truncate text-sm font-semibold']">
                        {{ FACTION_NAMES[pos.key] }}
                      </h3>
                      <span v-if="pos.key === playerSect" class="chip status-chip text-[0.65rem] px-2 py-0.5">Your Faction</span>
                    </div>
                    <div class="mt-2 flex flex-wrap items-center gap-2">
                      <span v-if="pos.data" class="chip text-xs">
                        {{ pos.data.member_count || 0 }} members
                      </span>
                      <span v-else class="text-xs text-theme-text-muted">No data</span>
                    </div>
                  </div>
                </button>
              </div>

              <div class="faction-diamond-wrapper">
                <div class="faction-diamond-shell">
                  <div class="faction-diamond-aura" aria-hidden="true"></div>
                  <div class="faction-core-seal" aria-hidden="true">
                    <span class="faction-core-seal-icon">{{ FACTION_ICONS[focusFactionKey] || '🏛️' }}</span>
                    <span v-if="focusFactionKey && factionData[focusFactionKey]" class="chip text-[0.65rem] px-2 py-0.5">
                      {{ factionData[focusFactionKey].member_count || 0 }} members
                    </span>
                  </div>

                  <div class="faction-diamond">
                    <svg class="relationship-svg" viewBox="0 0 400 400" preserveAspectRatio="xMidYMid meet" fill="none">
                      <line
                        x1="200"
                        y1="40"
                        x2="200"
                        y2="360"
                        :stroke="mapLineStyles.topBottom.color"
                        :stroke-width="mapLineStyles.topBottom.opacity > 0.5 ? 2.5 : 1"
                        :stroke-opacity="mapLineStyles.topBottom.opacity"
                        stroke-linecap="round"
                        :stroke-dasharray="mapLineStyles.topBottom.opacity < 0.3 ? '8 8' : 'none'"
                      />
                      <line
                        x1="200"
                        y1="40"
                        x2="360"
                        y2="200"
                        :stroke="mapLineStyles.topRight.color"
                        :stroke-width="mapLineStyles.topRight.opacity > 0.5 ? 2.5 : 1"
                        :stroke-opacity="mapLineStyles.topRight.opacity"
                        stroke-linecap="round"
                        :stroke-dasharray="mapLineStyles.topRight.opacity < 0.3 ? '8 8' : 'none'"
                      />
                      <line
                        x1="200"
                        y1="40"
                        x2="40"
                        y2="200"
                        :stroke="mapLineStyles.topLeft.color"
                        :stroke-width="1.5"
                        :stroke-opacity="mapLineStyles.topLeft.opacity"
                        stroke-linecap="round"
                        stroke-dasharray="6 6"
                      />
                      <line
                        x1="200"
                        y1="360"
                        x2="360"
                        y2="200"
                        stroke="#4a4a5a"
                        stroke-width="1"
                        :stroke-opacity="mapLineStyles.cross.opacity"
                        stroke-dasharray="4 8"
                      />
                      <line
                        x1="200"
                        y1="360"
                        x2="40"
                        y2="200"
                        stroke="#4a4a5a"
                        stroke-width="1"
                        :stroke-opacity="mapLineStyles.cross.opacity"
                        stroke-dasharray="4 8"
                      />
                      <line
                        x1="40"
                        y1="200"
                        x2="360"
                        y2="200"
                        stroke="#4a4a5a"
                        stroke-width="1"
                        :stroke-opacity="mapLineStyles.cross.opacity"
                        stroke-dasharray="4 8"
                      />
                    </svg>

                    <div
                      v-for="pos in displayPositions"
                      :key="pos.key"
                      class="faction-node"
                      :class="`faction-node--${pos.slot}`"
                      @mouseenter="hoveredFaction = pos.key"
                      @mouseleave="hoveredFaction = null"
                      @click="selectFaction(pos.key)"
                    >
                      <div
                        class="faction-node-card cursor-pointer p-3 sm:p-4"
                        :class="[
                          pos.key === playerSect ? 'ring-2 ring-theme-accent/35 shadow-glow-gold' : '',
                          selectedFaction === pos.key ? 'faction-node-card--selected ring-2 ring-theme-accent/60 shadow-lg' : '',
                        ]"
                      >
                        <div class="text-center">
                          <span class="faction-node-icon text-2xl sm:text-3xl">{{ FACTION_ICONS[pos.key] }}</span>
                          <h3 :class="[pos.data ? FACTION_COLORS[pos.key]?.text : 'text-theme-text-muted', 'mt-2 font-bold text-xs sm:text-sm leading-tight']">
                            {{ FACTION_NAMES[pos.key] }}
                          </h3>
                          <span v-if="pos.data" class="chip mt-2 inline-flex text-xs">
                            {{ pos.data.member_count || 0 }} members
                          </span>
                          <span v-else class="mt-2 block text-xs text-theme-text-muted">No data</span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="relationship-legend">
              <span class="relationship-legend-item">
                <span class="inline-block h-0.5 w-5 rounded" style="background: #22c55e;"></span> Ally
              </span>
              <span class="relationship-legend-item">
                <span class="inline-block h-0.5 w-5 rounded" style="background: #ef4444;"></span> Enemy
              </span>
              <span class="relationship-legend-item">
                <span class="inline-block h-0.5 w-5 rounded" style="background: #eab308; opacity: 0.5;"></span> Neutral
              </span>
            </div>
          </section>

          <div :key="selectedFaction" v-if="selectedFaction && factionData[selectedFaction]" class="faction-detail glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <div class="faction-detail-grid">
              <div class="space-y-6">
                <div class="faction-detail-header">
                  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                    <div class="flex items-start gap-4">
                      <span class="faction-detail-icon text-4xl">{{ FACTION_ICONS[selectedFaction] }}</span>
                      <div>
                        <h2 :class="[FACTION_COLORS[selectedFaction]?.text, 'ritual-heading text-2xl font-bold sm:text-3xl']">
                          {{ FACTION_NAMES[selectedFaction] }}
                        </h2>
                        <p class="mt-1 text-sm italic text-theme-text-muted">"{{ factionData[selectedFaction].mission }}"</p>
                      </div>
                    </div>
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="chip text-xs">
                        {{ factionData[selectedFaction].member_count || 0 }} members
                      </span>
                      <div v-if="selectedFaction === playerSect" class="chip status-chip text-xs">Your Faction</div>
                    </div>
                  </div>
                </div>

                <div
                  v-if="factionData[selectedFaction].modifiers && Object.keys(factionData[selectedFaction].modifiers).length > 0"
                  class="faction-section-card"
                >
                  <h3 class="ritual-heading mb-4 text-lg font-bold text-theme-text">Economic Modifiers</h3>
                  <div class="faction-metric-grid">
                    <div
                      v-for="(value, key) in factionData[selectedFaction].modifiers"
                      :key="key"
                      class="faction-metric-card"
                    >
                      <div class="text-xs text-theme-text-muted">{{ getModifierLabel(key) }}</div>
                      <div class="mt-1 text-sm font-semibold" :class="parseFloat(value) >= 1 ? 'text-green-600' : 'text-red-400'">
                        {{ formatModifier(value) }}
                      </div>
                    </div>
                  </div>
                </div>

                <div class="faction-section-card">
                  <h3 class="ritual-heading mb-4 text-lg font-bold text-theme-text">Top Members</h3>
                  <div v-if="(factionData[selectedFaction].top_members || []).length === 0" class="py-6 text-center text-sm text-theme-text-muted">
                    No members yet.
                  </div>
                  <div v-else class="space-y-2">
                    <div
                      v-for="(member, i) in factionData[selectedFaction].top_members"
                      :key="member.id"
                      class="faction-member-row"
                    >
                      <div class="flex items-center gap-3">
                        <span class="faction-member-rank">{{ i + 1 }}</span>
                        <span class="font-medium text-sm text-theme-text">{{ member.username || 'Unknown' }}</span>
                      </div>
                      <span class="chip text-xs">{{ member.karma }} ⚡</span>
                    </div>
                  </div>
                </div>
              </div>

              <div class="space-y-6">
                <div class="faction-section-card">
                  <h3 class="ritual-heading mb-4 text-lg font-bold text-theme-text">Relationships</h3>
                  <div class="faction-relationship-stack">
                    <div class="faction-relationship-card faction-relationship-card--ally">
                      <span class="chip bg-green-500/10 border border-green-500/30 text-green-600 text-xs py-2 px-3">
                        🟢 Ally: {{ FACTION_NAMES[factionData[selectedFaction].ally] }}
                      </span>
                      <span v-if="factionData[selectedFaction].rationale_ally" class="text-xs text-theme-text-muted">— {{ factionData[selectedFaction].rationale_ally }}</span>
                    </div>
                    <div class="faction-relationship-card faction-relationship-card--enemy">
                      <span class="chip bg-red-500/10 border border-red-500/30 text-red-400 text-xs py-2 px-3">
                        🔴 Enemy: {{ FACTION_NAMES[factionData[selectedFaction].enemy] }}
                      </span>
                      <span v-if="factionData[selectedFaction].rationale_enemy" class="text-xs text-theme-text-muted">— {{ factionData[selectedFaction].rationale_enemy }}</span>
                    </div>
                    <div class="faction-relationship-card faction-relationship-card--neutral">
                      <span class="chip bg-yellow-500/10 border border-yellow-500/30 text-yellow-500 text-xs py-2 px-3">
                        🟡 Neutral: {{ FACTION_NAMES[factionData[selectedFaction].neutral] }}
                      </span>
                      <span v-if="factionData[selectedFaction].rationale_neutral" class="text-xs text-theme-text-muted">— {{ factionData[selectedFaction].rationale_neutral }}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="glass-panel glass-panel-soft p-8 text-center">
            <p class="text-sm text-theme-text-muted">Click a faction above to see its details.</p>
          </div>
        </div>
      </div>

      <div v-if="activeTab === 'rankings'">
        <div v-if="leaderboard.loading && leaderboard.rankings.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading rankings...</div>
          <p>Summoning the divine ledger...</p>
        </div>

        <div v-else-if="leaderboard.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="font-semibold text-red-500 mb-2">Failed to load rankings</p>
          <p class="text-sm text-theme-text-muted">{{ leaderboard.error }}</p>
          <button @click="handleRefreshRankings" class="btn-secondary mt-4 px-4 py-2 text-sm">Try Again</button>
        </div>

        <div v-else-if="leaderboard.rankings.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <p class="text-lg font-semibold text-theme-text mb-2">No rankings yet</p>
          <p class="text-sm">The divine ledger is empty. Start praying to earn your place!</p>
        </div>

        <div v-else class="faction-rankings-shell glass-panel glass-panel-soft glass-gloss overflow-hidden">
          <div class="overflow-x-auto">
            <table class="faction-rankings-table w-full">
              <thead>
                <tr class="border-b border-theme-border/50 text-left text-xs font-medium uppercase tracking-wider text-theme-text-muted">
                  <th class="pb-3 pl-4 pr-4 pt-4 w-16">Rank</th>
                  <th class="pb-3 pr-4 pt-4">Name</th>
                  <th class="pb-3 pr-4 pt-4 hidden sm:table-cell">Faith</th>
                  <th class="pb-3 pr-4 pt-4 text-right">Karma</th>
                  <th class="pb-3 pr-4 pt-4 text-right">Mana</th>
                  <th class="pb-3 pr-4 pt-4 text-right hidden md:table-cell">Gold</th>
                  <th class="pb-3 pr-4 pt-4 text-right hidden md:table-cell">Food</th>
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
        </div>

        <div v-if="currentUserRank" class="glass-panel glass-panel-soft glass-gloss mt-6 p-4 text-center">
          <p class="text-sm text-theme-text-muted">
            Your position: <span class="font-semibold text-theme-accent">Rank #{{ currentUserRank }}</span>
          </p>
        </div>

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
  fetchFactions,
  autoSelectPlayerFaction,
} = factions

const activeTab = ref('overview')
const currentUserId = ref(null)

const currentUserRank = computed(() => {
  if (!currentUserId.value) return null
  return leaderboard.getUserRank(currentUserId.value)
})

const fallbackFactionOrder = ['gilded_path', 'holy_way', 'final_watch', 'black_tribunal']

const focusFactionKey = computed(() => {
  if (selectedFaction.value && factionData.value[selectedFaction.value]) return selectedFaction.value
  if (playerSect.value && factionData.value[playerSect.value]) return playerSect.value
  return fallbackFactionOrder.find(key => factionData.value[key]) || fallbackFactionOrder[0]
})

const displayPositions = computed(() => {
  const focus = focusFactionKey.value
  const data = factionData.value

  if (focus && data[focus]) {
    const faction = data[focus]
    return [
      { slot: 'top', key: focus, data: faction },
      { slot: 'right', key: faction.ally, data: data[faction.ally] || null },
      { slot: 'bottom', key: faction.enemy, data: data[faction.enemy] || null },
      { slot: 'left', key: faction.neutral, data: data[faction.neutral] || null },
    ]
  }

  return fallbackFactionOrder.map((key, index) => ({
    slot: ['top', 'right', 'bottom', 'left'][index],
    key,
    data: data[key] || null,
  }))
})

const mapLineStyles = computed(() => {
  const focus = focusFactionKey.value
  const data = factionData.value

  if (!focus || !data[focus]) {
    return {
      topBottom: { color: '#ef4444', opacity: 0.85 },
      topRight: { color: '#22c55e', opacity: 0.85 },
      topLeft: { color: '#eab308', opacity: 0.4 },
      cross: { color: '#4a4a5a', opacity: 0.06 },
    }
  }

  return {
    topBottom: { color: '#ef4444', opacity: 0.85 },
    topRight: { color: '#22c55e', opacity: 0.85 },
    topLeft: { color: '#eab308', opacity: 0.4 },
    cross: { color: '#4a4a5a', opacity: 0.06 },
  }
})

function isCurrentUser(playerId) {
  return currentUserId.value && playerId === currentUserId.value
}

function selectFaction(factionKey) {
  selectedFaction.value = factionKey
}

function formatNumber(num) {
  if (num === null || num === undefined) return '0'
  return num.toLocaleString()
}

async function handleRefreshRankings() {
  await leaderboard.fetchLeaderboard()
}

onMounted(async () => {
  const { data: { user } } = await auth.session
    ? { data: { user: auth.user } }
    : import('@/lib/supabase').then(m => m.supabase.auth.getUser())
  if (user) {
    currentUserId.value = user.id
  }

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

.factions-stage {
  position: relative;
}

.factions-stage-grid {
  display: grid;
  gap: 1.35rem;
  align-items: center;
}

.factions-roster {
  display: grid;
  gap: 0.7rem;
  align-content: start;
}

.faction-roster-card {
  display: flex;
  align-items: center;
  gap: 0.8rem;
  width: 100%;
  padding: 0.72rem 0.85rem;
  border-radius: 999px;
  border: 1px solid rgba(73, 60, 98, 0.22);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.08), rgba(255, 255, 255, 0) 42%),
    linear-gradient(180deg, rgba(27, 21, 39, 0.94), rgba(17, 13, 26, 0.96));
  box-shadow: 0 16px 30px rgba(15, 11, 22, 0.28), inset 0 1px 0 rgba(255, 255, 255, 0.08);
  text-align: left;
  transition:
    transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    border-color 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    box-shadow 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    background 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-roster-card:hover {
  transform: translateY(-2px);
  border-color: rgba(177, 128, 255, 0.28);
  box-shadow: 0 20px 34px rgba(15, 11, 22, 0.32), 0 0 22px rgba(177, 128, 255, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.12);
}

.faction-roster-card--selected {
  border-color: rgba(255, 223, 147, 0.26);
  background:
    linear-gradient(180deg, rgba(255, 223, 147, 0.18), rgba(255, 255, 255, 0) 38%),
    linear-gradient(180deg, rgba(31, 23, 44, 0.96), rgba(17, 12, 27, 0.98));
  box-shadow: 0 22px 38px rgba(15, 11, 22, 0.34), 0 0 30px rgba(255, 223, 147, 0.12), inset 0 1px 0 rgba(255, 255, 255, 0.14);
}

.faction-roster-card--player {
  border-color: rgba(255, 223, 147, 0.18);
}

.faction-roster-orb {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.75rem;
  height: 2.75rem;
  flex: 0 0 2.75rem;
  border-radius: 999px;
  border: 1px solid rgba(177, 128, 255, 0.18);
  background:
    radial-gradient(circle at 35% 30%, rgba(255, 255, 255, 0.18), rgba(255, 255, 255, 0.04) 42%, rgba(177, 128, 255, 0.16) 100%),
    linear-gradient(180deg, rgba(30, 22, 43, 0.98), rgba(18, 13, 28, 0.98));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.14), 0 10px 20px rgba(4, 2, 10, 0.22);
}

.faction-diamond-wrapper {
  max-width: 540px;
  margin: 0 auto;
  width: 100%;
}

.faction-diamond-shell {
  position: relative;
  padding: clamp(0.8rem, 2.4vw, 1.2rem);
  border-radius: 36px;
  background:
    radial-gradient(circle at 50% 50%, rgba(177, 128, 255, 0.12), transparent 46%),
    linear-gradient(180deg, rgba(31, 23, 44, 0.96), rgba(14, 10, 22, 0.98));
  border: 1px solid rgba(73, 60, 98, 0.22);
  box-shadow: 0 28px 48px rgba(10, 8, 16, 0.28), inset 0 1px 0 rgba(255, 255, 255, 0.08);
  overflow: hidden;
}

.faction-diamond-aura {
  position: absolute;
  inset: 16% 18%;
  border-radius: 50%;
  background:
    radial-gradient(circle, rgba(177, 128, 255, 0.24) 0%, rgba(177, 128, 255, 0.08) 36%, transparent 66%);
  filter: blur(26px);
  pointer-events: none;
}

.faction-diamond {
  position: relative;
  width: 100%;
  aspect-ratio: 1;
}

.faction-core-seal {
  position: absolute;
  inset: 50% auto auto 50%;
  transform: translate(-50%, -50%);
  z-index: 2;
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  gap: 0.55rem;
  pointer-events: none;
}

.faction-core-seal-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: clamp(3.4rem, 7.5vw, 4.5rem);
  height: clamp(3.4rem, 7.5vw, 4.5rem);
  border-radius: 999px;
  border: 1px solid rgba(177, 128, 255, 0.22);
  background:
    radial-gradient(circle at 35% 30%, rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.04) 44%, rgba(177, 128, 255, 0.16) 100%),
    linear-gradient(180deg, rgba(33, 24, 47, 0.96), rgba(18, 13, 28, 0.98));
  box-shadow: 0 20px 34px rgba(4, 2, 10, 0.26), 0 0 30px rgba(177, 128, 255, 0.14), inset 0 1px 0 rgba(255, 255, 255, 0.14);
  font-size: clamp(1.45rem, 2.7vw, 1.85rem);
}

.relationship-svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 0;
  filter: drop-shadow(0 10px 16px rgba(48, 38, 21, 0.1));
}

.faction-node {
  position: absolute;
  width: 29%;
  transform: translate(-50%, -50%);
  z-index: 1;
  transition:
    top 320ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    left 320ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-node:hover {
  transform: translate(-50%, -50%) scale(1.05);
  z-index: 3;
}

.faction-node--top {
  top: 14%;
  left: 50%;
}

.faction-node--right {
  top: 50%;
  left: 86%;
}

.faction-node--bottom {
  top: 86%;
  left: 50%;
}

.faction-node--left {
  top: 50%;
  left: 14%;
}

.faction-node-card {
  position: relative;
  min-height: 6.15rem;
  overflow: hidden;
  border-radius: 999px;
  border: 1px solid rgba(73, 60, 98, 0.28);
  background:
    radial-gradient(circle at 50% 18%, rgba(255, 255, 255, 0.14), rgba(255, 255, 255, 0) 52%),
    linear-gradient(180deg, rgba(29, 22, 41, 0.97), rgba(16, 12, 25, 0.98));
  box-shadow: 0 18px 30px rgba(5, 3, 12, 0.28), inset 0 1px 0 rgba(255, 255, 255, 0.1);
  transition:
    transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    box-shadow 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    border-color 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-node-card::before {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(145deg, rgba(255, 255, 255, 0.1), transparent 36%, transparent 74%, rgba(177, 128, 255, 0.14));
  opacity: 0.92;
  pointer-events: none;
}

.faction-node-card--selected {
  transform: translateY(-2px) scale(1.02);
  box-shadow: 0 22px 36px rgba(5, 3, 12, 0.34), 0 0 28px rgba(177, 128, 255, 0.12), inset 0 1px 0 rgba(255, 255, 255, 0.14);
}

.faction-node-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.35rem;
  height: 2.35rem;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.08);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.14);
}

.relationship-legend {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 0.85rem;
  margin-top: clamp(1rem, 2.6vw, 1.5rem);
}

.relationship-legend-item {
  display: inline-flex;
  align-items: center;
  gap: 0.55rem;
  padding: 0.55rem 0.85rem;
  border-radius: 999px;
  border: 1px solid rgba(213, 154, 23, 0.12);
  background: rgba(255, 251, 243, 0.56);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.68);
  font-size: 0.74rem;
  color: var(--theme-text-muted);
}

.faction-detail {
  animation: detail-rise 320ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-detail-grid {
  display: grid;
  gap: 1.5rem;
}

.faction-detail-header {
  position: relative;
  padding: 1.15rem 1.2rem;
  border-radius: 24px;
  border: 1px solid rgba(213, 154, 23, 0.14);
  background:
    radial-gradient(circle at top right, rgba(255, 223, 147, 0.18), transparent 32%),
    linear-gradient(180deg, rgba(255, 255, 255, 0.22), rgba(255, 255, 255, 0) 28%),
    rgba(255, 251, 243, 0.44);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.72);
}

.faction-detail-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 4rem;
  height: 4rem;
  border-radius: 22px;
  background: linear-gradient(180deg, rgba(255, 250, 233, 0.92), rgba(255, 243, 220, 0.7));
  box-shadow: 0 16px 28px rgba(48, 38, 21, 0.1), inset 0 1px 0 rgba(255, 255, 255, 0.76);
}

.faction-section-card {
  padding: 1.15rem;
  border-radius: 24px;
  border: 1px solid rgba(139, 125, 91, 0.12);
  background: rgba(255, 251, 243, 0.38);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.66);
}

.faction-metric-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.85rem;
}

.faction-metric-card {
  padding: 0.9rem 0.95rem;
  border-radius: 18px;
  border: 1px solid rgba(139, 125, 91, 0.12);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.22), rgba(255, 255, 255, 0) 34%),
    rgba(255, 250, 241, 0.58);
  box-shadow: 0 12px 24px rgba(48, 38, 21, 0.06), inset 0 1px 0 rgba(255, 255, 255, 0.66);
}

.faction-relationship-stack {
  display: grid;
  gap: 0.9rem;
}

.faction-relationship-card {
  display: grid;
  gap: 0.55rem;
  padding: 1rem;
  border-radius: 20px;
  border: 1px solid rgba(139, 125, 91, 0.12);
  background: rgba(255, 251, 243, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.64);
}

.faction-relationship-card--ally {
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.64), 0 10px 24px rgba(34, 197, 94, 0.08);
}

.faction-relationship-card--enemy {
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.64), 0 10px 24px rgba(239, 68, 68, 0.08);
}

.faction-relationship-card--neutral {
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.64), 0 10px 24px rgba(234, 179, 8, 0.08);
}

.faction-member-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.8rem;
  padding: 0.8rem 0.95rem;
  border-radius: 18px;
  border: 1px solid rgba(139, 125, 91, 0.12);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.18), rgba(255, 255, 255, 0) 34%),
    rgba(255, 250, 241, 0.54);
  box-shadow: 0 12px 24px rgba(48, 38, 21, 0.06), inset 0 1px 0 rgba(255, 255, 255, 0.66);
}

.faction-member-rank {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  border-radius: 999px;
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--theme-accent-dark);
  background: linear-gradient(180deg, rgba(255, 250, 230, 0.94), rgba(248, 229, 185, 0.86));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), 0 8px 16px rgba(213, 154, 23, 0.12);
}

.faction-rankings-shell {
  border-radius: 28px;
}

.faction-rankings-table thead th {
  background: rgba(255, 251, 243, 0.22);
}

.faction-rankings-table tbody tr:last-child {
  border-bottom: none;
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

@media (min-width: 960px) {
  .factions-stage-grid {
    grid-template-columns: minmax(15.5rem, 18.5rem) minmax(0, 1fr);
  }

  .faction-detail-grid {
    grid-template-columns: minmax(0, 1.45fr) minmax(18rem, 0.85fr);
    align-items: start;
  }
}

@media (max-width: 640px) {
  .faction-diamond-wrapper {
    max-width: 320px;
  }

  .faction-diamond-shell {
    padding: 0.7rem;
    border-radius: 28px;
  }

  .faction-node {
    width: 34%;
  }

  .faction-node--top {
    top: 14%;
  }

  .faction-node--bottom {
    top: 86%;
  }

  .faction-node--left {
    left: 14%;
  }

  .faction-node--right {
    left: 86%;
  }

  .faction-node-card {
    min-height: 5.35rem;
    padding-inline: 0.45rem;
  }

  .faction-node-icon {
    width: 2.15rem;
    height: 2.15rem;
  }

  .faction-detail-header,
  .faction-section-card {
    padding: 1rem;
  }

  .faction-metric-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .nav-tab-active,
  .nav-tab-inactive {
    min-width: 0;
    width: 100%;
  }
}

@media (max-width: 420px) {
  .faction-roster-card {
    gap: 0.7rem;
    padding-inline: 0.8rem;
  }

  .faction-roster-orb {
    width: 2.45rem;
    height: 2.45rem;
    flex-basis: 2.45rem;
  }

  .faction-member-row {
    padding-inline: 0.8rem;
  }
}
</style>
