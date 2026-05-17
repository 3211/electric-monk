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
                <span class="text-blue-500">💧</span>
                <span>Mana: <span class="font-semibold text-blue-500">{{ economy.mana }}</span></span>
              </div>
              <div class="chip gap-2 px-3 py-2 text-xs text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span>💰</span>
                <span>Gold: <span class="font-semibold text-amber-600">{{ economy.gold }}</span></span>
              </div>
              <div class="chip gap-2 px-3 py-2 text-xs text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span class="text-emerald-600">🌾</span>
                <span>Food: <span class="font-semibold text-emerald-600">{{ economy.food }}</span></span>
              </div>
            </div>
          </div>

          <div class="segmented-shell self-start flex-wrap">
            <button
              @click="shop.activeTab = 'mana'"
              class="pill-tab"
              :class="shop.activeTab === 'mana' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              🕯️ Estates
            </button>
            <button
              @click="shop.activeTab = 'food'"
              class="pill-tab"
              :class="shop.activeTab === 'food' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              🍲 Farms
            </button>
            <button
              @click="shop.activeTab = 'workforce'"
              class="pill-tab"
              :class="shop.activeTab === 'workforce' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              🙏 Workers
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
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Mana Estates Tab -->
      <div v-if="shop.activeTab === 'mana'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Build Mana estates to generate Devotion energy. Higher tiers produce more but require the previous tier as a prerequisite. Prices increase with each purchase.
          </p>
          <div class="flex items-center gap-2 text-xs text-theme-text-dim">
            <span class="text-blue-500">💧</span>
            <span class="font-semibold text-blue-500">{{ economy.netManaPerDay }}/day</span>
          </div>
        </div>

        <div v-if="shop.loading && shop.manaItems.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading estates...</div>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
          <div
            v-for="item in shop.manaItems"
            :key="item.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
            :class="{
              'opacity-60': !canAfford(item),
              'ring-2 ring-amber-500/40': isOwned(item)
            }"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <!-- Tier badge -->
              <div class="mb-2 flex items-center justify-between">
                <span class="text-[0.65rem] font-bold uppercase tracking-wider text-theme-accent/70">Tier {{ item.sort_order - (shop.manaItems[0]?.sort_order || 0) + 1 }}</span>
                <span v-if="isOwned(item)" class="chip gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-emerald-600">
                  ×{{ ownedCount(item) }}
                </span>
              </div>

              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-14 w-14 items-center justify-center rounded-2xl border border-blue-400/20 bg-blue-50/55 text-3xl shadow-[0_10px_20px_rgba(59,130,246,0.12)] backdrop-blur-sm">
                  {{ item.emoji_icon }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ formatCost(item) }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-theme-text-dim">{{ item.description }}</p>

              <!-- Production Info -->
              <div v-if="item.effect_type === 'add_building'" class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div v-if="buildingProduction(item.effect_data.building_type, 'mana_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-blue-500">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'mana_per_day') }} mana/day each</span>
                </div>
                <div v-if="buildingUpkeep(item.effect_data.building_type, 'gold_upkeep_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-red-500">-</span>
                  <span>{{ buildingUpkeep(item.effect_data.building_type, 'gold_upkeep_per_day') }} gold upkeep/day each</span>
                </div>
              </div>

              <!-- Next cost preview for scaling items -->
              <div v-if="item.cost_scaling && isOwned(item)" class="mb-2 text-[0.65rem] text-theme-text-dim">
                Next: {{ formatNextCost(item) }} karma
              </div>

              <!-- Prerequisite indicator -->
              <div v-if="item.requires_building && !hasPrerequisite(item)" class="mb-3 flex items-center gap-1 text-[0.7rem] text-red-400">
                <span>🔒</span>
                <span>Requires {{ economy.buildingInfo[item.requires_building]?.name || item.requires_building }}</span>
              </div>

              <button
                @click="handlePurchase(item)"
                :disabled="!canAfford(item) || shop.purchasing"
                class="btn-secondary w-full py-2 text-sm disabled:opacity-40 disabled:cursor-not-allowed"
                :class="{ 'bg-theme-accent/10 text-theme-accent': canAfford(item) }"
              >
                <span v-if="shop.purchasing && shop.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span v-else-if="item.requires_building && !hasPrerequisite(item)">🔒 Requires {{ economy.buildingInfo[item.requires_building]?.name || item.requires_building }}</span>
                <span v-else-if="!canAfford(item) && prayers.karma < scaledCost(item)">Not enough karma</span>
                <span v-else>Purchase</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Food Estates Tab -->
      <div v-if="shop.activeTab === 'food'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Cultivate Food estates to sustain your workforce. Higher tiers produce more Food. Prices increase with each purchase.
          </p>
          <div class="flex items-center gap-2 text-xs text-theme-text-dim">
            <span class="text-emerald-600">🌾</span>
            <span class="font-semibold text-emerald-600">{{ economy.netFoodPerDay }}/day</span>
          </div>
        </div>

        <div v-if="shop.loading && shop.foodItems.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading farms...</div>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
          <div
            v-for="item in shop.foodItems"
            :key="item.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
            :class="{
              'opacity-60': !canAfford(item),
              'ring-2 ring-amber-500/40': isOwned(item)
            }"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-[0.65rem] font-bold uppercase tracking-wider text-theme-accent/70">Tier {{ item.sort_order - (shop.foodItems[0]?.sort_order || 0) + 1 }}</span>
                <span v-if="isOwned(item)" class="chip gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-emerald-600">
                  ×{{ ownedCount(item) }}
                </span>
              </div>

              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-14 w-14 items-center justify-center rounded-2xl border border-emerald-400/20 bg-emerald-50/55 text-3xl shadow-[0_10px_20px_rgba(16,185,129,0.12)] backdrop-blur-sm">
                  {{ item.emoji_icon }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ formatCost(item) }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-theme-text-dim">{{ item.description }}</p>

              <div v-if="item.effect_type === 'add_building'" class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div v-if="buildingProduction(item.effect_data.building_type, 'food_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-emerald-600">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'food_per_day') }} food/day each</span>
                </div>
              </div>

              <div v-if="item.cost_scaling && isOwned(item)" class="mb-2 text-[0.65rem] text-theme-text-dim">
                Next: {{ formatNextCost(item) }} karma
              </div>

              <div v-if="item.requires_building && !hasPrerequisite(item)" class="mb-3 flex items-center gap-1 text-[0.7rem] text-red-400">
                <span>🔒</span>
                <span>Requires {{ economy.buildingInfo[item.requires_building]?.name || item.requires_building }}</span>
              </div>

              <button
                @click="handlePurchase(item)"
                :disabled="!canAfford(item) || shop.purchasing"
                class="btn-secondary w-full py-2 text-sm disabled:opacity-40 disabled:cursor-not-allowed"
                :class="{ 'bg-theme-accent/10 text-theme-accent': canAfford(item) }"
              >
                <span v-if="shop.purchasing && shop.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span v-else-if="item.requires_building && !hasPrerequisite(item)">🔒 Requires {{ economy.buildingInfo[item.requires_building]?.name || item.requires_building }}</span>
                <span v-else-if="!canAfford(item) && prayers.karma < scaledCost(item)">Not enough karma</span>
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
            Recruit workers to generate Gold. Higher tiers produce more Gold but consume more Food. Prices increase with each purchase.
          </p>
          <div class="flex items-center gap-3 text-xs text-theme-text-dim">
            <span class="text-amber-600">💰</span>
            <span class="font-semibold text-amber-600">{{ economy.netGoldPerDay }} gold/day</span>
            <span class="text-emerald-600 ml-2">🌾</span>
            <span class="font-semibold" :class="economy.netFoodPerDay >= 0 ? 'text-emerald-600' : 'text-red-500'">{{ economy.netFoodPerDay }} food/day</span>
          </div>
        </div>

        <div v-if="shop.loading && shop.workforceItems.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">Loading workers...</div>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
          <div
            v-for="item in shop.workforceItems"
            :key="item.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
            :class="{
              'opacity-60': !canAfford(item),
              'ring-2 ring-amber-500/40': isOwned(item)
            }"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-[0.65rem] font-bold uppercase tracking-wider text-theme-accent/70">Tier {{ item.sort_order - (shop.workforceItems[0]?.sort_order || 0) + 1 }}</span>
                <span v-if="isOwned(item)" class="chip gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-amber-600">
                  ×{{ ownedCount(item) }}
                </span>
              </div>

              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-14 w-14 items-center justify-center rounded-2xl border border-amber-400/20 bg-amber-50/55 text-3xl shadow-[0_10px_20px_rgba(213,154,23,0.12)] backdrop-blur-sm">
                  {{ item.emoji_icon }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ formatCost(item) }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-theme-text-dim">{{ item.description }}</p>

              <div v-if="item.effect_type === 'add_building'" class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div v-if="buildingProduction(item.effect_data.building_type, 'gold_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-amber-600">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'gold_per_day') }} gold/day each</span>
                </div>
                <div v-if="buildingUpkeep(item.effect_data.building_type, 'food_consumption_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-red-500">-</span>
                  <span>{{ buildingUpkeep(item.effect_data.building_type, 'food_consumption_per_day') }} food consumed/day each</span>
                </div>
              </div>

              <div v-if="item.cost_scaling && isOwned(item)" class="mb-2 text-[0.65rem] text-theme-text-dim">
                Next: {{ formatNextCost(item) }} karma
              </div>

              <div v-if="item.requires_building && !hasPrerequisite(item)" class="mb-3 flex items-center gap-1 text-[0.7rem] text-red-400">
                <span>🔒</span>
                <span>Requires {{ economy.buildingInfo[item.requires_building]?.name || item.requires_building }}</span>
              </div>

              <button
                @click="handlePurchase(item)"
                :disabled="!canAfford(item) || shop.purchasing"
                class="btn-secondary w-full py-2 text-sm disabled:opacity-40 disabled:cursor-not-allowed"
                :class="{ 'bg-theme-accent/10 text-theme-accent': canAfford(item) }"
              >
                <span v-if="shop.purchasing && shop.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span v-else-if="item.requires_building && !hasPrerequisite(item)">🔒 Requires {{ economy.buildingInfo[item.requires_building]?.name || item.requires_building }}</span>
                <span v-else-if="!canAfford(item) && prayers.karma < scaledCost(item)">Not enough karma</span>
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

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
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
                  {{ item.emoji_icon }}
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

      <!-- Blessings Tab -->
      <div v-if="shop.activeTab === 'blessings'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Bless prayers in the Akashic Records to grant karma and <span class="font-medium text-theme-accent">Divine Shield</span> protection to both you and the prayer owner. Shields stack additively.
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

              <p class="mb-2 text-xs leading-relaxed text-theme-text-dim">{{ blessing.description }}</p>

              <div class="mb-3 flex items-center gap-1.5 rounded-md border border-blue-400/20 bg-blue-50/30 px-2.5 py-1.5 text-[0.7rem] text-blue-600">
                <span>🛡</span>
                <span class="font-medium">{{ formatShieldDuration(blessing) }}</span>
                <span class="text-blue-500/70">shield to both</span>
              </div>

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
import { useShop } from '@/composables/useShop'
import { useEconomy } from '@/composables/useEconomy'

const prayers = usePrayers()
const blessings = useBlessings()
const shop = useShop()
const economy = useEconomy()

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
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

// Calculate the scaled cost for an item (base * 1.15^owned)
function scaledCost(item) {
  return shop.scaledCost(item)
}

// Format shield duration for a blessing in human-readable form
function formatShieldDuration(blessing) {
  const minutes = blessings.getShieldMinutes(blessing)
  if (!minutes || minutes <= 0) return '0m'
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h > 0 && m > 0) return `${h}h ${m}m`
  if (h > 0) return `${h}h`
  return `${m}m`
}

// Format cost for display
function formatCost(item) {
  const cost = scaledCost(item)
  return cost.toLocaleString()
}

// Format next cost (cost after buying one more)
function formatNextCost(item) {
  if (!item.cost_scaling || !item.effect_data?.building_type) return ''
  const count = shop.ownedCount(item.effect_data.building_type)
  const multiplier = economy.gameConfig['shop.cost_scaling_multiplier'] || 1.15
  const nextCost = Math.floor(item.karma_cost * Math.pow(multiplier, count + 1))
  return nextCost.toLocaleString()
}

// Check if player can afford an item
function canAfford(item) {
  return shop.canPurchase(item)
}

// Check if player has the prerequisite building
function hasPrerequisite(item) {
  return shop.hasPrerequisite(item)
}

// Check if the player owns at least one of this building type
function isOwned(item) {
  if (!item.effect_data?.building_type) return false
  return shop.ownedCount(item.effect_data.building_type) > 0
}

// Get owned count for a building type
function ownedCount(item) {
  if (!item.effect_data?.building_type) return 0
  return shop.ownedCount(item.effect_data.building_type)
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