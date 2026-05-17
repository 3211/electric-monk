<script setup>
import { ref, computed, onMounted } from 'vue'
import { useVassalage } from '@/composables/useVassalage'
import { useEconomy } from '@/composables/useEconomy'

const vassalage = useVassalage()
const economy = useEconomy()

const targetUsername = ref('')
const targetSearchResults = ref([])
const searching = ref(false)
const showCrusadeConfirm = ref(false)
const selectedTarget = ref(null)

onMounted(async () => {
  await Promise.all([
    vassalage.fetchVassalageInfo(),
    vassalage.fetchAkashicLogs(20),
  ])
})

// Search for a player by username
async function searchPlayer() {
  if (!targetUsername.value.trim()) return
  searching.value = true
  try {
    const results = await vassalage.lookupPlayer(targetUsername.value.trim())
    targetSearchResults.value = results
  } finally {
    searching.value = false
  }
}

// Select a target for crusade
function selectTarget(player) {
  selectedTarget.value = player
  showCrusadeConfirm.value = true
}

// Launch crusade
async function executeCrusade() {
  if (!selectedTarget.value) return
  try {
    await vassalage.launchCrusade(selectedTarget.value.id)
    showCrusadeConfirm.value = false
    selectedTarget.value = null
    targetUsername.value = ''
    targetSearchResults.value = []
  } catch {
    // error is handled in composable
  }
}

// Format timestamp
function formatTime(timestamp) {
  if (!timestamp) return ''
  return new Date(timestamp).toLocaleString()
}

// Action type display names
const actionNames = {
  crusade: 'Crusade',
  schism: 'Schism',
  plague: 'Plague',
}

// Action type colors
const actionColors = {
  crusade: 'text-red-500',
  schism: 'text-purple-500',
  plague: 'text-emerald-500',
}

const hasDailyTithes = computed(() => {
  const tithes = vassalage.dailyTithes || {}
  return (tithes.mana_per_day || 0) > 0 || (tithes.gold_per_day || 0) > 0 || (tithes.food_per_day || 0) > 0
})
</script>

<template>
  <div class="vatican-shell">
    <header class="vatican-header border-b surface-divider">
      <div class="app-frame py-6 lg:py-8">
        <div class="vatican-hero">
          <div class="vatican-hero-glow" aria-hidden="true"></div>
          <div class="vatican-hero-arches" aria-hidden="true"></div>
          <div class="flex flex-col gap-5">
            <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
              <div class="relative min-w-0">
                <div class="vatican-title-frame" aria-hidden="true"></div>
                <h1 class="ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">The Vatican</h1>
                <p class="relative mt-2 text-sm text-theme-text-muted">Spiritual hierarchy, tithes, and holy war</p>
              </div>
              <div class="flex flex-wrap items-center gap-3">
                <div class="chip vatican-resource-chip vatican-resource-chip--heresy gap-2 px-4 py-2 text-xs text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                  <span class="text-purple-500">&#x271D;</span>
                  <span>Heresy: <span class="font-semibold text-purple-500">{{ economy.heresy }}</span></span>
                </div>
                <div v-if="vassalage.divineShieldRemaining" class="chip vatican-resource-chip vatican-resource-chip--shield gap-2 px-4 py-2 text-xs shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                  <span class="text-amber-500">&#x1F6E1;</span>
                  <span class="font-semibold text-amber-600">Shield: {{ vassalage.divineShieldRemaining }}</span>
                </div>
              </div>
            </div>
            <div class="vatican-architectural-line" aria-hidden="true"></div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10 space-y-8">
      <section class="vatican-card p-5 sm:p-6">
        <div class="vatican-card-header">
          <h2 class="vatican-card-title text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-amber-500">&#x1F451;</span>
            Your Liege Lord
          </h2>
        </div>
        <div class="vatican-divider"></div>

        <div v-if="vassalage.isVassal" class="space-y-4">
          <div class="vatican-liege-panel">
            <div class="flex-1">
              <p class="text-sm leading-relaxed text-theme-text">
                You bow before <span class="font-semibold text-amber-600">{{ vassalage.suzerain?.username || 'Unknown' }}</span>
                <span v-if="vassalage.suzerain?.faith" class="text-theme-text-muted"> - {{ vassalage.suzerain.faith }}</span>
              </p>
              <p class="mt-2 text-xs text-theme-text-muted">10% of your gross production flows upward as tithe</p>
            </div>
            <div class="w-full sm:w-auto">
              <button
                @click="vassalage.declareSchism()"
                :disabled="vassalage.schismLoading || economy.heresy < vassalage.schismCost"
                class="vatican-schism-btn w-full px-4 py-2 text-sm font-semibold rounded-xl disabled:opacity-40 disabled:cursor-not-allowed sm:w-auto"
              >
                <span v-if="vassalage.schismLoading">Declaring...</span>
                <span v-else>Declare Schism ({{ vassalage.schismCost }} heresy)</span>
              </button>
            </div>
          </div>
        </div>

        <div v-else class="vatican-free-panel">
          <p class="text-sm font-medium text-emerald-600">You are a free soul. No suzerain commands you.</p>
          <p v-if="vassalage.hasVassals" class="mt-2 text-xs text-theme-text-muted">But others bow to you...</p>
        </div>
      </section>

      <section class="vatican-card p-5 sm:p-6">
        <div class="vatican-card-header">
          <h2 class="vatican-card-title text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-amber-500">&#x2694;</span>
            Your Vassals
            <span v-if="vassalage.vassalCount > 0" class="chip vatican-count-chip gap-1 px-2 py-0.5 text-xs font-semibold text-amber-600">
              {{ vassalage.vassalCount }}
            </span>
          </h2>
        </div>
        <div class="vatican-divider"></div>

        <div v-if="vassalage.hasVassals" class="space-y-3">
          <div
            v-for="vassal in vassalage.vassals"
            :key="vassal.id"
            class="vatican-vassal-row"
          >
            <div>
              <p class="text-sm font-medium text-theme-text">{{ vassal.username }}</p>
              <p v-if="vassal.faith" class="text-xs text-theme-text-muted">{{ vassal.faith }}</p>
            </div>
            <div class="text-xs font-semibold text-amber-600">
              10% tithe
            </div>
          </div>

          <div class="vatican-tithe-band">
            <p class="text-xs text-theme-text-muted">Daily tithes received:</p>
            <div class="mt-3 flex flex-wrap gap-2">
              <span v-if="vassalage.dailyTithes.mana_per_day > 0" class="vatican-tithe-pill vatican-tithe-pill--mana">
                +{{ vassalage.dailyTithes.mana_per_day }} mana
              </span>
              <span v-if="vassalage.dailyTithes.gold_per_day > 0" class="vatican-tithe-pill vatican-tithe-pill--gold">
                +{{ vassalage.dailyTithes.gold_per_day }} gold
              </span>
              <span v-if="vassalage.dailyTithes.food_per_day > 0" class="vatican-tithe-pill vatican-tithe-pill--food">
                +{{ vassalage.dailyTithes.food_per_day }} food
              </span>
              <span v-if="!hasDailyTithes" class="vatican-tithe-pill">
                none yet
              </span>
            </div>
          </div>
        </div>

        <div v-else class="vatican-empty-panel">
          <p class="text-sm text-theme-text-dim">You have no vassals. Crusade to subjugate other players.</p>
        </div>
      </section>

      <section class="vatican-card p-5 sm:p-6">
        <div class="vatican-card-header">
          <h2 class="vatican-card-title text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-red-500">&#x2694;</span>
            Launch Crusade
          </h2>
        </div>
        <div class="vatican-divider"></div>

        <div class="vatican-crusade-brief">
          <p class="text-xs text-theme-text-muted">
            Spend Mana to attack another player. If victorious, they become your Vassal and pay 10% tithe.
            Your attack power: <span class="font-semibold text-blue-500">{{ vassalage.crusadeAttackPower }}</span> (Mana + Clerics)
          </p>
        </div>

        <div class="mt-5 flex flex-col gap-3 sm:flex-row sm:items-end">
          <div class="flex-1">
            <label class="mb-1 block text-xs text-theme-text-muted">Target Username</label>
            <input
              v-model="targetUsername"
              @keyup.enter="searchPlayer"
              type="text"
              placeholder="Enter player name..."
              class="form-field vatican-field w-full px-4 py-3 text-sm text-theme-text placeholder:text-theme-text-dim focus:outline-none"
            />
          </div>
          <button
            @click="searchPlayer"
            :disabled="searching || !targetUsername.trim()"
            class="vatican-search-btn px-5 py-3 text-sm font-semibold rounded-xl disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {{ searching ? 'Searching...' : 'Search' }}
          </button>
        </div>

        <div v-if="targetSearchResults.length > 0" class="mt-4 space-y-3">
          <div
            v-for="player in targetSearchResults"
            :key="player.id"
            class="vatican-target-row"
          >
            <div>
              <p class="text-sm font-medium text-theme-text">{{ player.username }}</p>
              <p v-if="player.faith" class="text-xs text-theme-text-muted">{{ player.faith }}</p>
            </div>
            <button
              @click="selectTarget(player)"
              class="vatican-target-btn px-4 py-2 text-xs font-semibold rounded-xl"
            >
              Target
            </button>
          </div>
        </div>

        <div v-if="vassalage.combatResult && vassalage.combatResult.type === 'crusade'" class="vatican-result-panel mt-5" :class="vassalage.combatResult.success ? 'vatican-result-panel--success' : 'vatican-result-panel--failure'">
          <p class="text-sm font-semibold" :class="vassalage.combatResult.success ? 'text-emerald-600' : 'text-red-600'">
            {{ vassalage.combatResult.success ? 'Crusade Victorious!' : 'Crusade Failed!' }}
          </p>
          <div class="mt-3 space-y-1 text-xs text-theme-text-muted">
            <p>Attack Power: {{ Math.round(vassalage.combatResult.attack_power) }} (roll: {{ Math.round(vassalage.combatResult.attack_roll) }})</p>
            <p>Defense Power: {{ Math.round(vassalage.combatResult.defense_power) }} (roll: {{ Math.round(vassalage.combatResult.defense_roll) }})</p>
            <p>Mana Cost: {{ vassalage.combatResult.mana_cost }}</p>
          </div>
        </div>

        <div v-if="vassalage.combatError" class="vatican-error-panel mt-4">
          <p class="text-xs text-red-600">{{ vassalage.combatError }}</p>
        </div>
      </section>

      <div v-if="showCrusadeConfirm" class="vatican-modal-overlay fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" @click.self="showCrusadeConfirm = false">
        <div class="vatican-modal-panel w-full max-w-md mx-4 p-6 space-y-4">
          <div class="vatican-modal-crest" aria-hidden="true"></div>
          <h3 class="text-lg font-semibold text-theme-text">Confirm Crusade</h3>
          <p class="text-sm text-theme-text-muted">
            You are about to launch a crusade against <span class="font-semibold text-red-500">{{ selectedTarget?.username }}</span>.
            This will cost <span class="font-semibold text-blue-500">50 Mana</span> regardless of outcome.
          </p>
          <p class="text-xs text-theme-text-muted">Your Attack Power: {{ vassalage.crusadeAttackPower }}</p>
          <div class="flex gap-3">
            <button
              @click="executeCrusade"
              :disabled="vassalage.crusadeLoading"
              class="vatican-confirm-btn flex-1 px-4 py-2 text-sm font-semibold rounded-xl disabled:opacity-40"
            >
              {{ vassalage.crusadeLoading ? 'Crusading...' : 'Launch Crusade' }}
            </button>
            <button
              @click="showCrusadeConfirm = false"
              class="vatican-cancel-btn flex-1 px-4 py-2 text-sm font-semibold rounded-xl"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>

      <section class="vatican-card p-5 sm:p-6">
        <div class="vatican-card-header">
          <h2 class="vatican-card-title text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-theme-accent">&#x1F4DC;</span>
            Akashic Records
          </h2>
        </div>
        <div class="vatican-divider"></div>

        <div v-if="vassalage.akashicLogs.length === 0" class="vatican-empty-panel">
          <p class="text-sm text-theme-text-dim">No recorded events yet.</p>
        </div>

        <div v-else class="space-y-3 max-h-72 overflow-y-auto pr-1">
          <div
            v-for="log in vassalage.akashicLogs"
            :key="log.id"
            class="vatican-log-row"
          >
            <div class="mt-0.5 flex-shrink-0">
              <span v-if="log.action_type === 'crusade'" class="text-red-500">&#x2694;</span>
              <span v-else-if="log.action_type === 'schism'" class="text-purple-500">&#x2728;</span>
              <span v-else-if="log.action_type === 'plague'" class="text-emerald-500">&#x2620;</span>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="text-xs font-semibold" :class="actionColors[log.action_type] || 'text-theme-text'">
                  {{ actionNames[log.action_type] || log.action_type }}
                </span>
                <span class="text-[0.65rem] text-theme-text-dim">{{ formatTime(log.created_at) }}</span>
              </div>
              <p class="mt-1 text-xs leading-relaxed text-theme-text-muted">
                <template v-if="log.action_type === 'crusade'">
                  <span v-if="log.result_data?.success">
                    {{ log.actor_username || 'You' }} conquered {{ log.target_username }}
                  </span>
                  <span v-else>
                    {{ log.actor_username || 'You' }} failed to conquer {{ log.target_username }}
                  </span>
                </template>
                <template v-else-if="log.action_type === 'schism'">
                  {{ log.target_username }} broke free from their suzerain
                </template>
                <template v-else-if="log.action_type === 'plague'">
                  Anonymous plague struck {{ log.target_username }} - {{ log.result_data?.food_destroyed || 0 }} food destroyed
                </template>
              </p>
            </div>
          </div>
        </div>

        <button
          @click="vassalage.fetchAkashicLogs(50)"
          :disabled="vassalage.logsLoading"
          class="vatican-refresh-btn mt-4 w-full py-3 text-xs font-medium"
        >
          {{ vassalage.logsLoading ? 'Loading...' : 'Refresh Logs' }}
        </button>
      </section>
    </main>
  </div>
</template>

<style scoped>
.vatican-shell {
  position: relative;
  isolation: isolate;
}

.vatican-shell::before,
.vatican-shell::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
}

.vatican-shell::before {
  inset: -6% -8% auto;
  height: 28rem;
  background:
    radial-gradient(circle at 50% 4%, rgba(255, 223, 147, 0.34) 0%, rgba(255, 223, 147, 0.12) 24%, transparent 58%),
    radial-gradient(circle at 22% 20%, rgba(240, 182, 59, 0.14) 0%, transparent 26%),
    radial-gradient(circle at 78% 16%, rgba(255, 255, 255, 0.36) 0%, transparent 20%);
  filter: blur(24px);
  opacity: 0.92;
}

.vatican-shell::after {
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.16), transparent 18%, transparent 78%, rgba(213, 154, 23, 0.04)),
    radial-gradient(circle at 50% 100%, rgba(240, 182, 59, 0.05), transparent 24%);
  opacity: 0.82;
}

.vatican-shell > * {
  position: relative;
  z-index: 1;
}

.vatican-header {
  position: relative;
  background: linear-gradient(180deg, rgba(255, 252, 246, 0.7), rgba(248, 240, 225, 0.4));
}

.vatican-hero {
  position: relative;
  overflow: hidden;
  border-radius: 34px;
  padding: clamp(1.4rem, 3vw, 2rem);
  border: 1px solid rgba(208, 171, 83, 0.24);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.92), rgba(251, 244, 231, 0.96) 44%, rgba(246, 236, 218, 0.94));
  box-shadow:
    0 18px 38px rgba(83, 59, 14, 0.08),
    0 28px 64px rgba(190, 148, 62, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.92);
}

.vatican-hero::before {
  content: "";
  position: absolute;
  inset: 0.75rem;
  border-radius: 26px;
  border: 1px solid rgba(208, 171, 83, 0.14);
  pointer-events: none;
}

.vatican-hero-glow {
  position: absolute;
  inset: -18% -10% auto;
  height: 18rem;
  background:
    radial-gradient(circle at 50% 10%, rgba(255, 223, 147, 0.38), transparent 48%),
    radial-gradient(circle at 20% 24%, rgba(255, 255, 255, 0.46), transparent 22%),
    radial-gradient(circle at 80% 22%, rgba(240, 182, 59, 0.18), transparent 22%);
  filter: blur(14px);
  opacity: 0.95;
}

.vatican-hero-arches {
  position: absolute;
  inset: 0;
  background:
    linear-gradient(90deg, transparent 0%, transparent 7%, rgba(191, 150, 60, 0.06) 12%, transparent 16%, transparent 84%, rgba(191, 150, 60, 0.06) 88%, transparent 93%, transparent 100%),
    linear-gradient(180deg, rgba(191, 150, 60, 0.08), transparent 26%);
  opacity: 0.86;
  pointer-events: none;
}

.vatican-title-frame {
  position: absolute;
  inset: -0.3rem -0.75rem auto;
  height: 3.5rem;
  border-radius: 22px;
  background: linear-gradient(90deg, rgba(255, 255, 255, 0.42), rgba(255, 223, 147, 0.16), rgba(255, 255, 255, 0.06));
  filter: blur(18px);
  opacity: 0.72;
}

.vatican-hero h1 {
  color: #8f6710;
  text-shadow: 0 10px 22px rgba(213, 154, 23, 0.16);
}

.vatican-architectural-line {
  position: relative;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(208, 171, 83, 0.4), rgba(255, 255, 255, 0.85), rgba(208, 171, 83, 0.4), transparent);
}

.vatican-architectural-line::before,
.vatican-architectural-line::after {
  content: "";
  position: absolute;
  top: 50%;
  width: 0.55rem;
  height: 0.55rem;
  border-radius: 999px;
  border: 1px solid rgba(208, 171, 83, 0.36);
  background: rgba(255, 253, 247, 0.9);
  transform: translateY(-50%);
}

.vatican-architectural-line::before {
  left: 18%;
}

.vatican-architectural-line::after {
  right: 18%;
}

.vatican-resource-chip {
  border-color: rgba(208, 171, 83, 0.2);
  background: linear-gradient(180deg, rgba(255, 254, 249, 0.94), rgba(247, 239, 224, 0.9));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.92),
    0 14px 24px rgba(83, 59, 14, 0.06);
}

.vatican-resource-chip--heresy {
  border-color: rgba(168, 85, 247, 0.18);
  background: linear-gradient(180deg, rgba(249, 246, 255, 0.96), rgba(241, 234, 250, 0.92));
}

.vatican-resource-chip--shield {
  border-color: rgba(217, 119, 6, 0.2);
  background: linear-gradient(180deg, rgba(255, 251, 235, 0.96), rgba(252, 238, 205, 0.92));
}

.vatican-card {
  position: relative;
  overflow: hidden;
  border-radius: 30px;
  border: 1px solid rgba(208, 171, 83, 0.2);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.92), rgba(250, 243, 230, 0.98));
  box-shadow:
    0 16px 34px rgba(83, 59, 14, 0.08),
    0 24px 56px rgba(190, 148, 62, 0.1),
    inset 0 1px 0 rgba(255, 255, 255, 0.94);
}

.vatican-card::before {
  content: "";
  position: absolute;
  inset: 0;
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.26), transparent 28%),
    linear-gradient(180deg, rgba(255, 223, 147, 0.08), transparent 18%, transparent 84%, rgba(213, 154, 23, 0.05));
  pointer-events: none;
}

.vatican-card::after {
  content: "";
  position: absolute;
  inset: 0.8rem;
  border-radius: 24px;
  border: 1px solid rgba(208, 171, 83, 0.08);
  pointer-events: none;
}

.vatican-card-header,
.vatican-card > :not(.vatican-card-header) {
  position: relative;
  z-index: 1;
}

.vatican-card-header {
  margin: -1.25rem -1.25rem 1rem;
  padding: 1rem 1.25rem 0.95rem;
  border-bottom: 1px solid rgba(208, 171, 83, 0.14);
  background:
    linear-gradient(180deg, rgba(243, 239, 232, 0.96), rgba(231, 226, 216, 0.86));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.9),
    inset 0 -1px 0 rgba(208, 171, 83, 0.05);
}

.vatican-card-title {
  color: #4a3a17;
  letter-spacing: 0.01em;
}

.vatican-divider {
  margin-bottom: 1rem;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(208, 171, 83, 0.34), rgba(255, 255, 255, 0.84), rgba(208, 171, 83, 0.34), transparent);
}

.vatican-count-chip {
  border-color: rgba(217, 119, 6, 0.18);
  background: linear-gradient(180deg, rgba(255, 250, 235, 0.95), rgba(249, 235, 199, 0.9));
}

.vatican-liege-panel,
.vatican-free-panel,
.vatican-empty-panel,
.vatican-crusade-brief,
.vatican-target-row,
.vatican-vassal-row,
.vatican-log-row,
.vatican-tithe-band,
.vatican-result-panel,
.vatican-error-panel {
  position: relative;
  border-radius: 22px;
  border: 1px solid rgba(208, 171, 83, 0.14);
  background: linear-gradient(180deg, rgba(255, 253, 247, 0.92), rgba(246, 238, 221, 0.88));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.9),
    0 12px 22px rgba(83, 59, 14, 0.06);
}

.vatican-liege-panel,
.vatican-target-row,
.vatican-vassal-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 1rem 1.1rem;
}

.vatican-free-panel,
.vatican-empty-panel,
.vatican-crusade-brief,
.vatican-tithe-band,
.vatican-result-panel,
.vatican-error-panel,
.vatican-log-row {
  padding: 1rem 1.1rem;
}

.vatican-vassal-row,
.vatican-target-row,
.vatican-log-row {
  transition:
    transform 220ms var(--ease-ritual-lift),
    border-color 220ms var(--ease-ritual-lift),
    box-shadow 220ms var(--ease-ritual-lift),
    background 220ms var(--ease-ritual-lift);
}

.vatican-vassal-row:hover,
.vatican-target-row:hover,
.vatican-log-row:hover {
  transform: translateY(-1px);
  border-color: rgba(208, 171, 83, 0.24);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.94),
    0 16px 28px rgba(83, 59, 14, 0.08),
    0 0 26px rgba(240, 182, 59, 0.08);
}

.vatican-tithe-band {
  background:
    linear-gradient(180deg, rgba(255, 251, 241, 0.96), rgba(245, 235, 215, 0.92));
}

.vatican-tithe-pill {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 2rem;
  padding: 0.4rem 0.8rem;
  border-radius: 999px;
  border: 1px solid rgba(208, 171, 83, 0.16);
  background: rgba(255, 255, 255, 0.72);
  color: var(--theme-text-dim);
  font-size: 0.72rem;
  font-weight: 600;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.9);
}

.vatican-tithe-pill--mana {
  color: #2563eb;
}

.vatican-tithe-pill--gold {
  color: #b45309;
}

.vatican-tithe-pill--food {
  color: #059669;
}

.vatican-field {
  border-color: rgba(170, 135, 57, 0.18);
  background: linear-gradient(180deg, rgba(255, 254, 250, 0.96), rgba(248, 241, 227, 0.9));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.96),
    inset 0 -1px 0 rgba(190, 148, 62, 0.06),
    0 10px 18px rgba(83, 59, 14, 0.05);
}

.vatican-field:hover {
  border-color: rgba(170, 135, 57, 0.28);
  background: linear-gradient(180deg, rgba(255, 255, 252, 0.98), rgba(249, 243, 230, 0.92));
}

.vatican-field:focus {
  border-color: rgba(170, 135, 57, 0.44);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.98),
    0 0 0 4px rgba(213, 154, 23, 0.1),
    0 14px 24px rgba(190, 148, 62, 0.1);
}

.vatican-search-btn,
.vatican-target-btn,
.vatican-schism-btn,
.vatican-confirm-btn,
.vatican-cancel-btn,
.vatican-refresh-btn {
  position: relative;
  overflow: hidden;
  transition:
    transform 220ms var(--ease-ritual-lift),
    border-color 220ms var(--ease-ritual-lift),
    box-shadow 220ms var(--ease-ritual-lift),
    background 220ms var(--ease-ritual-lift),
    color 220ms var(--ease-ritual-lift);
}

.vatican-search-btn,
.vatican-cancel-btn,
.vatican-refresh-btn {
  border: 1px solid rgba(170, 135, 57, 0.24);
  background: linear-gradient(180deg, rgba(255, 253, 247, 0.96), rgba(245, 234, 210, 0.92));
  color: #6b4e12;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.94),
    0 14px 24px rgba(83, 59, 14, 0.08);
}

.vatican-search-btn:hover,
.vatican-cancel-btn:hover,
.vatican-refresh-btn:hover {
  transform: translateY(-1px);
  border-color: rgba(170, 135, 57, 0.34);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.96),
    0 18px 28px rgba(83, 59, 14, 0.1),
    0 0 24px rgba(240, 182, 59, 0.08);
}

.vatican-target-btn,
.vatican-confirm-btn {
  border: 1px solid rgba(185, 28, 28, 0.2);
  background: linear-gradient(180deg, rgba(255, 246, 239, 0.96), rgba(248, 222, 207, 0.92));
  color: #b42318;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.92),
    0 14px 24px rgba(120, 35, 20, 0.08);
}

.vatican-target-btn:hover,
.vatican-confirm-btn:hover {
  transform: translateY(-1px);
  border-color: rgba(185, 28, 28, 0.32);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.94),
    0 18px 28px rgba(120, 35, 20, 0.12),
    0 0 24px rgba(185, 28, 28, 0.08);
}

.vatican-schism-btn {
  border: 1px solid rgba(147, 51, 234, 0.22);
  background: linear-gradient(180deg, rgba(248, 244, 255, 0.96), rgba(232, 223, 248, 0.92));
  color: #7e22ce;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.92),
    0 14px 24px rgba(88, 28, 135, 0.08);
}

.vatican-schism-btn:hover {
  transform: translateY(-1px);
  border-color: rgba(147, 51, 234, 0.34);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.94),
    0 18px 28px rgba(88, 28, 135, 0.12),
    0 0 24px rgba(147, 51, 234, 0.08);
}

.vatican-search-btn:active,
.vatican-target-btn:active,
.vatican-schism-btn:active,
.vatican-confirm-btn:active,
.vatican-cancel-btn:active,
.vatican-refresh-btn:active {
  transform: translateY(1px) scale(0.985);
}

.vatican-result-panel--success {
  border-color: rgba(5, 150, 105, 0.18);
  background: linear-gradient(180deg, rgba(236, 253, 245, 0.96), rgba(220, 252, 231, 0.9));
}

.vatican-result-panel--failure,
.vatican-error-panel {
  border-color: rgba(220, 38, 38, 0.16);
  background: linear-gradient(180deg, rgba(254, 242, 242, 0.96), rgba(254, 226, 226, 0.9));
}

.vatican-modal-overlay {
  animation: overlay-fade var(--dur-enter) var(--ease-standard);
}

.vatican-modal-panel {
  position: relative;
  overflow: hidden;
  border-radius: 28px;
  border: 1px solid rgba(208, 171, 83, 0.22);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.96), rgba(250, 242, 226, 0.98));
  box-shadow:
    0 22px 48px rgba(83, 59, 14, 0.16),
    0 36px 72px rgba(83, 59, 14, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.96);
  animation: modal-rise var(--dur-enter) var(--ease-ritual-lift);
}

.vatican-modal-panel::before {
  content: "";
  position: absolute;
  inset: 0.9rem;
  border-radius: 22px;
  border: 1px solid rgba(208, 171, 83, 0.1);
  pointer-events: none;
}

.vatican-modal-panel > * {
  position: relative;
  z-index: 1;
}

.vatican-modal-crest {
  position: absolute;
  inset: -10% -12% auto;
  height: 10rem;
  background:
    radial-gradient(circle at 50% 20%, rgba(255, 223, 147, 0.24), transparent 44%),
    linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.26), transparent);
  filter: blur(12px);
  opacity: 0.88;
}

.vatican-log-row {
  align-items: flex-start;
  gap: 0.9rem;
}

.vatican-refresh-btn {
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
</style>
