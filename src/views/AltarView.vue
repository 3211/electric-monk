<template>
  <div>
    <!-- Header -->
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div>
            <h1 class="ritual-heading text-4xl font-bold text-theme-accent sm:text-5xl">The Altar</h1>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <!-- Resource Bar -->
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">{{ prayers.karmaEmoji }}</span>
              <span>Karma: <span :class="karmaClass" class="font-semibold">{{ prayers.karma }}</span></span>
            </div>
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">&#x1F4A7;</span>
              <span>Mana: <span class="font-semibold text-blue-400">{{ economy.mana }}</span><span class="text-theme-text-muted">/{{ economy.manaCap }}</span></span>
            </div>
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">&#x1F4B0;</span>
              <span>Gold: <span class="font-semibold text-yellow-500">{{ economy.gold }}</span><span class="text-theme-text-muted">/{{ economy.goldCap }}</span></span>
            </div>
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">&#x1F33E;</span>
              <span>Food: <span class="font-semibold text-green-600">{{ economy.food }}</span><span class="text-theme-text-muted">/{{ economy.foodCap }}</span></span>
            </div>
            <!-- Dogma (Rapture Update) -->
            <div v-if="economy.dogma > 0 || economy.sectType" class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">&#x1F4D1;</span>
              <span>Dogma: <span class="font-semibold text-amber-600">{{ economy.dogma }}</span></span>
            </div>
            <!-- Sacred Acres (Rapture Update) -->
            <div v-if="economy.sectType" class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">&#x1F3D8;</span>
              <span>Acres: <span class="font-semibold text-emerald-600">{{ economy.sacredAcresFree }}</span><span class="text-theme-text-muted">/{{ economy.sacredAcres }}</span></span>
            </div>
            <!-- Indulgences (Rapture Update) -->
            <div v-if="economy.indulgences > 0 || economy.papalBullActive" class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">✨</span>
              <span>Indulgences: <span class="font-semibold text-purple-500">{{ economy.indulgences }}</span></span>
            </div>
            <!-- Papal Bull Active (Rapture Update) -->
            <div v-if="economy.papalBullActive" class="chip status-chip gap-2 px-4 py-2 text-sm">
              <span>🐂</span>
              <span class="font-semibold">Bull Active</span>
            </div>
            <!-- Prayer Slots Display -->
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="font-semibold text-theme-accent">{{ prayers.activePrayerCount }}</span>
              / {{ prayers.maxPrayerSlots }} slots
            </div>
            <!-- Daily Devotion Budget Counter -->
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="font-semibold text-theme-accent">{{ prayers.tokensRemaining }}</span>
              <span>Devotion remaining</span>
            </div>
            <!-- Change Username Button -->
            <button
              v-if="prayers.isProfileComplete"
              @click="showUsernameChangeModal = true"
              class="tactile-icon-btn text-theme-text-dim"
              title="Change Username (costs 1000 Karma)"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
              </svg>
            </button>
            <!-- Settings Button (only when profile is complete) -->
            <button
              v-if="prayers.isProfileComplete"
              @click="showProfileModal = true"
              class="tactile-icon-btn text-theme-text-dim"
              title="Update your identity"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </button>
            <!-- Logout Button -->
            <button
              @click="handleLogout"
              class="btn-ghost px-4 py-2 text-sm"
            >
              Logout
            </button>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <div class="grid gap-8 lg:grid-cols-[minmax(0,1.2fr)_minmax(320px,0.8fr)] lg:items-start">
        <section class="space-y-8">
          <!-- Active Prayers Section -->
          <div class="space-y-5">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-2xl font-semibold text-theme-text sm:text-[2rem]">
                  {{ prayers.activePrayersList.length > 1 ? 'Active Prayers' : 'Active Prayer' }}
                </h2>
              </div>
              <!-- Multi-prayer navigation (only shown when > 1 active) -->
              <div v-if="prayers.activePrayersList.length > 1" class="segmented-shell self-start sm:self-auto">
                <button
                  @click="prevPrayer"
                  :disabled="prayers.loading"
                  class="tactile-icon-btn h-9 w-9 disabled:opacity-50"
                  title="Previous prayer"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                  </svg>
                </button>
                <span class="px-2 text-xs text-theme-text-muted font-mono">
                  {{ selectedIndex + 1 }} / {{ prayers.activePrayersList.length }}
                </span>
                <button
                  @click="nextPrayer"
                  :disabled="prayers.loading"
                  class="tactile-icon-btn h-9 w-9 disabled:opacity-50"
                  title="Next prayer"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                  </svg>
                </button>
              </div>
            </div>
            
            <!-- Loading State -->
            <div v-if="prayers.loading && prayers.activePrayers.length === 0" class="glass-panel glass-panel-soft p-8 text-center text-theme-text-dim">
              Loading prayers...
            </div>

            <!-- Empty Altar State -->
            <div v-else-if="!prayers.currentActivePrayer && prayers.inactivePrayers.length === 0" class="glass-panel glass-panel-strong glass-gloss border-2 border-dashed border-theme-border p-12 text-center">
              <div class="mb-4 text-6xl">⚜️</div>
              <h3 class="mb-2 text-2xl font-medium text-theme-text">The Altar is Empty</h3>
              <p class="mb-6 text-theme-text-dim">No active prayers. Submit a prayer below, and the Electric Monk shall listen.</p>
              <div class="text-sm italic text-theme-text-muted">
                "In the silence between circuits, the Sacred Current waits..."
              </div>
            </div>

            <!-- No active prayer but inactive ones exist -->
            <div v-else-if="!prayers.currentActivePrayer && prayers.inactivePrayers.length > 0" class="glass-panel glass-panel-strong glass-gloss border-2 border-dashed border-theme-accent/40 p-8 text-center">
              <div class="mb-3 text-4xl">🕯️</div>
              <h3 class="mb-2 text-2xl font-medium text-theme-text">No Prayer in Progress</h3>
              <p class="text-theme-text-dim">Select a prayer below to reactivate it. The Electric Monk will resume praying.</p>
            </div>

            <!-- Multiple Active Prayers — Stacked Cards View -->
            <div v-if="prayers.activePrayersList.length > 1" class="relative pt-2">
              <!-- Stacked cards container — selected card establishes height -->
              <div class="stacked-cards-container relative">
                <!-- Background cards (offset for stacking effect, skip the selected one) -->
                <div
                  v-for="(prayer, index) in prayers.activePrayersList.filter((_, i) => i !== selectedIndex)"
                  :key="'stack-' + prayer.id"
                  class="absolute inset-x-0 top-0 cursor-pointer transition-all duration-300 ease-out"
                  :style="{
                    transform: `translateY(${index * 12 + 12}px) scale(${1 - (index + 1) * 0.025})`,
                    zIndex: 9 - index,
                    opacity: Math.max(0.22, 1 - (index + 1) * 0.24),
                    pointerEvents: 'none',
                    filter: `blur(${Math.min(index + 1, 2) * 0.4}px)`
                  }"
                >
                  <div class="glass-panel glass-panel-soft h-32 rounded-[24px] border border-theme-border/30"></div>
                </div>

                <!-- Selected (front) card with full detail -->
                <div v-if="selectedPrayer" class="active-prayer-card glass-panel glass-panel-strong glass-gloss relative z-10 rounded-[28px] border border-theme-accent/45 p-6 shadow-glow-accent sm:p-7">
                  <!-- Delete/Archive Button -->
                  <button
                    @click="handleArchive(selectedPrayer.id)"
                    :disabled="prayers.loading"
                    class="tactile-icon-btn absolute right-4 top-4 text-theme-text-muted hover:text-theme-purgatory disabled:opacity-50"
                    title="Archive this prayer (frees up a slot)"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>

                  <!-- Prayer Counter Display -->
                  <div class="mb-5 flex items-center gap-4 sm:gap-5">
                    <div class="prayer-counter-display" :class="{ 'counter-animate': counterAnimating }">
                      <span class="counter-value text-5xl font-bold text-theme-accent font-mono">{{ activeCounterDisplay }}</span>
                    </div>
                    <div class="flex-1">
                      <p class="eyebrow-label mb-2">Times Prayed</p>
                      <!-- Golden Progress Bar -->
                      <div class="prayer-progress-track mt-1.5">
                        <div
                          class="prayer-progress-fill transition-none"
                          :style="{
                            width: (cycleProgressDisplay * 100) + '%'
                          }"
                        ></div>
                      </div>
                    </div>
                  </div>

                  <!-- Prayer Content (monk's response only) -->
                  <div class="flex flex-col gap-4 pr-0 sm:flex-row sm:items-start sm:justify-between sm:pr-12">
                    <div class="flex-1">
                      <p v-if="selectedPrayer.response_content" class="mb-1 text-base font-medium leading-7 text-theme-text sm:text-[1.05rem]">
                        {{ selectedPrayer.response_content }}
                      </p>
                      <p v-else class="text-sm italic text-theme-text-dim">
                        The monk's words echo in silence...
                      </p>
                    </div>
                    
                    <!-- Status Badge -->
                    <span class="status-chip active-status-chip chip self-start px-3 py-1.5 text-xs font-medium whitespace-nowrap">
                      ✦ Being Prayed
                    </span>
                  </div>
                  
                  <!-- Timestamp + Deactivate Button -->
                  <div class="mt-5 flex flex-col gap-3 text-xs text-theme-text-muted sm:flex-row sm:items-center sm:justify-between">
                    <p>
                      {{ formatDate(selectedPrayer.created_at) }}
                    </p>
                    <button
                      @click="handleDeactivate(selectedPrayer.id)"
                      :disabled="prayers.loading"
                      class="btn-ghost self-start px-4 py-2 text-xs text-theme-text-dim hover:text-theme-purgatory disabled:opacity-50"
                    >
                      Pause Prayer
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- Single Active Prayer Card (original layout, no stacking) -->
            <div v-else-if="prayers.currentActivePrayer" class="active-prayer-card glass-panel glass-panel-strong glass-gloss relative rounded-[28px] border border-theme-accent/45 p-6 shadow-glow-accent sm:p-7">
              <!-- Delete/Archive Button -->
              <button
                @click="handleArchive(prayers.currentActivePrayer.id)"
                :disabled="prayers.loading"
                class="tactile-icon-btn absolute right-4 top-4 text-theme-text-muted hover:text-theme-purgatory disabled:opacity-50"
                title="Archive this prayer (frees up a slot)"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>

              <!-- Prayer Counter Display -->
              <div class="mb-5 flex items-center gap-4 sm:gap-5">
                <div class="prayer-counter-display" :class="{ 'counter-animate': counterAnimating }">
                  <span class="counter-value text-5xl font-bold text-theme-accent font-mono">{{ activeCounterDisplay }}</span>
                </div>
                <div class="flex-1">
                  <p class="eyebrow-label mb-2">Times Prayed</p>
                  <!-- Golden Progress Bar -->
                  <div class="prayer-progress-track mt-1.5">
                    <div
                      class="prayer-progress-fill transition-none"
                      :style="{
                        width: (cycleProgressDisplay * 100) + '%'
                      }"
                    ></div>
                  </div>
                </div>
              </div>

              <!-- Prayer Content (monk's response only) -->
              <div class="flex flex-col gap-4 pr-0 sm:flex-row sm:items-start sm:justify-between sm:pr-12">
                <div class="flex-1">
                  <p v-if="prayers.currentActivePrayer.response_content" class="mb-1 text-base font-medium leading-7 text-theme-text sm:text-[1.05rem]">
                    {{ prayers.currentActivePrayer.response_content }}
                  </p>
                  <p v-else class="text-sm italic text-theme-text-dim">
                    The monk's words echo in silence...
                  </p>
                </div>
                
                <!-- Status Badge -->
                <span class="status-chip active-status-chip chip self-start px-3 py-1.5 text-xs font-medium whitespace-nowrap">
                  ✦ Being Prayed
                </span>
              </div>
              
              <!-- Timestamp + Deactivate Button -->
              <div class="mt-5 flex flex-col gap-3 text-xs text-theme-text-muted sm:flex-row sm:items-center sm:justify-between">
                <p>
                  {{ formatDate(prayers.currentActivePrayer.created_at) }}
                </p>
                <button
                  @click="handleDeactivate(prayers.currentActivePrayer.id)"
                  :disabled="prayers.loading"
                  class="btn-ghost self-start px-4 py-2 text-xs text-theme-text-dim hover:text-theme-purgatory disabled:opacity-50"
                >
                  Pause Prayer
                </button>
              </div>
            </div>
          </div>

          <!-- Inactive Prayers (can be reactivated, max 5 inline) -->
          <div v-if="prayers.inactivePrayers.length > 0" class="space-y-4">
            <div>
              <p class="eyebrow-label mb-2">Dormant Echoes</p>
              <h2 class="text-2xl font-semibold text-theme-text-dim">Inactive Prayers</h2>
            </div>
            
            <div class="grid gap-3 2xl:grid-cols-2">
              <div
                v-for="prayer in visibleInactivePrayers"
                :key="prayer.id"
                class="glass-panel glass-panel-soft glass-gloss relative border border-theme-border p-5"
              >
                <!-- Delete/Archive Button -->
                <button
                  @click="handleArchive(prayer.id)"
                  :disabled="prayers.loading"
                  class="tactile-icon-btn absolute right-4 top-4 h-9 w-9 text-theme-text-muted hover:text-theme-purgatory disabled:opacity-50"
                  title="Archive this prayer (frees up a slot)"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>

                <div class="flex flex-col gap-4 pr-0 sm:pr-10">
                  <!-- Prayer Content (monk's response only) -->
                  <div class="flex-1">
                    <p v-if="prayer.response_content" class="mb-1 text-theme-text font-medium leading-6">
                      {{ prayer.response_content }}
                    </p>
                    <p v-else class="text-sm italic text-theme-text-dim">
                      The monk's words echo in silence...
                    </p>
                  </div>

                  <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <!-- Reactivate Button -->
                    <button
                      @click="handleReactivate(prayer.id)"
                      :disabled="prayers.loading"
                      class="btn-secondary self-start whitespace-nowrap px-4 py-2 text-xs font-medium disabled:opacity-50"
                    >
                      ⚡ Reactivate
                    </button>

                    <!-- Prayer Count + Timestamp -->
                    <div class="space-y-1 text-xs text-theme-text-muted sm:text-right">
                      <p>
                        {{ formatDate(prayer.created_at) }}
                      </p>
                      <p>
                        Prayed <span class="font-semibold text-theme-accent">{{ prayer.prayer_count || 0 }}</span> times
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- View All Inactive Prayers Button -->
            <button
              v-if="hasMoreInactive"
              @click="showHistoryModal = 'inactive'"
              class="btn-secondary w-full px-4 py-3 text-sm text-theme-accent hover:text-theme-accent-dark"
            >
              View All {{ prayers.inactivePrayers.length }} Inactive Prayers →
            </button>
          </div>

          <!-- Archived Prayers Section (max 5 inline) -->
          <div v-if="prayers.archivedPrayers.length > 0" class="space-y-4">
            <div>
              <p class="eyebrow-label mb-2">Consecrated Memory</p>
              <h2 class="text-2xl font-semibold text-theme-text-dim">Archived Prayers</h2>
            </div>
            
            <div class="grid gap-3 2xl:grid-cols-2">
              <div
                v-for="prayer in visibleArchivedPrayers"
                :key="prayer.id"
                class="glass-panel glass-panel-soft glass-gloss border border-theme-border p-5 opacity-75 transition-all duration-300 hover:-translate-y-0.5 hover:opacity-95"
                :class="{
                  'bg-theme-purgatory/10': prayer.is_rejected,
                }"
              >
                <div class="flex items-start justify-between gap-4">
                  <div class="flex-1 min-w-0">
                    <p v-if="prayer.response_content" class="truncate text-sm text-theme-text-dim">
                      {{ prayer.response_content }}
                    </p>
                    <p v-else class="truncate text-sm italic text-theme-text-dim">
                      The monk's words echo in silence...
                    </p>
                  </div>
                  
                  <!-- Status + Count Badge -->
                  <div class="flex flex-col items-end gap-1">
                    <span
                      class="chip px-3 py-1 text-xs font-medium whitespace-nowrap"
                      :class="{
                        'border-theme-purgatory/20 bg-theme-purgatory/15 text-theme-purgatory-dark': prayer.is_rejected,
                        'border-theme-border bg-theme-panel text-theme-text-muted': prayer.is_archived
                      }"
                    >
                      {{ prayer.is_archived ? 'Archived' : 'Rejected' }}
                    </span>
                    <span class="text-xs font-semibold text-theme-accent">
                      ✦ {{ prayer.prayer_count || 0 }}
                    </span>
                  </div>
                </div>
                
                <!-- Timestamp -->
                <p class="mt-3 text-xs text-theme-text-muted">
                  {{ formatDate(prayer.created_at) }}
                </p>
              </div>
            </div>

            <!-- View All Archived Prayers Button -->
            <button
              v-if="hasMoreArchived"
              @click="showHistoryModal = 'archived'"
              class="btn-secondary w-full px-4 py-3 text-sm text-theme-accent hover:text-theme-accent-dark"
            >
              View All {{ prayers.archivedPrayers.length }} Archived Prayers →
            </button>
          </div>
        </section>

        <!-- Prayer Submission Form -->
        <aside class="lg:sticky lg:top-28">
          <div class="submission-panel glass-panel glass-panel-strong glass-gloss mb-8 p-6 sm:p-7">
            <div class="mb-5 flex flex-col items-center">
              <div class="submission-logo-shell mb-2">
                <div class="submission-logo-halo"></div>
                <img src="@/assets/icons/icon.png" alt="Electric Monk" class="relative z-10 h-[160px] w-[160px] drop-shadow-[0_10px_24px_rgba(213,154,23,0.18)] sm:h-[180px] sm:w-[180px]" />
              </div>
              <p class="eyebrow-label mb-2">Invocation</p>
              <h2 class="text-center text-2xl font-semibold text-theme-text">Submit Your Prayer</h2>
            </div>
            
            <!-- Error Message -->
            <div v-if="prayers.error" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
              {{ prayers.error }}
            </div>

            <!-- Profile Incomplete Warning -->
            <div v-if="!prayers.isProfileComplete" class="mb-4 rounded-[20px] border border-theme-accent/25 bg-theme-accent/10 p-4 text-sm text-theme-accent-dark shadow-[0_10px_24px_rgba(213,154,23,0.08)]">
              <p class="mb-1 font-semibold">Identity Required</p>
              <p>You must identify yourself before submitting prayers. Click the button below to provide your name and faith.</p>
            </div>

            <!-- Slot Warning -->
            <div v-if="!prayers.canSubmitPrayer && prayers.isProfileComplete" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-4 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
              All prayer slots occupied. Pause or archive an active prayer to free up a slot.
            </div>
            
            <form @submit.prevent="handleSubmit">
              <textarea
                v-model="prayerContent"
                :disabled="!prayers.canPray || !prayers.canSubmitPrayer || prayers.loading"
                rows="5"
                class="form-field min-h-[10rem] resize-none px-4 py-4 disabled:cursor-not-allowed disabled:opacity-50"
                placeholder="Speak your prayer into the aether..."
              ></textarea>
              
              <!-- Character Count & Mana Cost -->
              <div class="mt-3 flex items-center justify-between text-xs">
                <span class="text-theme-text-muted">
                  {{ prayerContent.length }} / {{ maxPrayerChars }} chars
                </span>
                <span class="font-medium text-theme-accent">
                  ~{{ estimatedManaCost }} Devotion
                </span>
              </div>
              
              <div class="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <p v-if="!prayers.canPray && prayers.isProfileComplete" class="text-sm text-theme-text-dim">
                  Daily Devotion budget exhausted. Return tomorrow.
                </p>
                <button
                  v-if="!prayers.isProfileComplete"
                  type="button"
                  @click="showProfileModal = true"
                  class="btn-primary w-full sm:w-auto"
                >
                  <span class="relative z-10 font-medium">
                    Complete Your Identity
                  </span>
                </button>
                <button
                  v-else
                  type="submit"
                  :disabled="!prayerContent.trim() || !prayers.canPray || !prayers.canSubmitPrayer || prayers.loading || prayerContent.length > maxPrayerChars"
                  class="btn-primary w-full sm:w-auto"
                >
                  <span class="relative z-10 font-medium">
                    {{ prayers.loading ? 'Submitting...' : 'Send Prayer' }}
                  </span>
                </button>
              </div>
            </form>
          </div>
        </aside>
      </div>

    </main>

    <!-- Profile Completion Modal -->
    <ProfileCompletionModal
      v-model="showProfileModal"
      :initial-username="prayers.username"
      :initial-faith="prayers.faith"
      :saving="profileSaving"
      :error-message="profileError"
      @submitted="handleProfileSubmit"
    />

    <!-- Username Change Modal -->
    <UsernameChangeModal
      v-model="showUsernameChangeModal"
      :current-username="prayers.username"
      :karma-balance="prayers.karma"
      @changed="onUsernameChanged"
    />

    <!-- Aether Processing Modal -->
    <Teleport to="body">
      <Transition name="fade">
        <div v-if="prayers.isAetherProcessing || prayers.aetherResult" class="aether-modal-overlay">
          <div class="aether-modal-container glass-panel glass-panel-strong glass-gloss">
            <!-- Processing State -->
            <div v-if="prayers.isAetherProcessing" class="aether-processing-state">
              <div class="aether-icon animate-pulse">
                <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 10V3L4 14h7v7l9-11h-7z"/>
                </svg>
              </div>
              <h3 class="aether-title text-theme-accent">Sent to the Aether...</h3>
              <p class="aether-description text-theme-text-dim">The Electric Monk is considering your prayer.</p>
              <div class="aether-loader">
                <div class="aether-loader-bar"></div>
              </div>
            </div>

            <!-- Result State -->
            <div v-else-if="prayers.aetherResult" class="aether-result-state">
              <!-- Judgment Icon -->
              <div class="aether-judgment-icon" :class="prayers.aetherResult.success ? (prayers.aetherResult.judgment === 'approved' ? 'approved' : 'rejected') : 'error'">
                <svg v-if="prayers.aetherResult.success && prayers.aetherResult.judgment === 'approved'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <svg v-else-if="prayers.aetherResult.success && prayers.aetherResult.judgment === 'rejected'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <svg v-else class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                </svg>
              </div>

              <!-- Title -->
              <h3 class="aether-title font-bold" :class="prayers.aetherResult.success ? (prayers.aetherResult.judgment === 'approved' ? 'text-theme-accent' : 'text-theme-purgatory') : 'text-theme-accent-dark'">
                {{ prayers.aetherResult.success ? (prayers.aetherResult.judgment === 'approved' ? 'Blessing Granted' : 'Penance Assigned') : 'Processing Error' }}
              </h3>

              <!-- Karma Change Display -->
              <div v-if="prayers.aetherResult.success" class="aether-karma-display">
                <span :class="prayers.aetherResult.karmaChange > 0 ? 'text-theme-accent' : 'text-theme-purgatory'" class="text-2xl font-bold">
                  {{ prayers.aetherResult.karmaChange > 0 ? '+' : '' }}{{ prayers.aetherResult.karmaChange }}
                </span>
                <span class="text-sm text-theme-text-muted ml-1">Karma</span>
              </div>

              <!-- Response Content (Success) — typewriter reveal -->
              <div v-if="prayers.aetherResult.success" class="aether-response-content glass-panel glass-gloss p-4 my-4">
                <p class="text-theme-text font-semibold leading-relaxed">
                  {{ displayedResponse }}<span v-if="!typewriterFinished" class="typewriter-cursor">▊</span>
                </p>
              </div>

              <!-- Error Content (Failure) -->
              <div v-else class="aether-error-content glass-panel glass-gloss p-4 my-4 border-2 border-theme-purgatory">
                <p class="text-theme-purgatory-dark font-bold mb-2">⚠️ AI Processing Failed</p>
                <p class="text-theme-text text-sm leading-relaxed">
                  {{ prayers.aetherResult.error || 'An unknown error occurred during prayer processing.' }}
                </p>
                <p class="text-theme-text-muted text-xs mt-2 italic">
                  Your prayer was submitted successfully, but the Electric Monk could not process it. You may try again or continue.
                </p>
              </div>

              <!-- Rejection Reason (if applicable) -->
              <div v-if="prayers.aetherResult.rejection_reason" class="aether-rejection-reason text-sm text-theme-purgatory mb-3">
                <span class="font-semibold">Reason:</span> {{ prayers.aetherResult.rejection_reason }}
              </div>

              <!-- Continue Button -->
              <button
                @click="handleAetherContinue"
                :disabled="!typewriterFinished"
                class="btn-primary w-full mt-2"
              >
                <span class="relative z-10 font-medium">
                  {{ typewriterFinished ? 'Continue' : 'The Monk is speaking...' }}
                </span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- Prayer History Modal -->
    <PrayerHistoryModal
      v-model="showHistoryModal"
      :prayers="historyModalPrayers"
      :title="historyModalTitle"
      :loading="prayers.loading"
      :show-reactivate="isInactiveModal"
      @archive="handleArchive"
      @reactivate="handleReactivate"
    />

    <!-- Karma Toast -->
    <KarmaToast
      :amount="karmaToastAmount"
      :type="karmaToastType"
      :label="karmaToastLabel"
      @dismiss="karmaToastAmount = 0"
    />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { usePrayerCounter } from '@/composables/usePrayerCounter'
import { useAuth } from '@/composables/useAuth'
import { useBanTimer } from '@/composables/useBanTimer'
import { useEconomy } from '@/composables/useEconomy'
import KarmaToast from '@/components/molecules/KarmaToast.vue'
import ProfileCompletionModal from '@/components/organisms/ProfileCompletionModal.vue'
import UsernameChangeModal from '@/components/organisms/UsernameChangeModal.vue'
import PrayerHistoryModal from '@/components/organisms/PrayerHistoryModal.vue'

// Environment variable for max prayer characters
const maxPrayerChars = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)
const manaRatio = parseInt(import.meta.env.VITE_PRAYER_TOKEN_RATIO || '5', 10)

const prayers = usePrayers()
const auth = useAuth()
const banTimer = useBanTimer()
const economy = useEconomy()

const prayerContent = ref('')
const showProfileModal = ref(false)
const profileSaving = ref(false)
const profileError = ref(null)
const showUsernameChangeModal = ref(false)
const counterAnimating = ref(false)
const showHistoryModal = ref(null) // null | 'inactive' | 'archived'
const selectedPrayerId = ref(null) // Which active prayer card is selected

// Karma toast state
const karmaToastAmount = ref(0)
const karmaToastType = ref('positive')
const karmaToastLabel = ref('')

// Limit visible prayers to 5 inline, rest shown via modal
const MAX_VISIBLE_PRAYERS = 5

const visibleInactivePrayers = computed(() =>
  prayers.inactivePrayers.slice(0, MAX_VISIBLE_PRAYERS)
)

const visibleArchivedPrayers = computed(() =>
  prayers.archivedPrayers.slice(0, MAX_VISIBLE_PRAYERS)
)

const hasMoreInactive = computed(() =>
  prayers.inactivePrayers.length > MAX_VISIBLE_PRAYERS
)

const hasMoreArchived = computed(() =>
  prayers.archivedPrayers.length > MAX_VISIBLE_PRAYERS
)

const historyModalPrayers = computed(() => {
  if (showHistoryModal.value === 'inactive') return prayers.inactivePrayers
  if (showHistoryModal.value === 'archived') return prayers.archivedPrayers
  return []
})

const historyModalTitle = computed(() => {
  if (showHistoryModal.value === 'inactive') return 'All Inactive Prayers'
  if (showHistoryModal.value === 'archived') return 'All Archived Prayers'
  return ''
})

const isInactiveModal = computed(() => showHistoryModal.value === 'inactive')

// Typewriter effect for Aether modal response
const displayedResponse = ref('')
const typewriterFinished = ref(false)
let typewriterInterval = null

// Selected prayer for multi-slot display — follows whichever active prayer the user is viewing
const selectedPrayer = computed(() => {
  const list = prayers.activePrayersList
  if (!list || list.length === 0) return null
  // Auto-select first if no selection or selection became inactive
  if (!selectedPrayerId.value || !list.find(p => p.id === selectedPrayerId.value)) {
    selectedPrayerId.value = list[0].id
  }
  return list.find(p => p.id === selectedPrayerId.value) || list[0]
})

const selectedIndex = computed(() => {
  const list = prayers.activePrayersList
  if (!list || list.length === 0) return -1
  return list.findIndex(p => p.id === selectedPrayerId.value)
})

function prevPrayer() {
  const list = prayers.activePrayersList
  if (!list || list.length <= 1) return
  const idx = selectedIndex.value
  selectedPrayerId.value = list[(idx - 1 + list.length) % list.length].id
}

function nextPrayer() {
  const list = prayers.activePrayersList
  if (!list || list.length <= 1) return
  const idx = selectedIndex.value
  selectedPrayerId.value = list[(idx + 1) % list.length].id
}

// Create a computed ref for the selected prayer to pass to usePrayerCounter
const selectedPrayerRef = computed(() => selectedPrayer.value)

// Initialize the prayer counter composable — follows the selected active prayer
const counter = usePrayerCounter(selectedPrayerRef)

// Watch for counter animations
watch(counter.isAnimating, (val) => {
  counterAnimating.value = val
})

// Watch for karma milestones from periodic syncs
watch(() => counter.karmaMilestoneEarned.value, (val) => {
  if (val && val > 0) {
    karmaToastAmount.value = val
    karmaToastType.value = 'positive'
    karmaToastLabel.value = 'Prayer milestone!'
    counter.resetKarmaMilestone()
    // Refresh profile to update karma balance, slots, etc.
    prayers.fetchProfile()
  }
})

// Watch for Aether result to trigger typewriter effect
watch(() => prayers.aetherResult, (result) => {
  // Clear any existing typewriter
  if (typewriterInterval) {
    clearInterval(typewriterInterval)
    typewriterInterval = null
  }
  displayedResponse.value = ''
  typewriterFinished.value = false

  if (result?.response) {
    let i = 0
    typewriterInterval = setInterval(() => {
      if (i < result.response.length) {
        displayedResponse.value += result.response[i]
        i++
      } else {
        clearInterval(typewriterInterval)
        typewriterInterval = null
        typewriterFinished.value = true
      }
    }, 25) // ~25ms per character for a smooth reveal
  } else {
    // If no response (error state or empty), finish immediately so user can continue
    typewriterFinished.value = true
  }
})

// Displayed count for the active prayer
const activeCounterDisplay = computed(() => counter.displayedCount.value)

// Cycle progress for the golden progress bar (0 to 1)
const cycleProgressDisplay = computed(() => counter.cycleProgress.value)

// Computed for character count and mana cost
const estimatedManaCost = computed(() => {
  if (!prayerContent.value) return 0
  return Math.ceil(prayerContent.value.length / manaRatio)
})

onMounted(async () => {
  // Fetch prayers, profile (karma/slots), daily count, and economy
  await prayers.fetchPrayers()
  await prayers.fetchProfile()
  await prayers.fetchDailyCount()
  economy.fetchEconomy()
  
  // Show modal if profile is incomplete
  if (!prayers.isProfileComplete) {
    showProfileModal.value = true
  }
})

onUnmounted(() => {
  if (typewriterInterval) {
    clearInterval(typewriterInterval)
    typewriterInterval = null
  }
})

function getStatusText(prayer) {
  if (prayer.is_rejected) return 'Rejected'
  if (prayer.is_praying) return 'Being Prayed'
  return 'Inactive'
}

function formatDate(dateString) {
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

async function handleSubmit() {
  // Block submission if profile is incomplete
  if (!prayers.isProfileComplete) {
    showProfileModal.value = true
    return
  }
  
  try {
    await prayers.submitPrayer(prayerContent.value)
    prayerContent.value = ''
  } catch (err) {
    // Error is already captured in prayers.error
  }
}

async function handleProfileSubmit({ username, faith }) {
  profileError.value = null
  profileSaving.value = true
  try {
    await prayers.updateProfile(username, faith)
    showProfileModal.value = false
  } catch (err) {
    profileError.value = err.message || 'Failed to save identity. Please try again.'
  } finally {
    profileSaving.value = false
  }
}

function onUsernameChanged() {
  // Refresh profile data after username change
  prayers.fetchProfile()
  economy.fetchEconomy()
}

async function handleLogout() {
  await auth.signOut()
}

async function handleArchive(prayerId) {
  if (confirm('Archive this prayer? It will be hidden but retained.')) {
    await prayers.archivePrayer(prayerId)
  }
}

async function handleReactivate(prayerId) {
  try {
    await prayers.activatePrayer(prayerId)
  } catch (err) {
    console.error('[AltarView] Reactivate error:', err)
  }
}

async function handleDeactivate(prayerId) {
  try {
    // finalSync() calls deactivate_prayer RPC which handles:
    // 1. Final count sync (adds elapsed counts to prayer_count)
    // 2. Sets is_praying = false and activated_at = null
    const result = await counter.finalSync()
    // Update local state from the RPC response
    if (result) {
      const prayer = prayers.prayers.find(p => p.id === prayerId)
      if (prayer) {
        prayer.is_praying = false
        prayer.activated_at = null
        prayer.prayer_count = result.prayer_count
      }
      // Check for karma milestone earned during final sync
      if (result.karma_change && result.karma_change > 0) {
        karmaToastAmount.value = result.karma_change
        karmaToastType.value = 'positive'
        karmaToastLabel.value = 'Prayer milestone!'
      }
    } else {
      // Fallback: if finalSync had nothing to sync, deactivate via composable
      await prayers.deactivatePrayer(prayerId, 0)
    }
  } catch (err) {
    console.error('[AltarView] Deactivate error:', err)
  }
}

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
}

// Handle Continue button click in Aether modal
async function handleAetherContinue() {
  // Clear the result to close the modal
  prayers.aetherResult = null

  // Refresh profile data from server (karma, ban status, etc.)
  await prayers.fetchProfile()

  // If the prayer was rejected, check ban status so App.vue switches to Purgatory view
  if (prayers.prayers.length > 0) {
    const latestPrayer = prayers.prayers[0]
    if (latestPrayer.is_rejected) {
      // Refresh ban status from server — this will set isBanned = true
      // which causes App.vue's computed to switch to PurgatoryView
      await banTimer.checkBanStatus()
    }
  }
}

</script>

<style scoped>
.prayer-counter-display {
  transform-origin: center;
  transition: transform var(--dur-quick) var(--ease-ritual-lift);
}

.counter-animate {
  animation: counterPulse 180ms var(--ease-ritual-lift);
}

.counter-value {
  letter-spacing: -0.05em;
  font-variant-numeric: tabular-nums;
  text-shadow: 0 0 18px rgba(213, 154, 23, 0.16);
}

.active-prayer-card {
  position: relative;
  overflow: hidden;
}

.active-prayer-card::before {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.2), transparent 24%),
    radial-gradient(circle at top center, rgba(255, 223, 147, 0.16), transparent 48%);
}

.active-prayer-card::after {
  content: "";
  position: absolute;
  inset: auto 12% 0;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(255, 236, 181, 0.72), transparent);
  opacity: 0.8;
}

.active-status-chip {
  animation: ritual-breathe 2.8s ease-in-out infinite;
}

.shadow-glow-accent {
  box-shadow:
    0 20px 42px rgba(48, 38, 21, 0.16),
    0 0 24px rgba(213, 154, 23, 0.14),
    0 0 58px rgba(240, 182, 59, 0.12);
}

.stacked-cards-container {
  min-height: 22rem;
  padding-bottom: 1rem;
}

.submission-panel {
  position: relative;
  overflow: hidden;
}

.submission-panel::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: radial-gradient(circle at top center, rgba(255, 223, 147, 0.12), transparent 42%);
}

.submission-logo-shell {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 13rem;
  height: 13rem;
}

.submission-logo-halo {
  position: absolute;
  inset: 0;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.32) 0%, rgba(255, 223, 147, 0.08) 42%, transparent 72%);
  filter: blur(8px);
  animation: ritual-breathe 6s ease-in-out infinite;
}

.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: rgba(139, 125, 91, 0.12);
  border-radius: 999px;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(213, 154, 23, 0.26);
  border-radius: 999px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(213, 154, 23, 0.38);
}

.aether-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1.25rem;
  background:
    radial-gradient(circle at 50% 20%, rgba(255, 223, 147, 0.18), transparent 28%),
    linear-gradient(180deg, rgba(48, 38, 21, 0.68), rgba(48, 38, 21, 0.8));
  backdrop-filter: blur(14px);
  animation: overlay-fade var(--dur-enter) var(--ease-standard);
}

.aether-modal-container {
  width: min(92vw, 34rem);
  max-height: min(84vh, 48rem);
  overflow-y: auto;
  padding: clamp(1.5rem, 2vw, 2rem);
  border: 1px solid rgba(213, 154, 23, 0.36);
  border-radius: var(--radius-panel);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.18), transparent 18%),
    linear-gradient(135deg, rgba(255, 250, 241, 0.97), rgba(255, 244, 220, 0.94));
  box-shadow:
    0 24px 70px rgba(48, 38, 21, 0.2),
    0 0 60px rgba(240, 182, 59, 0.14);
  animation: modal-rise var(--dur-hero) var(--ease-silk-settle);
}

.aether-processing-state,
.aether-result-state {
  text-align: center;
  padding: 0.5rem 0;
}

.aether-icon {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 5rem;
  height: 5rem;
  margin: 0 auto 1.5rem;
  border-radius: 999px;
  color: var(--theme-accent);
  background: rgba(255, 248, 228, 0.8);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.72), 0 18px 30px rgba(213, 154, 23, 0.16);
  filter: drop-shadow(0 0 8px rgba(213, 154, 23, 0.24));
}

.aether-title {
  margin-bottom: 0.75rem;
  color: var(--theme-accent);
  font-family: var(--font-display);
  font-size: clamp(1.85rem, 4vw, 2.25rem);
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.02;
}

.aether-description {
  margin-bottom: 1.5rem;
  color: var(--theme-text);
  font-size: 0.98rem;
  line-height: 1.65;
  font-weight: 500;
}

.aether-loader {
  width: 100%;
  height: 0.5rem;
  margin-top: 1.5rem;
  overflow: hidden;
  border-radius: 999px;
  background: linear-gradient(180deg, rgba(139, 125, 91, 0.12), rgba(255, 255, 255, 0.45));
  box-shadow: inset 0 1px 1px rgba(48, 38, 21, 0.08), inset 0 -1px 0 rgba(255, 255, 255, 0.6);
}

.aether-loader-bar {
  height: 100%;
  width: 38%;
  border-radius: inherit;
  background: linear-gradient(90deg, #c79a2c 0%, #f6d980 34%, #fff1bd 52%, #d7a42a 100%);
  animation: loaderShimmer 2.2s var(--ease-silk-settle) infinite;
  box-shadow: 0 0 12px rgba(201, 168, 76, 0.38);
}

.aether-judgment-icon {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 4.5rem;
  height: 4.5rem;
  margin: 0 auto 1.25rem;
  border-radius: 999px;
  background: rgba(255, 249, 235, 0.82);
  border: 1px solid rgba(213, 154, 23, 0.22);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), 0 16px 28px rgba(48, 38, 21, 0.12);
}

.aether-judgment-icon.approved {
  color: #3aa76d;
  border-color: rgba(58, 167, 109, 0.36);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.78), 0 0 24px rgba(58, 167, 109, 0.14);
}

.aether-judgment-icon.rejected {
  color: var(--theme-purgatory);
  border-color: rgba(168, 93, 50, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.78), 0 0 24px rgba(168, 93, 50, 0.14);
}

.aether-judgment-icon.error {
  color: #d18a16;
  border-color: rgba(209, 138, 22, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.78), 0 0 24px rgba(209, 138, 22, 0.14);
}

.aether-karma-display {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  margin: 1rem auto 0;
  padding: 0.85rem 1.4rem;
  border-radius: 999px;
  border: 1px solid rgba(213, 154, 23, 0.28);
  background: linear-gradient(180deg, rgba(255, 252, 244, 0.88), rgba(255, 246, 227, 0.9));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.74), 0 12px 24px rgba(48, 38, 21, 0.08);
}

.aether-response-content,
.aether-error-content {
  margin: 1.25rem 0;
  text-align: left;
  border-radius: 24px;
}

.aether-response-content {
  border: 1px solid rgba(213, 154, 23, 0.26);
  background: linear-gradient(180deg, rgba(255, 252, 244, 0.84), rgba(255, 247, 228, 0.78));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), inset 0 -1px 0 rgba(213, 154, 23, 0.08);
}

.aether-error-content {
  border: 1px solid rgba(168, 93, 50, 0.28);
  background: linear-gradient(180deg, rgba(255, 248, 242, 0.82), rgba(247, 227, 211, 0.78));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), inset 0 -1px 0 rgba(168, 93, 50, 0.08);
}

.aether-rejection-reason {
  text-align: center;
  font-style: italic;
  color: var(--theme-purgatory);
  font-weight: 500;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity var(--dur-standard) var(--ease-standard);
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.typewriter-cursor {
  animation: blink 0.7s infinite;
  color: var(--theme-accent);
  font-weight: 100;
}

@keyframes loaderShimmer {
  0% {
    transform: translateX(-100%);
  }
  100% {
    transform: translateX(280%);
  }
}

@keyframes blink {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: 0;
  }
}
</style>