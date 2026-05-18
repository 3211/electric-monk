<template>
  <div class="factions-view min-h-screen">
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
        <div v-if="loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">🏛️</div>
          <p class="text-theme-text-dim">Consulting the archives...</p>
        </div>

        <div v-else-if="error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="text-theme-purgatory-dark">{{ error }}</p>
          <button @click="fetchFactions()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
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

            <div class="relationship-legend steel-legend">
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
import { ref, computed, onMounted, toRefs } from 'vue'
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
} = toRefs(factions)
const { fetchFactions, autoSelectPlayerFaction } = factions

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
.factions-view {
  --faction-steel-plate: rgba(189, 198, 209, 0.74);
  --faction-steel-face: rgba(232, 237, 242, 0.92);
  --faction-steel-mist: rgba(214, 221, 229, 0.46);
  --faction-steel-edge: rgba(94, 111, 128, 0.26);
  --faction-steel-shadow: rgba(41, 51, 63, 0.16);
  --faction-steel-shadow-strong: rgba(34, 42, 52, 0.22);
  --faction-steel-ink: #25313d;
  --faction-steel-muted: #627182;
  --faction-steel-highlight: rgba(255, 255, 255, 0.72);
  --faction-steel-burnished: #a9824d;
  --faction-steel-burnished-soft: rgba(169, 130, 77, 0.18);
  --faction-steel-ally: #5a7f76;
  --faction-steel-enemy: #8f5a55;
  --faction-steel-neutral: #8a8466;
}

.nav-tab-active,
.nav-tab-inactive {
  @apply pill-tab;
  min-width: 10rem;
  border: 1px solid var(--faction-steel-edge);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.42), 0 12px 24px rgba(44, 54, 65, 0.08);
}

.nav-tab-active {
  @apply pill-tab-active;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.72), rgba(255, 255, 255, 0.18) 34%, rgba(255, 255, 255, 0.08) 100%),
    linear-gradient(135deg, rgba(197, 205, 214, 0.94), rgba(163, 175, 187, 0.92));
  color: var(--faction-steel-ink);
}

.nav-tab-inactive {
  @apply pill-tab-inactive;
  background: linear-gradient(180deg, rgba(244, 247, 250, 0.78), rgba(220, 227, 234, 0.72));
  color: var(--faction-steel-muted);
}

.factions-stage {
  position: relative;
  border: 1px solid var(--faction-steel-edge);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.52), rgba(255, 255, 255, 0.2) 28%, rgba(255, 255, 255, 0.1) 100%),
    linear-gradient(135deg, rgba(228, 234, 240, 0.94), rgba(205, 214, 223, 0.92) 55%, rgba(191, 200, 211, 0.9));
  box-shadow:
    0 24px 44px rgba(43, 54, 67, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.78),
    inset 0 -1px 0 rgba(87, 104, 120, 0.08);
}

.factions-stage::before {
  content: "";
  position: absolute;
  inset: 1px;
  border-radius: inherit;
  background:
    linear-gradient(115deg, rgba(255, 255, 255, 0.3), transparent 28%, transparent 68%, rgba(110, 124, 139, 0.08) 100%),
    repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.04) 0 2px, transparent 2px 12px);
  pointer-events: none;
  mix-blend-mode: soft-light;
}

.factions-stage-grid {
  position: relative;
  display: grid;
  gap: 1.5rem;
  align-items: center;
}

.factions-roster {
  display: grid;
  gap: 0.85rem;
  align-content: start;
}

.faction-roster-card {
  display: flex;
  align-items: center;
  gap: 0.8rem;
  width: 100%;
  padding: 0.8rem 0.95rem;
  border-radius: 1.6rem;
  border: 1px solid var(--faction-steel-edge);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.78), rgba(255, 255, 255, 0.16) 36%, rgba(255, 255, 255, 0.04) 100%),
    linear-gradient(135deg, rgba(230, 235, 240, 0.96), rgba(204, 212, 220, 0.94) 58%, rgba(186, 195, 205, 0.92));
  box-shadow:
    0 16px 28px rgba(43, 53, 64, 0.11),
    inset 0 1px 0 rgba(255, 255, 255, 0.76),
    inset 0 -1px 0 rgba(84, 101, 119, 0.08);
  text-align: left;
  transition:
    transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    border-color 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    box-shadow 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    background 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-roster-card:hover {
  transform: translateY(-3px);
  border-color: rgba(121, 137, 153, 0.38);
  box-shadow:
    0 20px 34px rgba(40, 50, 61, 0.15),
    0 0 0 1px rgba(255, 255, 255, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.84);
}

.faction-roster-card--selected {
  border-color: rgba(132, 109, 78, 0.34);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.86), rgba(255, 255, 255, 0.18) 34%, rgba(255, 255, 255, 0.06) 100%),
    linear-gradient(135deg, rgba(214, 208, 201, 0.98), rgba(189, 194, 200, 0.96) 52%, rgba(170, 178, 186, 0.94));
  box-shadow:
    0 22px 36px rgba(40, 48, 58, 0.16),
    0 0 0 1px rgba(169, 130, 77, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.9);
}

.faction-roster-card--player {
  border-color: rgba(128, 103, 69, 0.28);
}

.faction-roster-orb {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.75rem;
  height: 2.75rem;
  flex: 0 0 2.75rem;
  border-radius: 1rem;
  border: 1px solid rgba(103, 118, 133, 0.28);
  background:
    radial-gradient(circle at 32% 28%, rgba(255, 255, 255, 0.9), rgba(255, 255, 255, 0.28) 34%, rgba(255, 255, 255, 0) 62%),
    linear-gradient(135deg, rgba(242, 245, 248, 0.98), rgba(211, 219, 226, 0.94) 54%, rgba(178, 188, 198, 0.96));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.84),
    inset 0 -1px 0 rgba(90, 105, 121, 0.12),
    0 10px 18px rgba(41, 50, 60, 0.12);
}

.faction-diamond-wrapper {
  max-width: 560px;
  margin: 0 auto;
  width: 100%;
}

.faction-diamond-shell {
  position: relative;
  padding: clamp(0.9rem, 2.5vw, 1.35rem);
  border-radius: 2.25rem;
  background:
    radial-gradient(circle at 50% 45%, rgba(255, 255, 255, 0.48), transparent 34%),
    linear-gradient(145deg, rgba(228, 234, 239, 0.97), rgba(201, 210, 219, 0.95) 55%, rgba(183, 192, 202, 0.94));
  border: 1px solid rgba(100, 115, 131, 0.24);
  box-shadow:
    0 30px 52px rgba(42, 51, 62, 0.14),
    inset 0 1px 0 rgba(255, 255, 255, 0.82),
    inset 0 -1px 0 rgba(80, 97, 114, 0.1);
  overflow: hidden;
}

.faction-diamond-shell::after {
  content: "";
  position: absolute;
  inset: 0;
  background:
    linear-gradient(120deg, rgba(255, 255, 255, 0.22) 0%, transparent 22%, transparent 74%, rgba(107, 123, 140, 0.08) 100%),
    repeating-linear-gradient(45deg, rgba(255, 255, 255, 0.025) 0 2px, transparent 2px 12px);
  pointer-events: none;
}

.faction-diamond-aura {
  position: absolute;
  inset: 14% 16%;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(122, 138, 154, 0.24) 0%, rgba(160, 170, 181, 0.12) 38%, transparent 70%);
  filter: blur(28px);
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
  width: clamp(3.65rem, 7.7vw, 4.7rem);
  height: clamp(3.65rem, 7.7vw, 4.7rem);
  border-radius: 1.4rem;
  border: 1px solid rgba(102, 118, 133, 0.26);
  background:
    radial-gradient(circle at 30% 24%, rgba(255, 255, 255, 0.94), rgba(255, 255, 255, 0.3) 36%, rgba(255, 255, 255, 0) 62%),
    linear-gradient(145deg, rgba(241, 245, 248, 0.98), rgba(214, 221, 228, 0.96) 56%, rgba(186, 195, 204, 0.96));
  box-shadow:
    0 20px 36px rgba(41, 49, 60, 0.15),
    0 0 0 1px rgba(255, 255, 255, 0.38),
    inset 0 1px 0 rgba(255, 255, 255, 0.88),
    inset 0 -1px 0 rgba(92, 107, 122, 0.12);
  font-size: clamp(1.45rem, 2.7vw, 1.85rem);
}

.relationship-svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 0;
  filter: drop-shadow(0 8px 12px rgba(73, 84, 97, 0.14));
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
  min-height: 6.3rem;
  overflow: hidden;
  border-radius: 1.6rem;
  border: 1px solid rgba(102, 117, 131, 0.24);
  background:
    radial-gradient(circle at 50% 14%, rgba(255, 255, 255, 0.68), rgba(255, 255, 255, 0.12) 40%, rgba(255, 255, 255, 0) 68%),
    linear-gradient(145deg, rgba(233, 238, 243, 0.98), rgba(207, 215, 223, 0.95) 58%, rgba(184, 194, 203, 0.94));
  box-shadow:
    0 18px 30px rgba(41, 50, 60, 0.14),
    inset 0 1px 0 rgba(255, 255, 255, 0.82),
    inset 0 -1px 0 rgba(88, 103, 118, 0.1);
  transition:
    transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    box-shadow 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    border-color 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-node-card::before {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(135deg, rgba(255, 255, 255, 0.2), transparent 34%, transparent 72%, rgba(84, 101, 118, 0.08));
  opacity: 0.95;
  pointer-events: none;
}

.faction-node-card--selected {
  transform: translateY(-3px) scale(1.02);
  border-color: rgba(125, 101, 70, 0.3);
  box-shadow:
    0 24px 38px rgba(39, 48, 57, 0.18),
    0 0 0 1px rgba(169, 130, 77, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.9);
}

.faction-node-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.45rem;
  height: 2.45rem;
  border-radius: 0.9rem;
  background: rgba(255, 255, 255, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.74), inset 0 -1px 0 rgba(95, 109, 123, 0.08);
}

.relationship-legend {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 0.85rem;
  margin-top: clamp(1.15rem, 2.6vw, 1.7rem);
}

.relationship-legend-item {
  display: inline-flex;
  align-items: center;
  gap: 0.55rem;
  padding: 0.62rem 0.95rem;
  border-radius: 999px;
  border: 1px solid rgba(101, 117, 132, 0.18);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.78), rgba(229, 235, 241, 0.78)),
    rgba(215, 223, 231, 0.46);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.84), 0 10px 20px rgba(43, 53, 63, 0.08);
  font-size: 0.74rem;
  color: var(--faction-steel-muted);
}

.steel-legend .relationship-legend-item:nth-child(1) {
  border-color: color-mix(in srgb, var(--faction-steel-ally) 24%, white);
}

.steel-legend .relationship-legend-item:nth-child(2) {
  border-color: color-mix(in srgb, var(--faction-steel-enemy) 24%, white);
}

.steel-legend .relationship-legend-item:nth-child(3) {
  border-color: color-mix(in srgb, var(--faction-steel-neutral) 24%, white);
}

.faction-detail {
  animation: detail-rise 320ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
  border: 1px solid var(--faction-steel-edge);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.56), rgba(255, 255, 255, 0.2) 24%, rgba(255, 255, 255, 0.12) 100%),
    linear-gradient(145deg, rgba(229, 235, 240, 0.94), rgba(207, 215, 223, 0.92) 58%, rgba(191, 200, 211, 0.9));
  box-shadow:
    0 22px 40px rgba(43, 53, 64, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.8),
    inset 0 -1px 0 rgba(83, 99, 114, 0.08);
}

.faction-detail-grid {
  display: grid;
  gap: 1.5rem;
}

.faction-detail-header {
  position: relative;
  padding: 1.2rem 1.25rem;
  border-radius: 1.75rem;
  border: 1px solid rgba(107, 122, 137, 0.2);
  background:
    radial-gradient(circle at top right, rgba(255, 255, 255, 0.44), transparent 34%),
    linear-gradient(180deg, rgba(255, 255, 255, 0.78), rgba(255, 255, 255, 0.18) 32%, rgba(255, 255, 255, 0.08) 100%),
    linear-gradient(135deg, rgba(232, 237, 242, 0.96), rgba(211, 218, 226, 0.94) 56%, rgba(192, 201, 210, 0.92));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.88),
    inset 0 -1px 0 rgba(85, 101, 116, 0.08),
    0 16px 28px rgba(43, 53, 64, 0.08);
}

.faction-detail-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 4rem;
  height: 4rem;
  border-radius: 1.3rem;
  border: 1px solid rgba(107, 121, 135, 0.22);
  background:
    radial-gradient(circle at 30% 25%, rgba(255, 255, 255, 0.96), rgba(255, 255, 255, 0.3) 34%, rgba(255, 255, 255, 0) 62%),
    linear-gradient(145deg, rgba(243, 246, 248, 0.98), rgba(214, 221, 227, 0.95) 56%, rgba(189, 198, 208, 0.94));
  box-shadow:
    0 16px 28px rgba(42, 50, 59, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.88),
    inset 0 -1px 0 rgba(83, 99, 114, 0.1);
}

.faction-section-card {
  padding: 1.15rem;
  border-radius: 1.5rem;
  border: 1px solid rgba(106, 121, 136, 0.18);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.72), rgba(255, 255, 255, 0.2) 36%, rgba(255, 255, 255, 0.08) 100%),
    linear-gradient(135deg, rgba(233, 238, 243, 0.88), rgba(214, 221, 228, 0.82) 62%, rgba(198, 206, 214, 0.8));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.82),
    inset 0 -1px 0 rgba(83, 100, 115, 0.06),
    0 14px 26px rgba(42, 51, 61, 0.08);
}

.faction-metric-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.85rem;
}

.faction-metric-card {
  padding: 0.95rem 1rem;
  border-radius: 1.2rem;
  border: 1px solid rgba(106, 121, 136, 0.16);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.76), rgba(255, 255, 255, 0.12) 42%, rgba(255, 255, 255, 0.04) 100%),
    linear-gradient(135deg, rgba(236, 240, 244, 0.96), rgba(218, 224, 230, 0.9) 58%, rgba(201, 209, 216, 0.88));
  box-shadow: 0 12px 22px rgba(42, 50, 60, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.82);
}

.faction-relationship-stack {
  display: grid;
  gap: 0.9rem;
}

.faction-relationship-card {
  display: grid;
  gap: 0.55rem;
  padding: 1rem;
  border-radius: 1.3rem;
  border: 1px solid rgba(106, 121, 136, 0.18);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.72), rgba(255, 255, 255, 0.18) 36%, rgba(255, 255, 255, 0.08) 100%),
    linear-gradient(135deg, rgba(233, 238, 243, 0.84), rgba(214, 221, 228, 0.78) 58%, rgba(196, 204, 212, 0.76));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.82), 0 12px 22px rgba(42, 50, 60, 0.08);
}

.faction-relationship-card--ally {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.82),
    0 14px 26px color-mix(in srgb, var(--faction-steel-ally) 18%, transparent);
}

.faction-relationship-card--enemy {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.82),
    0 14px 26px color-mix(in srgb, var(--faction-steel-enemy) 18%, transparent);
}

.faction-relationship-card--neutral {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.82),
    0 14px 26px color-mix(in srgb, var(--faction-steel-neutral) 16%, transparent);
}

.faction-member-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.8rem;
  padding: 0.85rem 1rem;
  border-radius: 1.15rem;
  border: 1px solid rgba(106, 121, 136, 0.16);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.72), rgba(255, 255, 255, 0.14) 40%, rgba(255, 255, 255, 0.04) 100%),
    linear-gradient(135deg, rgba(236, 240, 244, 0.92), rgba(217, 223, 229, 0.84) 58%, rgba(199, 207, 214, 0.82));
  box-shadow: 0 12px 22px rgba(42, 50, 60, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.82);
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
  color: #4f402a;
  background:
    radial-gradient(circle at 30% 28%, rgba(255, 255, 255, 0.95), rgba(255, 255, 255, 0.24) 36%, rgba(255, 255, 255, 0) 62%),
    linear-gradient(145deg, rgba(223, 203, 175, 0.98), rgba(185, 157, 118, 0.9));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.86), 0 10px 18px rgba(133, 103, 62, 0.14);
}

.faction-rankings-shell {
  border-radius: 1.75rem;
  border: 1px solid rgba(105, 120, 135, 0.18);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.5), rgba(255, 255, 255, 0.18) 28%, rgba(255, 255, 255, 0.08) 100%),
    linear-gradient(135deg, rgba(229, 235, 240, 0.9), rgba(209, 216, 224, 0.86) 58%, rgba(193, 201, 210, 0.84));
  box-shadow: 0 20px 34px rgba(42, 51, 61, 0.1), inset 0 1px 0 rgba(255, 255, 255, 0.82);
}

.faction-rankings-table thead th {
  background: rgba(255, 255, 255, 0.34);
  color: var(--faction-steel-muted);
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
  background: radial-gradient(circle, rgba(190, 202, 214, 0.34) 0%, rgba(177, 188, 198, 0.14) 42%, transparent 74%);
  filter: blur(14px);
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
