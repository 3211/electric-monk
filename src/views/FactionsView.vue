<template>
  <div class="factions-view min-h-screen">
    <header class="factions-war-header border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="relative min-w-0">
            <div class="merged-header-glow" aria-hidden="true"></div>
            <h1 class="faction-page-title ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">🏛️ The Four Factions</h1>
            <p class="faction-page-subtitle relative mt-1 text-sm text-theme-text-muted">Know thy allies. Fear thy enemies.</p>
          </div>
          <div v-if="playerSect && factionData[playerSect]" class="flex items-center gap-3">
            <div class="chip status-chip faction-player-indicator gap-2 px-4 py-2 text-sm">
              <span class="text-lg">{{ FACTION_ICONS[playerSect] }}</span>
              <span>{{ FACTION_NAMES[playerSect] }}</span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="factions-war-main app-frame py-8 lg:py-10">
      <div class="mb-8 flex justify-center">
        <div class="segmented-shell faction-tab-shell">
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
        <div v-if="loading" class="glass-panel glass-panel-soft faction-state-card p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">🏛️</div>
          <p class="text-theme-text-dim">Consulting the archives...</p>
        </div>

        <div v-else-if="error" class="glass-panel faction-state-card faction-state-card--error p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="text-theme-purgatory-dark">{{ error }}</p>
          <button @click="fetchFactions()" class="btn-secondary faction-action-button mt-4 px-6 py-2">Try Again</button>
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
                        stroke="#55616d"
                        stroke-width="1"
                        :stroke-opacity="mapLineStyles.cross.opacity"
                        stroke-dasharray="4 8"
                      />
                      <line
                        x1="200"
                        y1="360"
                        x2="40"
                        y2="200"
                        stroke="#55616d"
                        stroke-width="1"
                        :stroke-opacity="mapLineStyles.cross.opacity"
                        stroke-dasharray="4 8"
                      />
                      <line
                        x1="40"
                        y1="200"
                        x2="360"
                        y2="200"
                        stroke="#55616d"
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
                          pos.key === playerSect ? 'faction-node-card--player' : '',
                          selectedFaction === pos.key ? 'faction-node-card--selected' : '',
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
                <span class="inline-block h-0.5 w-5 rounded" style="background: #6c8c83;"></span> Ally
              </span>
              <span class="relationship-legend-item">
                <span class="inline-block h-0.5 w-5 rounded" style="background: #9b6b66;"></span> Enemy
              </span>
              <span class="relationship-legend-item">
                <span class="inline-block h-0.5 w-5 rounded" style="background: #8b856d; opacity: 0.65;"></span> Neutral
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
                      <span class="chip faction-relation-badge faction-relation-badge--ally text-xs py-2 px-3">
                        🟢 Ally: {{ FACTION_NAMES[factionData[selectedFaction].ally] }}
                      </span>
                      <span v-if="factionData[selectedFaction].rationale_ally" class="text-xs text-theme-text-muted">— {{ factionData[selectedFaction].rationale_ally }}</span>
                    </div>
                    <div class="faction-relationship-card faction-relationship-card--enemy">
                      <span class="chip faction-relation-badge faction-relation-badge--enemy text-xs py-2 px-3">
                        🔴 Enemy: {{ FACTION_NAMES[factionData[selectedFaction].enemy] }}
                      </span>
                      <span v-if="factionData[selectedFaction].rationale_enemy" class="text-xs text-theme-text-muted">— {{ factionData[selectedFaction].rationale_enemy }}</span>
                    </div>
                    <div class="faction-relationship-card faction-relationship-card--neutral">
                      <span class="chip faction-relation-badge faction-relation-badge--neutral text-xs py-2 px-3">
                        🟡 Neutral: {{ FACTION_NAMES[factionData[selectedFaction].neutral] }}
                      </span>
                      <span v-if="factionData[selectedFaction].rationale_neutral" class="text-xs text-theme-text-muted">— {{ factionData[selectedFaction].rationale_neutral }}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="glass-panel glass-panel-soft faction-state-card p-8 text-center">
            <p class="text-sm text-theme-text-muted">Click a faction above to see its details.</p>
          </div>
        </div>
      </div>

      <div v-if="activeTab === 'rankings'">
        <div v-if="leaderboard.loading && leaderboard.rankings.length === 0" class="glass-panel glass-panel-soft faction-state-card p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading rankings...</div>
          <p>Summoning the divine ledger...</p>
        </div>

        <div v-else-if="leaderboard.error" class="glass-panel faction-state-card faction-state-card--error p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="font-semibold text-red-500 mb-2">Failed to load rankings</p>
          <p class="text-sm text-theme-text-muted">{{ leaderboard.error }}</p>
          <button @click="handleRefreshRankings" class="btn-secondary faction-action-button mt-4 px-4 py-2 text-sm">Try Again</button>
        </div>

        <div v-else-if="leaderboard.rankings.length === 0" class="glass-panel glass-panel-soft faction-state-card p-12 text-center text-theme-text-dim">
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
                  class="faction-rank-row border-b border-theme-border/30 transition-colors duration-200 hover:bg-theme-accent/5"
                  :class="{ 'faction-rank-row--current': isCurrentUser(player.id) }"
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

        <div v-if="currentUserRank" class="glass-panel glass-panel-soft glass-gloss faction-position-card mt-6 p-4 text-center">
          <p class="text-sm text-theme-text-muted">
            Your position: <span class="font-semibold text-theme-accent">Rank #{{ currentUserRank }}</span>
          </p>
        </div>

        <div class="mt-6 flex justify-center">
          <button
            @click="handleRefreshRankings"
            :disabled="leaderboard.loading"
            class="btn-secondary faction-action-button flex items-center gap-2 px-4 py-2 text-sm"
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
import { ref, computed, inject, onMounted, onUnmounted, toRefs } from 'vue'
import { useFactions, FACTION_ICONS, FACTION_NAMES, FACTION_COLORS, formatModifier, getModifierLabel } from '@/composables/useFactions'
import { useLeaderboard } from '@/composables/useLeaderboard'
import { useAuth } from '@/composables/useAuth'

// Activate war theme on the global nav/footer
const forceWarTheme = inject('forceWarTheme')

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
      topBottom: { color: '#9b6b66', opacity: 0.72 },
      topRight: { color: '#6c8c83', opacity: 0.72 },
      topLeft: { color: '#8b856d', opacity: 0.42 },
      cross: { color: '#55616d', opacity: 0.16 },
    }
  }

  return {
    topBottom: { color: '#9b6b66', opacity: 0.72 },
    topRight: { color: '#6c8c83', opacity: 0.72 },
    topLeft: { color: '#8b856d', opacity: 0.42 },
    cross: { color: '#55616d', opacity: 0.16 },
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
  if (forceWarTheme) forceWarTheme.value = true

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

onUnmounted(() => {
  if (forceWarTheme) forceWarTheme.value = false
})
</script>

<style scoped>
.factions-view {
  --war-bg-0: #090c10;
  --war-bg-1: #0f1318;
  --war-bg-2: #141a20;
  --war-bg-3: #1a2128;
  --war-panel: rgba(24, 31, 39, 0.9);
  --war-panel-strong: rgba(18, 24, 31, 0.94);
  --war-panel-soft: rgba(32, 40, 49, 0.78);
  --war-panel-highlight: rgba(255, 255, 255, 0.075);
  --war-panel-shadow: rgba(0, 0, 0, 0.42);
  --war-edge: rgba(164, 176, 189, 0.16);
  --war-edge-strong: rgba(188, 198, 208, 0.22);
  --war-text: #d7e0e8;
  --war-text-soft: #b4c0cc;
  --war-muted: #8291a0;
  --war-dim: #677482;
  --war-steel: #b9c5cf;
  --war-steel-soft: rgba(185, 197, 207, 0.18);
  --war-brass: #b6905b;
  --war-brass-soft: rgba(182, 144, 91, 0.18);
  --war-ally: #6c8c83;
  --war-enemy: #9b6b66;
  --war-neutral: #8b856d;
  position: relative;
  isolation: isolate;
  overflow: hidden;
  color: var(--war-text);
  background:
    linear-gradient(180deg, rgba(7, 9, 12, 0.94), rgba(11, 15, 19, 0.98)),
    linear-gradient(135deg, rgba(15, 19, 24, 0.92), rgba(10, 13, 17, 0.96));
}

.factions-view::before {
  content: "";
  position: absolute;
  inset: 0;
  background:
    linear-gradient(150deg, rgba(255, 255, 255, 0.02) 12%, transparent 12.5%, transparent 87%, rgba(255, 255, 255, 0.02) 87.5%, rgba(255, 255, 255, 0.02)),
    linear-gradient(30deg, rgba(255, 255, 255, 0.012) 12%, transparent 12.5%, transparent 87%, rgba(255, 255, 255, 0.012) 87.5%, rgba(255, 255, 255, 0.012)),
    linear-gradient(90deg, rgba(255, 255, 255, 0.008) 2%, transparent 2%, transparent 98%, rgba(255, 255, 255, 0.008) 98%),
    linear-gradient(180deg, rgba(255, 255, 255, 0.012), rgba(0, 0, 0, 0.18));
  background-size: 48px 84px, 48px 84px, 48px 84px, 100% 100%;
  background-position: 0 0, 24px 42px, 0 0, 0 0;
  opacity: 0.74;
  pointer-events: none;
}

.factions-view::after {
  content: "";
  position: absolute;
  inset: 0;
  background:
    radial-gradient(circle at 18% 0%, rgba(190, 202, 214, 0.08), transparent 28%),
    radial-gradient(circle at 82% 18%, rgba(255, 255, 255, 0.03), transparent 24%),
    linear-gradient(115deg, transparent 18%, rgba(255, 255, 255, 0.03) 31%, transparent 44%),
    linear-gradient(295deg, transparent 56%, rgba(255, 255, 255, 0.016) 67%, transparent 76%);
  mix-blend-mode: screen;
  opacity: 0.7;
  pointer-events: none;
}

.factions-view > * {
  position: relative;
  z-index: 1;
}

.factions-view :is(.text-theme-text, .text-theme-accent) {
  color: var(--war-text) !important;
}

.factions-view :is(.text-theme-text-muted, .text-theme-text-dim) {
  color: var(--war-muted) !important;
}

.factions-view .text-theme-purgatory-dark,
.factions-view .text-red-500,
.factions-view .text-red-400 {
  color: var(--war-enemy) !important;
}

.factions-view .text-green-600 {
  color: var(--war-ally) !important;
}

.factions-view .text-yellow-500,
.factions-view .text-amber-600,
.factions-view .text-amber-700 {
  color: #b49b6b !important;
}

.factions-view .text-blue-500 {
  color: #86a2bc !important;
}

.factions-view .text-emerald-600 {
  color: #7c9a85 !important;
}

.factions-view .surface-divider {
  border-color: rgba(160, 172, 183, 0.12) !important;
}

.factions-war-header {
  position: relative;
  background:
    linear-gradient(180deg, rgba(8, 10, 13, 0.94), rgba(14, 18, 23, 0.96)),
    linear-gradient(135deg, rgba(26, 32, 39, 0.88), rgba(12, 15, 20, 0.9));
  box-shadow:
    0 18px 34px rgba(0, 0, 0, 0.26),
    inset 0 1px 0 rgba(255, 255, 255, 0.05),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03);
}

.factions-war-header::before {
  content: "";
  position: absolute;
  inset: 0;
  background:
    linear-gradient(145deg, rgba(255, 255, 255, 0.04), transparent 24%, transparent 76%, rgba(255, 255, 255, 0.02)),
    repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.015) 0 1px, transparent 1px 14px);
  pointer-events: none;
}

.factions-war-main {
  position: relative;
}

.faction-page-title {
  color: var(--war-steel) !important;
  text-shadow: 0 0 24px rgba(185, 197, 207, 0.08);
}

.faction-page-subtitle {
  color: var(--war-muted) !important;
}

.merged-header-glow {
  position: absolute;
  inset: -1rem auto auto -1rem;
  width: 13rem;
  height: 6rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(187, 198, 209, 0.16) 0%, rgba(135, 147, 159, 0.08) 42%, transparent 74%);
  filter: blur(16px);
  pointer-events: none;
}

.factions-view :is(.glass-panel, .glass-panel-soft, .glass-panel-strong) {
  border: 1px solid var(--war-edge);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.02) 26%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(28, 35, 43, 0.92), rgba(18, 24, 30, 0.96) 56%, rgba(13, 18, 23, 0.98));
  box-shadow:
    0 22px 40px rgba(0, 0, 0, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03);
  color: var(--war-text);
}

.factions-view .glass-gloss {
  backdrop-filter: blur(12px);
}

.factions-view .chip {
  border: 1px solid rgba(172, 183, 194, 0.14);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.08), rgba(255, 255, 255, 0.02) 42%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(42, 50, 59, 0.9), rgba(26, 33, 40, 0.95));
  color: var(--war-text-soft);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    inset 0 -1px 0 rgba(255, 255, 255, 0.02),
    0 8px 18px rgba(0, 0, 0, 0.18);
}

.factions-view .status-chip,
.faction-player-indicator {
  border-color: rgba(182, 144, 91, 0.28);
  background:
    linear-gradient(180deg, rgba(182, 144, 91, 0.16), rgba(255, 255, 255, 0.03) 42%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(53, 45, 34, 0.92), rgba(29, 24, 19, 0.96));
  color: #e9d6b5;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 10px 20px rgba(0, 0, 0, 0.22),
    0 0 0 1px rgba(182, 144, 91, 0.08);
}

.faction-tab-shell.segmented-shell {
  padding: 0.32rem;
  border-radius: 999px;
  border: 1px solid rgba(166, 178, 189, 0.14);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.04), rgba(255, 255, 255, 0.015) 100%),
    linear-gradient(145deg, rgba(22, 28, 34, 0.94), rgba(12, 16, 21, 0.98));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 16px 28px rgba(0, 0, 0, 0.22);
}

.nav-tab-active,
.nav-tab-inactive {
  @apply pill-tab;
  min-width: 10rem;
  border: 1px solid transparent;
  box-shadow: none;
}

.nav-tab-active {
  @apply pill-tab-active;
  border-color: rgba(182, 194, 204, 0.2);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.04) 38%, rgba(255, 255, 255, 0.02) 100%),
    linear-gradient(145deg, rgba(70, 81, 92, 0.92), rgba(35, 43, 51, 0.96));
  color: var(--war-text);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.14),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03),
    0 10px 20px rgba(0, 0, 0, 0.22);
}

.nav-tab-inactive {
  @apply pill-tab-inactive;
  background: transparent;
  color: var(--war-muted);
}

.factions-view .btn-secondary,
.faction-action-button {
  border: 1px solid rgba(173, 184, 194, 0.16);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.08), rgba(255, 255, 255, 0.02) 42%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(45, 54, 63, 0.94), rgba(25, 31, 39, 0.98));
  color: var(--war-text);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03),
    0 14px 24px rgba(0, 0, 0, 0.24);
  transition:
    transform 220ms ease,
    border-color 220ms ease,
    box-shadow 220ms ease,
    background 220ms ease;
}

.factions-view .btn-secondary:hover,
.faction-action-button:hover {
  transform: translateY(-2px);
  border-color: rgba(188, 198, 208, 0.24);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.1),
    0 18px 28px rgba(0, 0, 0, 0.28),
    0 0 0 1px rgba(255, 255, 255, 0.03);
}

.factions-view .btn-secondary:disabled,
.faction-action-button:disabled {
  opacity: 0.6;
  transform: none;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.05);
}

.factions-view .btn-secondary:focus-visible,
.nav-tab-active:focus-visible,
.nav-tab-inactive:focus-visible,
.faction-roster-card:focus-visible {
  outline: 2px solid rgba(185, 197, 207, 0.34);
  outline-offset: 2px;
}

.faction-state-card {
  position: relative;
  overflow: hidden;
}

.faction-state-card::before {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(135deg, rgba(255, 255, 255, 0.05), transparent 30%, transparent 70%, rgba(255, 255, 255, 0.02));
  pointer-events: none;
}

.faction-state-card--error {
  border-color: rgba(155, 107, 102, 0.24) !important;
  background:
    linear-gradient(180deg, rgba(155, 107, 102, 0.09), rgba(255, 255, 255, 0.02) 28%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(36, 24, 24, 0.96), rgba(20, 15, 16, 0.98));
}

.factions-stage {
  position: relative;
  border-color: rgba(172, 183, 194, 0.16);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.02) 22%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(30, 37, 45, 0.96), rgba(19, 24, 30, 0.98) 52%, rgba(12, 16, 21, 0.98));
  box-shadow:
    0 28px 48px rgba(0, 0, 0, 0.34),
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    inset 0 -1px 0 rgba(255, 255, 255, 0.025);
}

.factions-stage::before {
  content: "";
  position: absolute;
  inset: 1px;
  border-radius: inherit;
  background:
    linear-gradient(125deg, rgba(255, 255, 255, 0.035), transparent 22%, transparent 78%, rgba(255, 255, 255, 0.02)),
    repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.012) 0 1px, transparent 1px 12px);
  pointer-events: none;
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
  border-radius: 1.45rem;
  border: 1px solid rgba(167, 179, 190, 0.14);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.08), rgba(255, 255, 255, 0.02) 38%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(39, 47, 56, 0.92), rgba(23, 29, 36, 0.96) 56%, rgba(18, 23, 28, 0.98));
  box-shadow:
    0 16px 26px rgba(0, 0, 0, 0.24),
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    inset 0 -1px 0 rgba(255, 255, 255, 0.02);
  text-align: left;
  transition:
    transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    border-color 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    box-shadow 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-roster-card:hover {
  transform: translateY(-3px);
  border-color: rgba(188, 198, 208, 0.22);
  box-shadow:
    0 20px 32px rgba(0, 0, 0, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 0 0 1px rgba(255, 255, 255, 0.02);
}

.faction-roster-card--selected {
  border-color: rgba(182, 144, 91, 0.24);
  background:
    linear-gradient(180deg, rgba(182, 144, 91, 0.12), rgba(255, 255, 255, 0.025) 36%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(49, 43, 36, 0.94), rgba(28, 25, 22, 0.98) 42%, rgba(23, 24, 26, 0.98));
  box-shadow:
    0 22px 34px rgba(0, 0, 0, 0.3),
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 0 0 1px rgba(182, 144, 91, 0.08);
}

.faction-roster-card--player {
  border-color: rgba(182, 144, 91, 0.2);
}

.faction-roster-orb {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.75rem;
  height: 2.75rem;
  flex: 0 0 2.75rem;
  border-radius: 1rem;
  border: 1px solid rgba(181, 191, 201, 0.16);
  background:
    radial-gradient(circle at 30% 24%, rgba(255, 255, 255, 0.22), rgba(255, 255, 255, 0.02) 40%, rgba(255, 255, 255, 0) 64%),
    linear-gradient(145deg, rgba(68, 79, 90, 0.92), rgba(37, 45, 53, 0.96) 54%, rgba(24, 31, 38, 0.98));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    inset 0 -1px 0 rgba(255, 255, 255, 0.025),
    0 10px 18px rgba(0, 0, 0, 0.22);
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
    radial-gradient(circle at 50% 44%, rgba(181, 191, 201, 0.08), transparent 36%),
    linear-gradient(145deg, rgba(29, 36, 43, 0.98), rgba(18, 24, 30, 0.98) 52%, rgba(11, 15, 20, 1));
  border: 1px solid rgba(169, 180, 190, 0.14);
  box-shadow:
    0 30px 52px rgba(0, 0, 0, 0.36),
    inset 0 1px 0 rgba(255, 255, 255, 0.065),
    inset 0 -1px 0 rgba(255, 255, 255, 0.02);
  overflow: hidden;
}

.faction-diamond-shell::after {
  content: "";
  position: absolute;
  inset: 0;
  background:
    linear-gradient(118deg, rgba(255, 255, 255, 0.04) 0%, transparent 24%, transparent 76%, rgba(255, 255, 255, 0.02) 100%),
    repeating-linear-gradient(45deg, rgba(255, 255, 255, 0.01) 0 1px, transparent 1px 10px);
  pointer-events: none;
}

.faction-diamond-aura {
  position: absolute;
  inset: 14% 16%;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(109, 123, 136, 0.18) 0%, rgba(72, 84, 96, 0.08) 40%, transparent 70%);
  filter: blur(30px);
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
  border: 1px solid rgba(183, 193, 202, 0.18);
  background:
    radial-gradient(circle at 30% 24%, rgba(255, 255, 255, 0.2), rgba(255, 255, 255, 0.025) 38%, rgba(255, 255, 255, 0) 62%),
    linear-gradient(145deg, rgba(75, 86, 97, 0.94), rgba(41, 49, 57, 0.96) 54%, rgba(24, 31, 38, 0.98));
  box-shadow:
    0 20px 36px rgba(0, 0, 0, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.1),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03);
  font-size: clamp(1.45rem, 2.7vw, 1.85rem);
}

.relationship-svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 0;
  filter: drop-shadow(0 8px 12px rgba(0, 0, 0, 0.2));
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
  border-radius: 1.45rem;
  border: 1px solid rgba(171, 182, 192, 0.14);
  background:
    radial-gradient(circle at 50% 12%, rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0.02) 42%, rgba(255, 255, 255, 0) 68%),
    linear-gradient(145deg, rgba(40, 48, 57, 0.95), rgba(23, 29, 36, 0.98) 58%, rgba(16, 21, 27, 1));
  box-shadow:
    0 18px 30px rgba(0, 0, 0, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    inset 0 -1px 0 rgba(255, 255, 255, 0.025);
  transition:
    transform 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    box-shadow 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1)),
    border-color 280ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
}

.faction-node-card::before {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(135deg, rgba(255, 255, 255, 0.05), transparent 34%, transparent 72%, rgba(255, 255, 255, 0.02));
  opacity: 0.95;
  pointer-events: none;
}

.faction-node-card--player {
  border-color: rgba(182, 144, 91, 0.2);
}

.faction-node-card--selected {
  transform: translateY(-3px) scale(1.02);
  border-color: rgba(182, 144, 91, 0.24);
  box-shadow:
    0 24px 38px rgba(0, 0, 0, 0.32),
    inset 0 1px 0 rgba(255, 255, 255, 0.09),
    0 0 0 1px rgba(182, 144, 91, 0.08);
}

.faction-node-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.45rem;
  height: 2.45rem;
  border-radius: 0.9rem;
  background: rgba(255, 255, 255, 0.06);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), inset 0 -1px 0 rgba(255, 255, 255, 0.025);
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
  border: 1px solid rgba(169, 180, 191, 0.14);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.015) 100%),
    linear-gradient(145deg, rgba(30, 37, 45, 0.9), rgba(19, 24, 31, 0.96));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06), 0 10px 20px rgba(0, 0, 0, 0.2);
  font-size: 0.74rem;
  color: var(--war-muted);
}

.steel-legend .relationship-legend-item:nth-child(1) {
  border-color: color-mix(in srgb, var(--war-ally) 28%, rgba(172, 183, 194, 0.14));
}

.steel-legend .relationship-legend-item:nth-child(2) {
  border-color: color-mix(in srgb, var(--war-enemy) 28%, rgba(172, 183, 194, 0.14));
}

.steel-legend .relationship-legend-item:nth-child(3) {
  border-color: color-mix(in srgb, var(--war-neutral) 28%, rgba(172, 183, 194, 0.14));
}

.faction-detail {
  animation: detail-rise 320ms var(--ease-ritual-lift, cubic-bezier(0.4, 0, 0.2, 1));
  border-color: rgba(170, 181, 191, 0.16);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.02) 24%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(29, 36, 44, 0.95), rgba(19, 25, 31, 0.98) 58%, rgba(13, 18, 23, 1));
  box-shadow:
    0 24px 42px rgba(0, 0, 0, 0.3),
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    inset 0 -1px 0 rgba(255, 255, 255, 0.02);
}

.faction-detail-grid {
  display: grid;
  gap: 1.5rem;
}

.faction-detail-header {
  position: relative;
  padding: 1.2rem 1.25rem;
  border-radius: 1.75rem;
  border: 1px solid rgba(172, 183, 193, 0.14);
  background:
    radial-gradient(circle at top right, rgba(182, 194, 204, 0.08), transparent 34%),
    linear-gradient(180deg, rgba(255, 255, 255, 0.07), rgba(255, 255, 255, 0.02) 36%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(41, 49, 57, 0.92), rgba(25, 31, 39, 0.96) 56%, rgba(17, 22, 28, 1));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    inset 0 -1px 0 rgba(255, 255, 255, 0.025),
    0 16px 28px rgba(0, 0, 0, 0.22);
}

.faction-detail-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 4rem;
  height: 4rem;
  border-radius: 1.3rem;
  border: 1px solid rgba(174, 184, 194, 0.16);
  background:
    radial-gradient(circle at 30% 24%, rgba(255, 255, 255, 0.22), rgba(255, 255, 255, 0.03) 36%, rgba(255, 255, 255, 0) 62%),
    linear-gradient(145deg, rgba(77, 87, 98, 0.94), rgba(44, 52, 60, 0.96) 56%, rgba(26, 32, 39, 0.98));
  box-shadow:
    0 16px 28px rgba(0, 0, 0, 0.24),
    inset 0 1px 0 rgba(255, 255, 255, 0.1),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03);
}

.faction-section-card {
  padding: 1.15rem;
  border-radius: 1.5rem;
  border: 1px solid rgba(169, 180, 190, 0.14);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.055), rgba(255, 255, 255, 0.02) 38%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(33, 40, 48, 0.92), rgba(21, 27, 33, 0.96) 60%, rgba(15, 20, 25, 0.98));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    inset 0 -1px 0 rgba(255, 255, 255, 0.025),
    0 14px 26px rgba(0, 0, 0, 0.22);
}

.faction-metric-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.85rem;
}

.faction-metric-card {
  padding: 0.95rem 1rem;
  border-radius: 1.2rem;
  border: 1px solid rgba(169, 180, 190, 0.12);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.015) 42%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(40, 47, 56, 0.92), rgba(24, 30, 37, 0.96));
  box-shadow: 0 12px 22px rgba(0, 0, 0, 0.22), inset 0 1px 0 rgba(255, 255, 255, 0.06);
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
  border: 1px solid rgba(169, 180, 190, 0.14);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.02) 36%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(35, 42, 50, 0.92), rgba(21, 27, 34, 0.96));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06), 0 12px 22px rgba(0, 0, 0, 0.22);
}

.faction-relationship-card--ally {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 14px 26px color-mix(in srgb, var(--war-ally) 14%, transparent);
}

.faction-relationship-card--enemy {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 14px 26px color-mix(in srgb, var(--war-enemy) 14%, transparent);
}

.faction-relationship-card--neutral {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 14px 26px color-mix(in srgb, var(--war-neutral) 12%, transparent);
}

.faction-relation-badge {
  color: var(--war-text-soft);
}

.faction-relation-badge--ally {
  border-color: color-mix(in srgb, var(--war-ally) 36%, rgba(172, 183, 194, 0.14));
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--war-ally) 18%, rgba(255, 255, 255, 0.04)), rgba(255, 255, 255, 0.02)),
    linear-gradient(145deg, rgba(29, 38, 39, 0.95), rgba(18, 24, 25, 0.98));
  color: #c7ddd6;
}

.faction-relation-badge--enemy {
  border-color: color-mix(in srgb, var(--war-enemy) 38%, rgba(172, 183, 194, 0.14));
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--war-enemy) 18%, rgba(255, 255, 255, 0.04)), rgba(255, 255, 255, 0.02)),
    linear-gradient(145deg, rgba(40, 28, 29, 0.95), rgba(23, 17, 18, 0.98));
  color: #e0c1be;
}

.faction-relation-badge--neutral {
  border-color: color-mix(in srgb, var(--war-neutral) 36%, rgba(172, 183, 194, 0.14));
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--war-neutral) 16%, rgba(255, 255, 255, 0.04)), rgba(255, 255, 255, 0.02)),
    linear-gradient(145deg, rgba(39, 37, 30, 0.95), rgba(23, 22, 18, 0.98));
  color: #d4cfbd;
}

.faction-member-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.8rem;
  padding: 0.85rem 1rem;
  border-radius: 1.15rem;
  border: 1px solid rgba(169, 180, 190, 0.12);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.055), rgba(255, 255, 255, 0.015) 42%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(38, 46, 54, 0.92), rgba(22, 28, 35, 0.96));
  box-shadow: 0 12px 22px rgba(0, 0, 0, 0.2), inset 0 1px 0 rgba(255, 255, 255, 0.06);
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
  color: #352817;
  background:
    radial-gradient(circle at 30% 28%, rgba(255, 255, 255, 0.32), rgba(255, 255, 255, 0.08) 36%, rgba(255, 255, 255, 0) 62%),
    linear-gradient(145deg, rgba(202, 170, 120, 0.98), rgba(145, 112, 64, 0.92));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.2), 0 10px 18px rgba(0, 0, 0, 0.22);
}

.faction-rankings-shell {
  border-radius: 1.75rem;
  border: 1px solid rgba(170, 181, 191, 0.15);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.055), rgba(255, 255, 255, 0.018) 28%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(29, 36, 44, 0.95), rgba(19, 24, 30, 0.98) 58%, rgba(12, 16, 21, 1));
  box-shadow: 0 20px 34px rgba(0, 0, 0, 0.28), inset 0 1px 0 rgba(255, 255, 255, 0.06);
}

.faction-rankings-table {
  color: var(--war-text-soft);
}

.faction-rankings-table thead tr {
  border-color: rgba(171, 181, 191, 0.12) !important;
}

.faction-rankings-table thead th {
  background: rgba(255, 255, 255, 0.035);
  color: var(--war-muted);
}

.faction-rank-row {
  border-color: rgba(171, 181, 191, 0.1) !important;
}

.faction-rank-row:hover {
  background: rgba(185, 197, 207, 0.045) !important;
}

.faction-rank-row--current {
  background:
    linear-gradient(90deg, rgba(182, 144, 91, 0.12), rgba(255, 255, 255, 0.02) 48%, rgba(255, 255, 255, 0.01) 100%) !important;
  box-shadow: inset 3px 0 0 rgba(182, 144, 91, 0.42);
}

.faction-position-card {
  border-color: rgba(182, 144, 91, 0.18);
  background:
    linear-gradient(180deg, rgba(182, 144, 91, 0.08), rgba(255, 255, 255, 0.02) 32%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(34, 30, 25, 0.96), rgba(20, 18, 16, 0.98));
  box-shadow:
    0 18px 30px rgba(0, 0, 0, 0.24),
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 0 0 1px rgba(182, 144, 91, 0.06);
}

.faction-rankings-table tbody tr:last-child {
  border-bottom: none;
}

.factions-view .text-amber-400 {
  color: #d4ba8e !important;
}

.factions-view .text-gray-400 {
  color: #b8c0c8 !important;
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
