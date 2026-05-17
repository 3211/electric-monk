<script setup>
import { ref, computed, onMounted } from 'vue'
import { useCatacombs } from '@/composables/useCatacombs'
import { useVassalage } from '@/composables/useVassalage'
import { useEconomy } from '@/composables/useEconomy'

const catacombs = useCatacombs()
const vassalage = useVassalage()
const economy = useEconomy()

const plagueTarget = ref('')
const plagueSearchResults = ref([])
const searchingPlague = ref(false)
const showPlagueConfirm = ref(false)
const selectedPlagueTarget = ref(null)
const showSchismConfirm = ref(false)

onMounted(async () => {
  await Promise.all([
    catacombs.fetchCatacombsItems(),
    vassalage.fetchVassalageInfo(),
  ])
})

// Search for a plague target
async function searchPlagueTarget() {
  if (!plagueTarget.value.trim()) return
  searchingPlague.value = true
  try {
    const results = await vassalage.lookupPlayer(plagueTarget.value.trim())
    plagueSearchResults.value = results
  } finally {
    searchingPlague.value = false
  }
}

// Select plague target
function selectPlagueTarget(player) {
  selectedPlagueTarget.value = player
  showPlagueConfirm.value = true
}

// Execute plague
async function executePlague() {
  if (!selectedPlagueTarget.value) return
  try {
    await vassalage.castPlague(selectedPlagueTarget.value.id)
    showPlagueConfirm.value = false
    selectedPlagueTarget.value = null
    plagueTarget.value = ''
    plagueSearchResults.value = []
  } catch {
    // handled in composable
  }
}

// Execute schism
async function executeSchism() {
  try {
    await vassalage.declareSchism()
    showSchismConfirm.value = false
  } catch {
    // handled in composable
  }
}

// Heresy cost for plague
const plagueCost = computed(() => {
  const config = economy.gameConfig?.['plague.heresy_cost'] || 75
  return config
})

// Building production info for cultist display
function buildingProduction(buildingType, stat) {
  const key = `building.${buildingType}.${stat}`
  return economy.gameConfig?.[key] || 0
}

// Format cost display for an item
function formatItemCost(item) {
  return catacombs.formatCosts(item)
}

// Check if player can afford item
function canAffordItem(item) {
  return catacombs.canAfford(item)
}

// Check prerequisite
function hasPrereq(item) {
  return catacombs.hasPrerequisite(item)
}

// Owned count of a building type
function ownedCount(buildingType) {
  return economy.buildingCounts?.[buildingType] || 0
}

// Next scaled cost display
function formatNextCost(item) {
  const costs = catacombs.scaledCosts(item)
  const parts = []
  if (costs.karma > 0) parts.push(`${costs.karma} karma`)
  if (costs.gold > 0) parts.push(`${costs.gold} gold`)
  if (costs.heresy > 0) parts.push(`${costs.heresy} heresy`)
  return parts.join(', ')
}
</script>

<template>
  <div class="catacombs-theme">
    <header class="border-b border-purple-900/40 bg-gray-950/80 backdrop-blur-[16px]">
      <div class="app-frame py-6">
        <div class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="relative">
              <div class="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(139,92,246,0.2),transparent_60%)]" aria-hidden="true"></div>
              <h1 class="relative text-3xl font-bold text-purple-400 sm:text-4xl">The Catacombs</h1>
              <p class="relative mt-1 text-sm text-purple-300/60">Shadow economy. Heresy breeds here.</p>
            </div>
            <div class="flex flex-wrap items-center gap-3">
              <!-- Heresy Display -->
              <div class="flex items-center gap-2 px-4 py-2 rounded-lg bg-purple-500/10 border border-purple-500/30">
                <span class="text-purple-400 text-lg">&#x271D;</span>
                <div>
                  <p class="text-xs text-purple-300/60">Heresy</p>
                  <p class="text-sm font-semibold text-purple-300">{{ catacombs.heresy }} / {{ catacombs.heresyCap }}</p>
                </div>
              </div>
              <!-- Heresy progress bar -->
              <div class="w-24 h-2 rounded-full bg-gray-800 overflow-hidden">
                <div
                  class="h-full rounded-full bg-gradient-to-r from-purple-600 to-purple-400 transition-all duration-500"
                  :style="{ width: `${catacombs.heresyPercent}%` }"
                ></div>
              </div>
              <!-- Gold Display -->
              <div class="flex items-center gap-2 px-3 py-2 rounded-lg bg-amber-500/10 border border-amber-500/30">
                <span class="text-amber-400">&#x1F4B0;</span>
                <span class="text-sm font-semibold text-amber-400">{{ catacombs.gold }}</span>
              </div>
            </div>
          </div>

          <!-- Heresy generation rate -->
          <div class="flex items-center gap-2 text-xs text-purple-300/60">
            <span>+{{ catacombs.heresyPerDay }} heresy/day</span>
            <span class="text-gray-600">|</span>
            <span v-if="vassalage.divineShieldRemaining" class="text-amber-400 font-medium">
              &#x1F6E1; Shield: {{ vassalage.divineShieldRemaining }}
            </span>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10 space-y-8">
      <!-- CULTIST & COVEN SHOP -->
      <section class="rounded-xl border border-purple-900/40 bg-gray-950/60 p-5">
        <h2 class="text-lg font-semibold text-purple-300 mb-4 flex items-center gap-2">
          <span>&#x1F52E;</span>
          Shadow Holdings
        </h2>

        <div v-if="catacombs.loading && catacombs.allCatacombsItems.length === 0" class="p-12 text-center text-purple-300/50">
          <div class="mb-3 text-4xl animate-pulse">Loading the dark...</div>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-2 xl:grid-cols-2">
          <!-- Cultist -->
          <div
            v-for="item in catacombs.allCatacombsItems"
            :key="item.id"
            class="group relative overflow-hidden rounded-xl border border-purple-900/40 bg-gray-900/60 p-5 transition-all duration-300 hover:-translate-y-1 hover:border-purple-500/40 hover:shadow-[0_18px_32px_rgba(139,92,246,0.12)]"
            :class="{
              'opacity-60': !canAffordItem(item),
              'ring-2 ring-purple-500/40': ownedCount(item.effect_data?.building_type) > 0
            }"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(139,92,246,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100" aria-hidden="true"></div>

            <div class="relative">
              <!-- Tier badge -->
              <div class="mb-2 flex items-center justify-between">
                <span class="text-[0.65rem] font-bold uppercase tracking-wider text-purple-400/70">
                  {{ item.effect_data?.building_type === 'cultist' ? 'Worker' : 'Infrastructure' }}
                </span>
                <span v-if="ownedCount(item.effect_data?.building_type) > 0" class="chip gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-purple-400">
                  x{{ ownedCount(item.effect_data?.building_type) }}
                </span>
              </div>

              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-14 w-14 items-center justify-center rounded-2xl border border-purple-500/20 bg-purple-500/10 text-3xl shadow-[0_10px_20px_rgba(139,92,246,0.12)]">
                  {{ item.emoji_icon }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-purple-200">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-purple-400">
                    <span>{{ formatItemCost(item) }}</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-purple-300/60">{{ item.description }}</p>

              <!-- Production Info -->
              <div v-if="item.effect_type === 'add_building'" class="mb-3 space-y-1 text-[0.7rem] text-purple-300/50">
                <div v-if="buildingProduction(item.effect_data.building_type, 'heresy_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-purple-400">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'heresy_per_day') }} heresy/day each</span>
                </div>
                <div v-if="item.effect_data?.building_type === 'cultist' && buildingProduction('cultist', 'food_consumption_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-red-400">-</span>
                  <span>{{ buildingProduction('cultist', 'food_consumption_per_day') }} food/day each</span>
                </div>
                <div v-if="item.effect_data?.building_type === 'coven'" class="flex items-center gap-1">
                  <span class="text-purple-400">+</span>
                  <span>{{ economy.gameConfig?.['building.coven.heresy_cap_bonus'] || 50 }} heresy cap each</span>
                </div>
                <div v-if="item.effect_data?.building_type === 'coven' && buildingProduction('coven', 'gold_upkeep_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-red-400">-</span>
                  <span>{{ buildingProduction('coven', 'gold_upkeep_per_day') }} gold upkeep/day each</span>
                </div>
                <div v-if="item.cost_scaling" class="flex items-center gap-1 text-purple-400/60">
                  <span>&#x1F4C8;</span>
                  <span>Cost scales with ownership</span>
                </div>
              </div>

              <!-- Next cost preview for scaling items -->
              <div v-if="item.cost_scaling && ownedCount(item.effect_data?.building_type) > 0" class="mb-2 text-[0.65rem] text-purple-300/40">
                Next: {{ formatNextCost(item) }}
              </div>

              <!-- Prerequisite indicator -->
              <div v-if="item.requires_building && !hasPrereq(item)" class="mb-3 flex items-center gap-1 text-[0.7rem] text-red-400">
                <span>&#x1F512;</span>
                <span>Requires {{ catacombs.catacombsBuildingInfo[item.requires_building]?.name || item.requires_building }}</span>
              </div>

              <button
                @click="catacombs.purchaseItem(item.id)"
                :disabled="!canAffordItem(item) || catacombs.purchasing"
                class="w-full py-2 text-sm font-semibold rounded-lg transition-colors"
                :class="canAffordItem(item)
                  ? 'bg-purple-500/20 border border-purple-500/40 text-purple-300 hover:bg-purple-500/30'
                  : 'bg-gray-800/50 border border-gray-700/50 text-gray-500 cursor-not-allowed'"
              >
                <span v-if="catacombs.purchasing && catacombs.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span v-else-if="item.requires_building && !hasPrereq(item)">&#x1F512; Requires {{ catacombs.catacombsBuildingInfo[item.requires_building]?.name || item.requires_building }}</span>
                <span v-else-if="!canAffordItem(item)">Not enough resources</span>
                <span v-else>Purchase</span>
              </button>
            </div>
          </div>
        </div>

        <!-- Purchase error -->
        <div v-if="catacombs.purchaseError" class="mt-4 p-3 rounded-lg bg-red-500/10 border border-red-500/30">
          <p class="text-xs text-red-400">{{ catacombs.purchaseError }}</p>
          <button @click="catacombs.clearPurchaseError()" class="mt-1 text-xs text-red-300 hover:text-red-200">Dismiss</button>
        </div>
      </section>

      <!-- PLAGUE PANEL -->
      <section class="rounded-xl border border-emerald-900/40 bg-gray-950/60 p-5">
        <h2 class="text-lg font-semibold text-emerald-400 mb-3 flex items-center gap-2">
          <span>&#x2620;</span>
          Cast Plague
        </h2>

        <p class="text-xs text-emerald-300/60 mb-4">
          Spend <span class="font-semibold text-purple-400">{{ plagueCost }} heresy</span> to anonymously zero out a target's Food storage.
          Bypasses all defenses. Your identity is hidden in the Akashic Records.
        </p>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div class="flex-1">
            <label class="block text-xs text-emerald-300/60 mb-1">Target Username</label>
            <input
              v-model="plagueTarget"
              @keyup.enter="searchPlagueTarget"
              type="text"
              placeholder="Enter player name..."
              class="w-full rounded-lg border border-emerald-900/40 bg-gray-900/50 px-3 py-2 text-sm text-emerald-200 placeholder:text-emerald-300/30 focus:border-emerald-500 focus:outline-none"
            />
          </div>
          <button
            @click="searchPlagueTarget"
            :disabled="searchingPlague || !plagueTarget.trim()"
            class="px-4 py-2 text-sm font-semibold rounded-lg bg-emerald-500/20 border border-emerald-500/40 text-emerald-300 hover:bg-emerald-500/30 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {{ searchingPlague ? 'Searching...' : 'Search' }}
          </button>
        </div>

        <!-- Search results -->
        <div v-if="plagueSearchResults.length > 0" class="mt-3 space-y-2">
          <div
            v-for="player in plagueSearchResults"
            :key="player.id"
            class="flex items-center justify-between p-3 rounded-lg bg-gray-900/40 border border-emerald-900/30"
          >
            <div>
              <p class="text-sm font-medium text-emerald-200">{{ player.username }}</p>
              <p v-if="player.faith" class="text-xs text-emerald-300/50">{{ player.faith }}</p>
            </div>
            <button
              @click="selectPlagueTarget(player)"
              :disabled="catacombs.heresy < plagueCost"
              class="px-3 py-1.5 text-xs font-semibold rounded-lg bg-emerald-500/20 border border-emerald-500/40 text-emerald-300 hover:bg-emerald-500/30 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Target
            </button>
          </div>
        </div>

        <!-- Plague result -->
        <div v-if="vassalage.combatResult && vassalage.combatResult.type === 'plague'" class="mt-4 p-4 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
          <p class="text-sm font-semibold text-emerald-400">Plague Cast Successfully!</p>
          <p class="text-xs text-emerald-300/60 mt-1">{{ vassalage.combatResult.food_destroyed }} food destroyed. Your identity remains hidden.</p>
        </div>

        <!-- Error display -->
        <div v-if="vassalage.combatError && !showPlagueConfirm" class="mt-4 p-3 rounded-lg bg-red-500/10 border border-red-500/30">
          <p class="text-xs text-red-400">{{ vassalage.combatError }}</p>
        </div>
      </section>

      <!-- SCHISM PANEL (only visible if vassal) -->
      <section v-if="vassalage.isVassal" class="rounded-xl border border-purple-900/40 bg-gray-950/60 p-5">
        <h2 class="text-lg font-semibold text-purple-300 mb-3 flex items-center gap-2">
          <span>&#x2728;</span>
          Declare Schism
        </h2>

        <p class="text-xs text-purple-300/60 mb-3">
          Break free from <span class="font-semibold text-purple-300">{{ vassalage.suzerain?.username || 'your suzerain' }}</span>.
          Costs heresy and grants 24h Divine Shield protection from crusades.
          Cost scales exponentially with each schism.
        </p>

        <div class="flex items-center gap-4 p-3 rounded-lg bg-purple-500/10 border border-purple-500/20">
          <div class="flex-1">
            <p class="text-sm font-medium text-purple-200">Schism Cost: <span class="font-bold text-purple-400">{{ vassalage.schismCost }} heresy</span></p>
            <p class="text-xs text-purple-300/50 mt-1">Current heresy: {{ catacombs.heresy }}</p>
          </div>
          <button
            @click="showSchismConfirm = true"
            :disabled="catacombs.heresy < vassalage.schismCost || vassalage.schismLoading"
            class="px-4 py-2 text-sm font-semibold rounded-lg bg-purple-500/20 border border-purple-500/40 text-purple-300 hover:bg-purple-500/30 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Declare Schism
          </button>
        </div>

        <!-- Schism result -->
        <div v-if="vassalage.combatResult && vassalage.combatResult.type === 'schism'" class="mt-4 p-4 rounded-lg bg-purple-500/10 border border-purple-500/30">
          <p class="text-sm font-semibold text-purple-300">Schism Declared!</p>
          <p class="text-xs text-purple-300/60 mt-1">
            You are free! Divine Shield active until {{ new Date(vassalage.combatResult.shield_until).toLocaleString() }}
          </p>
        </div>
      </section>

      <!-- HERESY ECONOMY SUMMARY -->
      <section class="rounded-xl border border-purple-900/40 bg-gray-950/60 p-5">
        <h2 class="text-lg font-semibold text-purple-300 mb-3 flex items-center gap-2">
          <span>&#x1F4CA;</span>
          Heresy Economy
        </h2>

        <div class="grid gap-4 sm:grid-cols-3">
          <div class="p-3 rounded-lg bg-purple-500/10 border border-purple-500/20">
            <p class="text-xs text-purple-300/60">Generation</p>
            <p class="text-lg font-semibold text-purple-300">+{{ catacombs.heresyPerDay }}/day</p>
          </div>
          <div class="p-3 rounded-lg bg-purple-500/10 border border-purple-500/20">
            <p class="text-xs text-purple-300/60">Capacity</p>
            <p class="text-lg font-semibold text-purple-300">{{ catacombs.heresyCap }}</p>
          </div>
          <div class="p-3 rounded-lg bg-purple-500/10 border border-purple-500/20">
            <p class="text-xs text-purple-300/60">Schisms Declared</p>
            <p class="text-lg font-semibold text-purple-300">{{ economy.schismCount || 0 }}</p>
          </div>
        </div>
      </section>
    </main>

    <!-- PLAGUE CONFIRMATION MODAL -->
    <div v-if="showPlagueConfirm" class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm" @click.self="showPlagueConfirm = false">
      <div class="rounded-xl border border-emerald-900/40 bg-gray-900 w-full max-w-md mx-4 p-6 space-y-4">
        <h3 class="text-lg font-semibold text-emerald-400">Confirm Plague</h3>
        <p class="text-sm text-emerald-300/60">
          Cast plague on <span class="font-semibold text-emerald-300">{{ selectedPlagueTarget?.username }}</span>?
          This will cost <span class="font-semibold text-purple-400">{{ plagueCost }} heresy</span> and destroy all their Food.
          Your identity will remain anonymous.
        </p>
        <div class="flex gap-3">
          <button
            @click="executePlague"
            :disabled="vassalage.plagueLoading"
            class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg bg-emerald-500/20 border border-emerald-500/40 text-emerald-300 hover:bg-emerald-500/30 transition-colors disabled:opacity-40"
          >
            {{ vassalage.plagueLoading ? 'Casting...' : 'Cast Plague' }}
          </button>
          <button
            @click="showPlagueConfirm = false"
            class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg bg-gray-800/50 border border-gray-700/50 text-gray-400 hover:bg-gray-800/70 transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>

    <!-- SCHISM CONFIRMATION MODAL -->
    <div v-if="showSchismConfirm" class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm" @click.self="showSchismConfirm = false">
      <div class="rounded-xl border border-purple-900/40 bg-gray-900 w-full max-w-md mx-4 p-6 space-y-4">
        <h3 class="text-lg font-semibold text-purple-300">Confirm Schism</h3>
        <p class="text-sm text-purple-300/60">
          Break free from <span class="font-semibold text-purple-300">{{ vassalage.suzerain?.username || 'your suzerain' }}</span>?
          This will cost <span class="font-semibold text-purple-400">{{ vassalage.schismCost }} heresy</span> and grant you 24 hours of Divine Shield.
        </p>
        <p class="text-xs text-purple-300/40">After this schism, the next one will cost {{ Math.floor(100 * Math.pow(2, (economy.schismCount || 0) + 1)) }} heresy.</p>
        <div class="flex gap-3">
          <button
            @click="executeSchism"
            :disabled="vassalage.schismLoading"
            class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg bg-purple-500/20 border border-purple-500/40 text-purple-300 hover:bg-purple-500/30 transition-colors disabled:opacity-40"
          >
            {{ vassalage.schismLoading ? 'Declaring...' : 'Declare Schism' }}
          </button>
          <button
            @click="showSchismConfirm = false"
            class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg bg-gray-800/50 border border-gray-700/50 text-gray-400 hover:bg-gray-800/70 transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.catacombs-theme {
  --tw-ring-color: rgba(139, 92, 246, 0.3);
}
</style>