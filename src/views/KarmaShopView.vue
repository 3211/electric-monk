<template>
  <div>
    <header class="shop-header border-b surface-divider bg-theme-panel/55 backdrop-blur-[16px]">
      <div class="app-frame py-6">
        <div class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="relative">
              <div class="shop-header-glow"></div>
              <h1 class="ritual-heading relative text-3xl font-bold text-theme-accent sm:text-4xl">Karma Shop</h1>
            </div>
            <div class="flex flex-wrap items-center gap-3">
              <div class="chip gap-2 self-start px-4 py-2 text-sm text-theme-text-dim shadow-[0_12px_24px_rgba(48,38,21,0.08)] lg:self-auto">
                <span class="text-lg">{{ prayers.karmaEmoji }}</span>
                <span>Karma: <span :class="karmaClass" class="font-semibold">{{ prayers.karma }}</span></span>
              </div>
              <div class="chip gap-2 px-3 py-2 text-xs text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span class="text-blue-500">+</span>
                <span>Mana: <span class="font-semibold text-blue-500">{{ prayers.mana }}</span></span>
              </div>
              <div class="chip gap-2 px-3 py-2 text-xs text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span class="text-amber-600">+</span>
                <span>Gold: <span class="font-semibold text-amber-600">{{ prayers.gold }}</span></span>
              </div>
              <div class="chip gap-2 px-3 py-2 text-xs text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span class="text-emerald-600">+</span>
                <span>Food: <span class="font-semibold text-emerald-600">{{ prayers.food }}</span></span>
              </div>
            </div>
          </div>

          <div class="segmented-shell self-start flex-wrap">
            <button
              @click="shop.activeTab = 'real_estate'"
              class="pill-tab"
              :class="shop.activeTab === 'real_estate' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              Estates
            </button>
            <button
              @click="shop.activeTab = 'workforce'"
              class="pill-tab"
              :class="shop.activeTab === 'workforce' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              Workers
            </button>
            <button
              @click="shop.activeTab = 'infrastructure'"
              class="pill-tab"
              :class="shop.activeTab === 'infrastructure' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              Slots
            </button>
            <button
              @click="shop.activeTab = 'blessings'"
              class="pill-tab"
              :class="shop.activeTab === 'blessings' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              Blessings
            </button>
            <button
              class="pill-tab pill-tab-inactive cursor-not-allowed opacity-50"
              disabled
              title="Coming soon"
            >
              Avatars
            </button>
            <button
              class="pill-tab pill-tab-inactive cursor-not-allowed opacity-50"
              disabled
              title="Coming soon"
            >
              Titles
            </button>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Real Estate Tab -->
      <div v-if="shop.activeTab === 'real_estate'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Purchase Temples and Gardens to generate Mana and Food. Upgrade Temples to Churches for triple output.
          </p>
          <div class="flex items-center gap-2 text-xs text-theme-text-dim">
            <span class="text-theme-accent">Your buildings:</span>
            <span v-for="(count, type) in economy.buildingCounts" :key="type" class="chip px-2 py-0.5">
              {{ economy.buildingInfo[type]?.name || type }}: {{ count }}
            </span>
          </div>
        </div>

        <div v-if="shop.loading && shop.realEstateItems.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading estates...</div>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="item in shop.realEstateItems"
            :key="item.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
            :class="{ 'opacity-60': !canAfford(item) }"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-12 w-12 items-center justify-center rounded-2xl border border-theme-accent/20 bg-white/55 text-2xl shadow-[0_10px_20px_rgba(213,154,23,0.12)] backdrop-blur-sm">
                  {{ buildingIcon(item.emoji_icon) }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ item.karma_cost }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-theme-text-dim">{{ item.description }}</p>

              <!-- Production/Upkeep Info -->
              <div v-if="item.effect_type === 'add_building'" class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div v-if="buildingProduction(item.effect_data.building_type, 'mana_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-blue-500">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'mana_per_day') }} mana/day</span>
                </div>
                <div v-if="buildingProduction(item.effect_data.building_type, 'food_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-emerald-600">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'food_per_day') }} food/day</span>
                </div>
                <div v-if="buildingProduction(item.effect_data.building_type, 'gold_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-amber-600">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'gold_per_day') }} gold/day</span>
                </div>
                <div v-if="buildingUpkeep(item.effect_data.building_type, 'gold_upkeep_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-red-500">-</span>
                  <span>{{ buildingUpkeep(item.effect_data.building_type, 'gold_upkeep_per_day') }} gold upkeep/day</span>
                </div>
                <div v-if="buildingUpkeep(item.effect_data.building_type, 'food_consumption_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-red-500">-</span>
                  <span>{{ buildingUpkeep(item.effect_data.building_type, 'food_consumption_per_day') }} food consumed/day</span>
                </div>
              </div>
              <div v-else-if="item.effect_type === 'upgrade_building'" class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div class="flex items-center gap-1">
                  <span class="text-blue-500">+</span>
                  <span>{{ buildingProduction(item.effect_data.to_type, 'mana_per_day') }} mana/day (upgraded)</span>
                </div>
                <div v-if="buildingUpkeep(item.effect_data.to_type, 'gold_upkeep_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-red-500">-</span>
                  <span>{{ buildingUpkeep(item.effect_data.to_type, 'gold_upkeep_per_day') }} gold upkeep/day</span>
                </div>
              </div>

              <button
                @click="handlePurchase(item)"
                :disabled="!canAfford(item) || shop.purchasing"
                class="btn-secondary w-full py-2 text-sm disabled:opacity-40 disabled:cursor-not-allowed"
                :class="{ 'bg-theme-accent/10 text-theme-accent': canAfford(item) }"
              >
                <span v-if="shop.purchasing && shop.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span v-else-if="!canAfford(item) && prayers.karma < item.karma_cost">Not enough karma</span>
                <span v-else-if="shop.isAtLimit(item)">Limit reached</span>
                <span v-else-if="item.requires_building && !hasRequiredBuilding(item)">Requires {{ item.requires_building }}</span>
                <span v-else>Purchase</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Workforce Tab -->
      <div v-if="shop.activeTab === 'workforce'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Hire Workers to generate Gold. Each Worker consumes 1 Food per day - make sure you have enough Gardens!
          </p>
          <div class="flex items-center gap-2 text-xs text-theme-text-dim">
            <span class="text-amber-600">Gold/day: </span>
            <span class="font-semibold text-amber-600">{{ economy.netGoldPerDay }}</span>
            <span class="text-emerald-600 ml-2">Food net: </span>
            <span class="font-semibold" :class="economy.netFoodPerDay >= 0 ? 'text-emerald-600' : 'text-red-500'">{{ economy.netFoodPerDay }}</span>
          </div>
        </div>

        <div v-if="shop.loading && shop.workforceItems.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading workers...</div>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="item in shop.workforceItems"
            :key="item.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
            :class="{ 'opacity-60': !canAfford(item) }"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-12 w-12 items-center justify-center rounded-2xl border border-amber-500/20 bg-amber-50/55 text-2xl shadow-[0_10px_20px_rgba(213,154,23,0.12)] backdrop-blur-sm">
                  {{ buildingIcon(item.emoji_icon) }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ item.karma_cost }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-theme-text-dim">{{ item.description }}</p>

              <div class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div class="flex items-center gap-1">
                  <span class="text-amber-600">+</span>
                  <span>{{ buildingProduction('worker', 'gold_per_day') }} gold/day</span>
                </div>
                <div class="flex items-center gap-1">
                  <span class="text-red-500">-</span>
                  <span>{{ buildingUpkeep('worker', 'food_consumption_per_day') }} food consumed/day</span>
                </div>
              </div>

              <button
                @click="handlePurchase(item)"
                :disabled="!canAfford(item) || shop.purchasing"
                class="btn-secondary w-full py-2 text-sm disabled:opacity-40 disabled:cursor-not-allowed"
                :class="{ 'bg-theme-accent/10 text-theme-accent': canAfford(item) }"
              >
                <span v-if="shop.purchasing && shop.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span v-else-if="!canAfford(item) && prayers.karma < item.karma_cost">Not enough karma</span>
                <span v-else>Purchase</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Infrastructure Tab (Prayer Slots) -->
      <div v-if="shop.activeTab === 'infrastructure'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Purchase additional Prayer Slots to pray multiple prayers simultaneously. Each slot also grants +100 Devotion per day.
          </p>
          <div class="flex items-center gap-2 text-xs text-theme-text-dim">
            <span class="font-semibold text-theme-accent">{{ prayers.maxPrayerSlots }}</span>
            <span>current slots</span>
          </div>
        </div>

        <div v-if="shop.loading && shop.infrastructureItems.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading slots...</div>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="item in shop.infrastructureItems"
            :key="item.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
            :class="{ 'opacity-60': !canAfford(item) }"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-12 w-12 items-center justify-center rounded-2xl border border-theme-accent/20 bg-white/55 text-2xl shadow-[0_10px_20px_rgba(213,154,23,0.12)] backdrop-blur-sm">
                  {{ buildingIcon(item.emoji_icon) }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ item.karma_cost }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-theme-text-dim">{{ item.description }}</p>

              <div class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div class="flex items-center gap-1">
                  <span>+{{ item.effect_data?.slots_to_add || 1 }} prayer slot</span>
                </div>
                <div class="flex items-center gap-1">
                  <span class="text-theme-accent">+</span>
                  <span>{{ item.effect_data?.daily_devotion_bonus || 100 }} Devotion/day</span>
                </div>
              </div>

              <button
                @click="handlePurchase(item)"
                :disabled="!canAfford(item) || shop.purchasing"
                class="btn-secondary w-full py-2 text-sm disabled:opacity-40 disabled:cursor-not-allowed"
                :class="{ 'bg-theme-accent/10 text-theme-accent': canAfford(item) }"
              >
                <span v-if="shop.purchasing && shop.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span v-else-if="!canAfford(item) && prayers.karma < item.karma_cost">Not enough karma</span>
                <span v-else>Purchase</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Blessings Tab (existing) -->
      <div v-if="shop.activeTab === 'blessings'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Bless prayers in the Akashic Records with divine emojis. Each blessing grants karma to the receiver.
          </p>
        </div>

        <div v-if="blessings.loading && blessings.blessingTypes.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading blessings...</div>
          <p>Loading blessings...</p>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          <div
            v-for="blessing in blessings.blessingTypes"
            :key="blessing.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-12 w-12 items-center justify-center rounded-2xl border border-theme-accent/20 bg-white/55 text-2xl shadow-[0_10px_20px_rgba(213,154,23,0.12)] backdrop-blur-sm">{{ blessing.emoji }}</span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ blessing.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ blessing.karma_cost }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-4 text-xs leading-relaxed text-theme-text-dim">{{ blessing.description }}</p>

              <div class="flex items-center gap-3 border-t border-theme-border/50 pt-3 text-[0.7rem] text-theme-text-muted">
                <div class="flex items-center gap-1">
                  <span class="text-theme-accent">Giver +{{ blessing.karma_to_giver }}</span>
                </div>
                <div class="flex items-center gap-1">
                  <span class="text-theme-accent">Receiver +{{ blessing.karma_to_receiver }}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="glass-panel glass-panel-soft glass-gloss border border-theme-border/50 p-4 text-center text-xs text-theme-text-muted">
          <p>To bless a prayer, navigate to the <span class="font-medium text-theme-accent">Akashic Records</span> and tap the Bless button on any prayer card.</p>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { computed, onMounted } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useBlessings } from '@/composables/useBlessings'
import { useKarmaShop } from '@/composables/useKarmaShop'
import { useEconomy } from '@/composables/useEconomy'

const prayers = usePrayers()
const blessings = useBlessings()
const shop = useKarmaShop()
const economy = useEconomy()

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
}

// Map emoji_icon keys to display characters
function buildingIcon(iconKey) {
  const icons = {
    temple: '\u269B',     // ⚛
    church: '\u26EA',     // ⛪
    garden: '\uD83C\uDF3E', // 🌾
    worker: '\u2692',     // ⚒
    shrine: '\u269B',     // ⚛
    'prayer-slot': '\u2726', // ✦
  }
  return icons[iconKey] || '\u2726'
}

// Get production rate for a building type from game config
function buildingProduction(buildingType, configKey) {
  const fullKey = `building.${buildingType}.${configKey}`
  const val = economy.gameConfig[fullKey]
  return val !== undefined ? Number(val) : 0
}

// Get upkeep cost for a building type from game config
function buildingUpkeep(buildingType, configKey) {
  const fullKey = `building.${buildingType}.${configKey}`
  const val = economy.gameConfig[fullKey]
  return val !== undefined ? Number(val) : 0
}

// Check if player can afford an item
function canAfford(item) {
  return shop.canPurchase(item)
}

// Check if player has required building for an item
function hasRequiredBuilding(item) {
  if (!item.requires_building) return true
  const counts = economy.buildingCounts
  return counts[item.requires_building] && counts[item.requires_building] > 0
}

// Handle purchase
async function handlePurchase(item) {
  try {
    await shop.purchaseItem(item.id)
  } catch (err) {
    // Error is already handled in the composable
  }
}

onMounted(async () => {
  await Promise.all([
    blessings.fetchBlessingTypes(),
    prayers.fetchProfile(),
    shop.fetchShopItems(),
    shop.fetchPlayerBuildings(),
    economy.fetchEconomy(),
    economy.fetchGameConfig(),
  ])
})
</script>

<style scoped>
.shop-header {
  position: relative;
  overflow: clip;
}

.shop-header::after {
  content: "";
  position: absolute;
  inset: auto 0 -1px 0;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(213, 154, 23, 0.28), transparent);
}

.shop-header-glow {
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