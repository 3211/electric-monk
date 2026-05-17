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
  crusade: 'text-red-400',
  schism: 'text-purple-400',
  plague: 'text-emerald-400',
}
</script>

<template>
  <div>
    <header class="shop-header border-b surface-divider bg-theme-panel/55 backdrop-blur-[16px]">
      <div class="app-frame py-6">
        <div class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="relative">
              <div class="shop-header-glow"></div>
              <h1 class="ritual-heading relative text-3xl font-bold text-theme-accent sm:text-4xl">The Vatican</h1>
              <p class="mt-1 text-sm text-theme-text-muted">Spiritual hierarchy, tithes, and holy war</p>
            </div>
            <div class="flex flex-wrap items-center gap-3">
              <!-- Heresy display -->
              <div class="chip gap-2 px-3 py-2 text-xs text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span class="text-purple-400">&#x271D;</span>
                <span>Heresy: <span class="font-semibold text-purple-400">{{ economy.heresy }}</span></span>
              </div>
              <!-- Divine Shield badge -->
              <div v-if="vassalage.divineShieldRemaining" class="chip gap-2 px-3 py-2 text-xs shadow-[0_10px_20px_rgba(48,38,21,0.06)] bg-amber-500/10 border border-amber-500/30">
                <span class="text-amber-400">&#x1F6E1;</span>
                <span class="font-semibold text-amber-400">Shield: {{ vassalage.divineShieldRemaining }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10 space-y-8">
      <!-- SUZERAIN STATUS -->
      <section class="glass-panel glass-panel-soft glass-gloss p-5">
        <h2 class="text-lg font-semibold text-theme-text mb-3 flex items-center gap-2">
          <span class="text-amber-400">&#x1F451;</span>
          Your Liege Lord
        </h2>

        <div v-if="vassalage.isVassal" class="space-y-3">
          <div class="flex items-center gap-4 p-3 rounded-lg bg-red-500/10 border border-red-500/20">
            <div class="flex-1">
              <p class="text-sm text-theme-text">
                You bow before <span class="font-semibold text-amber-400">{{ vassalage.suzerain?.username || 'Unknown' }}</span>
                <span v-if="vassalage.suzerain?.faith" class="text-theme-text-muted"> - {{ vassalage.suzerain.faith }}</span>
              </p>
              <p class="text-xs text-theme-text-muted mt-1">10% of your gross production flows upward as tithe</p>
            </div>
            <div>
              <button
                @click="vassalage.declareSchism()"
                :disabled="vassalage.schismLoading || economy.heresy < vassalage.schismCost"
                class="px-4 py-2 text-sm font-semibold rounded-lg bg-purple-500/20 border border-purple-500/40 text-purple-300 hover:bg-purple-500/30 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <span v-if="vassalage.schismLoading">Declaring...</span>
                <span v-else>Declare Schism ({{ vassalage.schismCost }} heresy)</span>
              </button>
            </div>
          </div>
        </div>

        <div v-else class="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/20">
          <p class="text-sm text-emerald-400 font-medium">You are a free soul. No suzerain commands you.</p>
          <p v-if="vassalage.hasVassals" class="text-xs text-theme-text-muted mt-1">But others bow to you...</p>
        </div>
      </section>

      <!-- VASSALS & TITHES -->
      <section class="glass-panel glass-panel-soft glass-gloss p-5">
        <h2 class="text-lg font-semibold text-theme-text mb-3 flex items-center gap-2">
          <span class="text-amber-400">&#x2694;</span>
          Your Vassals
          <span v-if="vassalage.vassalCount > 0" class="chip gap-1 px-2 py-0.5 text-xs font-semibold text-amber-400">
            {{ vassalage.vassalCount }}
          </span>
        </h2>

        <div v-if="vassalage.hasVassals" class="space-y-2">
          <div
            v-for="vassal in vassalage.vassals"
            :key="vassal.id"
            class="flex items-center justify-between p-3 rounded-lg bg-theme-panel/50 border border-theme-border"
          >
            <div>
              <p class="text-sm font-medium text-theme-text">{{ vassal.username }}</p>
              <p v-if="vassal.faith" class="text-xs text-theme-text-muted">{{ vassal.faith }}</p>
            </div>
            <div class="text-xs text-theme-text-dim">
              10% tithe
            </div>
          </div>

          <div class="mt-3 pt-3 border-t border-theme-border">
            <p class="text-xs text-theme-text-muted">Daily tithes received:</p>
            <div class="flex gap-4 mt-1">
              <span v-if="vassalage.dailyTithes.mana_per_day > 0" class="text-xs text-blue-400">
                +{{ vassalage.dailyTithes.mana_per_day }} mana
              </span>
              <span v-if="vassalage.dailyTithes.gold_per_day > 0" class="text-xs text-amber-400">
                +{{ vassalage.dailyTithes.gold_per_day }} gold
              </span>
              <span v-if="vassalage.dailyTithes.food_per_day > 0" class="text-xs text-emerald-400">
                +{{ vassalage.dailyTithes.food_per_day }} food
              </span>
              <span v-if="!vassalage.dailyTithes.mana_per_day && !vassalage.dailyTithes.gold_per_day && !vassalage.dailyTithes.food_per_day" class="text-xs text-theme-text-dim">
                none yet
              </span>
            </div>
          </div>
        </div>

        <div v-else class="p-3 rounded-lg bg-theme-panel/30 border border-theme-border">
          <p class="text-sm text-theme-text-dim">You have no vassals. Crusade to subjugate other players.</p>
        </div>
      </section>

      <!-- CRUSADE PANEL -->
      <section class="glass-panel glass-panel-soft glass-gloss p-5">
        <h2 class="text-lg font-semibold text-theme-text mb-3 flex items-center gap-2">
          <span class="text-red-400">&#x2694;</span>
          Launch Crusade
        </h2>

        <p class="text-xs text-theme-text-muted mb-4">
          Spend Mana to attack another player. If victorious, they become your Vassal and pay 10% tithe.
          Your attack power: <span class="font-semibold text-blue-400">{{ vassalage.crusadeAttackPower }}</span> (Mana + Clerics)
        </p>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div class="flex-1">
            <label class="block text-xs text-theme-text-muted mb-1">Target Username</label>
            <input
              v-model="targetUsername"
              @keyup.enter="searchPlayer"
              type="text"
              placeholder="Enter player name..."
              class="w-full rounded-lg border border-theme-border bg-theme-panel/50 px-3 py-2 text-sm text-theme-text placeholder:text-theme-text-dim focus:border-theme-accent focus:outline-none"
            />
          </div>
          <button
            @click="searchPlayer"
            :disabled="searching || !targetUsername.trim()"
            class="px-4 py-2 text-sm font-semibold rounded-lg bg-blue-500/20 border border-blue-500/40 text-blue-300 hover:bg-blue-500/30 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {{ searching ? 'Searching...' : 'Search' }}
          </button>
        </div>

        <!-- Search results -->
        <div v-if="targetSearchResults.length > 0" class="mt-3 space-y-2">
          <div
            v-for="player in targetSearchResults"
            :key="player.id"
            class="flex items-center justify-between p-3 rounded-lg bg-theme-panel/50 border border-theme-border"
          >
            <div>
              <p class="text-sm font-medium text-theme-text">{{ player.username }}</p>
              <p v-if="player.faith" class="text-xs text-theme-text-muted">{{ player.faith }}</p>
            </div>
            <button
              @click="selectTarget(player)"
              class="px-3 py-1.5 text-xs font-semibold rounded-lg bg-red-500/20 border border-red-500/40 text-red-300 hover:bg-red-500/30 transition-colors"
            >
              Target
            </button>
          </div>
        </div>

        <!-- Combat result display -->
        <div v-if="vassalage.combatResult && vassalage.combatResult.type === 'crusade'" class="mt-4 p-4 rounded-lg" :class="vassalage.combatResult.success ? 'bg-emerald-500/10 border border-emerald-500/30' : 'bg-red-500/10 border border-red-500/30'">
          <p class="text-sm font-semibold" :class="vassalage.combatResult.success ? 'text-emerald-400' : 'text-red-400'">
            {{ vassalage.combatResult.success ? 'Crusade Victorious!' : 'Crusade Failed!' }}
          </p>
          <div class="mt-2 text-xs text-theme-text-muted space-y-1">
            <p>Attack Power: {{ Math.round(vassalage.combatResult.attack_power) }} (roll: {{ Math.round(vassalage.combatResult.attack_roll) }})</p>
            <p>Defense Power: {{ Math.round(vassalage.combatResult.defense_power) }} (roll: {{ Math.round(vassalage.combatResult.defense_roll) }})</p>
            <p>Mana Cost: {{ vassalage.combatResult.mana_cost }}</p>
          </div>
        </div>

        <!-- Error display -->
        <div v-if="vassalage.combatError" class="mt-4 p-3 rounded-lg bg-red-500/10 border border-red-500/30">
          <p class="text-xs text-red-400">{{ vassalage.combatError }}</p>
        </div>
      </section>

      <!-- CRUSADE CONFIRMATION MODAL -->
      <div v-if="showCrusadeConfirm" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm" @click.self="showCrusadeConfirm = false">
        <div class="glass-panel glass-panel-soft w-full max-w-md mx-4 p-6 space-y-4">
          <h3 class="text-lg font-semibold text-theme-text">Confirm Crusade</h3>
          <p class="text-sm text-theme-text-muted">
            You are about to launch a crusade against <span class="font-semibold text-red-400">{{ selectedTarget?.username }}</span>.
            This will cost <span class="font-semibold text-blue-400">50 Mana</span> regardless of outcome.
          </p>
          <p class="text-xs text-theme-text-muted">Your Attack Power: {{ vassalage.crusadeAttackPower }}</p>
          <div class="flex gap-3">
            <button
              @click="executeCrusade"
              :disabled="vassalage.crusadeLoading"
              class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg bg-red-500/20 border border-red-500/40 text-red-300 hover:bg-red-500/30 transition-colors disabled:opacity-40"
            >
              {{ vassalage.crusadeLoading ? 'Crusading...' : 'Launch Crusade' }}
            </button>
            <button
              @click="showCrusadeConfirm = false"
              class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg bg-theme-panel/50 border border-theme-border text-theme-text-muted hover:bg-theme-panel/70 transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>

      <!-- AKASHIC LOGS -->
      <section class="glass-panel glass-panel-soft glass-gloss p-5">
        <h2 class="text-lg font-semibold text-theme-text mb-3 flex items-center gap-2">
          <span class="text-theme-accent">&#x1F4DC;</span>
          Akashic Records
        </h2>

        <div v-if="vassalage.akashicLogs.length === 0" class="p-3 rounded-lg bg-theme-panel/30 border border-theme-border">
          <p class="text-sm text-theme-text-dim">No recorded events yet.</p>
        </div>

        <div v-else class="space-y-2 max-h-64 overflow-y-auto">
          <div
            v-for="log in vassalage.akashicLogs"
            :key="log.id"
            class="flex items-start gap-3 p-2 rounded-lg bg-theme-panel/30 border border-theme-border"
          >
            <div class="flex-shrink-0 mt-0.5">
              <span v-if="log.action_type === 'crusade'" class="text-red-400">&#x2694;</span>
              <span v-else-if="log.action_type === 'schism'" class="text-purple-400">&#x2728;</span>
              <span v-else-if="log.action_type === 'plague'" class="text-emerald-400">&#x2620;</span>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-xs font-semibold" :class="actionColors[log.action_type] || 'text-theme-text'">
                  {{ actionNames[log.action_type] || log.action_type }}
                </span>
                <span class="text-[0.65rem] text-theme-text-dim">{{ formatTime(log.created_at) }}</span>
              </div>
              <p class="text-xs text-theme-text-muted mt-0.5">
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
          class="mt-3 w-full py-2 text-xs font-medium text-theme-text-muted hover:text-theme-text transition-colors"
        >
          {{ vassalage.logsLoading ? 'Loading...' : 'Refresh Logs' }}
        </button>
      </section>
    </main>
  </div>
</template>

<style scoped>
.shop-header-glow {
  position: absolute;
  inset: 0;
  background: radial-gradient(circle at top, rgba(255, 223, 147, 0.16), transparent 60%);
  opacity: 0.8;
  pointer-events: none;
}
</style>