<template>
  <div :class="[activeTab === 'dark' ? 'evil-shell' : 'war-shell', 'min-h-screen']">
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="relative min-w-0">
            <div class="merged-header-glow" aria-hidden="true"></div>
            <h1 class="ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">
              {{ activeTab === 'light' ? 'The Vatican' : 'The Catacombs' }}
            </h1>
            <p class="relative mt-1 text-sm text-theme-text-muted">
              {{ activeTab === 'light' ? 'Spiritual hierarchy, tithes, and holy war' : 'Shadow economy. Heresy breeds here.' }}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <MiracleBuffBar :miracles="nonShieldMiracles" />
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <div class="mb-8 flex justify-center">
        <div class="segmented-shell">
          <button
            @click="activeTab = 'light'"
            :class="activeTab === 'light' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            🏰 Vatican
          </button>
          <button
            @click="activeTab = 'dark'"
            :class="activeTab === 'dark' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            ✝️ Catacombs
          </button>
        </div>
      </div>

      <div v-if="activeTab === 'light'" class="space-y-8">
        <section class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-amber-500">👑</span>
            Your Liege Lord
          </h2>
          <div class="mt-4">
            <div v-if="vassalage.isVassal" class="rounded-lg border border-theme-border bg-theme-panel/35 p-4 sm:p-5">
              <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div class="flex-1">
                  <p class="text-sm leading-relaxed text-theme-text">
                    You bow before <span class="font-semibold text-amber-600">{{ vassalage.suzerain?.username || 'Unknown' }}</span>
                    <span v-if="vassalage.suzerain?.faith" class="text-theme-text-muted"> - {{ vassalage.suzerain.faith }}</span>
                  </p>
                  <p class="mt-2 text-xs text-theme-text-muted">10% of your gross production flows upward as tithe</p>
                </div>
                <button
                  @click="vassalage.declareSchism()"
                  :disabled="vassalage.schismLoading || economy.heresy < vassalage.schismCost"
                  class="btn-secondary w-full px-4 py-2 text-sm sm:w-auto"
                >
                  <span class="relative z-10 font-medium">
                    {{ vassalage.schismLoading ? 'Declaring...' : `Declare Schism (${vassalage.schismCost} heresy)` }}
                  </span>
                </button>
              </div>
            </div>

            <div v-else class="rounded-lg border border-theme-border bg-theme-panel/35 p-4 sm:p-5">
              <p class="text-sm font-medium text-emerald-600">You are a free soul. No suzerain commands you.</p>
              <p v-if="vassalage.hasVassals" class="mt-2 text-xs text-theme-text-muted">But others bow to you...</p>
            </div>
          </div>
        </section>

        <section class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-amber-500">⚔️</span>
            Your Vassals
            <span v-if="vassalage.vassalCount > 0" class="chip gap-1 px-2 py-0.5 text-xs font-semibold text-amber-600">
              {{ vassalage.vassalCount }}
            </span>
          </h2>

          <div v-if="vassalage.hasVassals" class="mt-4 space-y-3">
            <div
              v-for="vassal in vassalage.vassals"
              :key="vassal.id"
              class="rounded-lg border border-theme-border bg-theme-panel/35 p-4 transition-all duration-200 hover:-translate-y-0.5 hover:border-theme-accent/20"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-sm font-medium text-theme-text">{{ vassal.username }}</p>
                  <p v-if="vassal.faith" class="text-xs text-theme-text-muted">{{ vassal.faith }}</p>
                </div>
                <div class="text-xs font-semibold text-amber-600">10% tithe</div>
              </div>
            </div>

            <div class="rounded-lg border border-theme-border bg-theme-panel/35 p-4">
              <p class="text-xs text-theme-text-muted">Daily tithes received:</p>
              <div class="mt-3 flex flex-wrap gap-2">
                <span v-if="vassalage.dailyTithes.mana_per_day > 0" class="chip text-xs">+{{ vassalage.dailyTithes.mana_per_day }} mana</span>
                <span v-if="vassalage.dailyTithes.gold_per_day > 0" class="chip text-xs">+{{ vassalage.dailyTithes.gold_per_day }} gold</span>
                <span v-if="vassalage.dailyTithes.food_per_day > 0" class="chip text-xs">+{{ vassalage.dailyTithes.food_per_day }} food</span>
                <span v-if="!hasDailyTithes" class="chip text-xs">none yet</span>
              </div>
            </div>
          </div>

          <div v-else class="mt-4 rounded-lg border border-theme-border bg-theme-panel/35 p-4">
            <p class="text-sm text-theme-text-dim">You have no vassals. Crusade to subjugate other players.</p>
          </div>
        </section>

        <!-- Active Siege Card (shown when you have an active combat) -->
        <section v-if="combat.myCombatTargetId || combat.attackersOnMe.length > 0" class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-red-500">⚔️</span>
            Active Siege
            <span class="chip gap-1 px-2 py-0.5 text-xs font-semibold text-green-500">● Live</span>
          </h2>

          <div v-if="combat.myAttack" class="mt-4 space-y-4">
            <!-- Attacker view -->
            <div class="rounded-lg border border-theme-accent/25 bg-theme-accent/5 p-4">
              <p class="text-xs text-theme-text-muted mb-2">
                Sieging <span class="font-semibold text-red-400">{{ combat.myAttack.defender_name }}</span>
                · <span class="text-theme-text-dim">{{ siegeProgressText(combat.myAttack) }}</span>
              </p>

              <div class="space-y-3">
                <div>
                  <div class="flex justify-between text-xs mb-1">
                    <span class="text-theme-text-muted">Your Mana</span>
                    <span class="font-semibold text-blue-400">{{ combat.myAttack.attacker_mana }}
                      <span class="text-[0.65rem] text-theme-text-dim">(-{{ combat.myAttack.defender_workers || 0 }}/min)</span>
                    </span>
                  </div>
                  <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                    <div class="h-full bg-blue-500/60 transition-all duration-500"
                      :style="{ width: manaBarPercent(combat.myAttack.attacker_mana, combat.myAttack.attacker_mana + combat.myAttack.defender_mana) + '%' }"></div>
                  </div>
                </div>
                <div>
                  <div class="flex justify-between text-xs mb-1">
                    <span class="text-theme-text-muted">Enemy Mana</span>
                    <span class="font-semibold text-red-400">{{ combat.myAttack.defender_mana }}
                      <span class="text-[0.65rem] text-theme-text-dim">(-{{ combat.myAttack.attacker_workers }}/min)</span>
                    </span>
                  </div>
                  <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                    <div class="h-full bg-red-500/60 transition-all duration-500"
                      :style="{ width: manaBarPercent(combat.myAttack.defender_mana, combat.myAttack.attacker_mana + combat.myAttack.defender_mana) + '%' }"></div>
                  </div>
                </div>
              </div>

              <div class="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs overflow-x-auto">
                <div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-theme-text">{{ combat.myAttack.attacker_workers }}</div>
                  <div class="text-theme-text-dim">Your Workers</div>
                </div>
                <div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-theme-text">{{ combat.myAttack.defender_workers }}</div>
                  <div class="text-theme-text-dim">Enemy Workers</div>
                </div>
                <div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-theme-text">{{ combat.myAttack.ticks_total - combat.myAttack.ticks_remaining }} / {{ combat.myAttack.ticks_total }}</div>
                  <div class="text-theme-text-dim">Ticks</div>
                </div>
                <div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-yellow-500">{{ combat.myAttack.gold_stolen || 0 }} 💰</div>
                  <div class="text-theme-text-dim">Gold Leech</div>
                </div>
              </div>

              <button
                @click="handleCancelSiege(combat.myAttack.session_id)"
                class="btn-secondary mt-4 w-full py-2 text-xs"
                :title="'Pay 50% of remaining tick gold to withdraw. -5 Karma penalty.'"
              >
                <span class="relative z-10 font-medium">Withdraw ({{ withdrawCost(combat.myAttack) }} Gold, -5 Karma)</span>
              </button>
            </div>
          </div>

          <!-- Defender view: under attack -->
          <div v-for="atk in combat.attackersOnMe" :key="atk.session_id" class="mt-4 rounded-lg border border-theme-purgatory/25 bg-theme-purgatory/5 p-4">
            <p class="text-xs text-theme-text-muted mb-2">
              🛡 <span class="font-semibold text-red-400">{{ atk.attacker_name }}</span> is sieging you!
               · <span class="text-theme-text-dim">{{ siegeProgressText(atk) }}</span>
            </p>

            <div class="space-y-3">
              <div>
                <div class="flex justify-between text-xs mb-1">
                  <span class="text-theme-text-muted">Enemy Mana</span>
                  <span class="font-semibold text-red-400">{{ atk.attacker_mana }}
                    <span class="text-[0.65rem] text-theme-text-dim">(-{{ atk.defender_workers || 0 }}/min)</span>
                  </span>
                </div>
                <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                  <div class="h-full bg-red-500/60 transition-all duration-500"
                    :style="{ width: manaBarPercent(atk.attacker_mana, atk.attacker_mana + atk.defender_mana) + '%' }"></div>
                </div>
              </div>
              <div>
                <div class="flex justify-between text-xs mb-1">
                  <span class="text-theme-text-muted">Your Mana</span>
                  <span class="font-semibold text-blue-400">{{ atk.defender_mana }}
                    <span class="text-[0.65rem] text-theme-text-dim">(-{{ atk.attacker_workers }}/min)</span>
                  </span>
                </div>
                <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                  <div class="h-full bg-blue-500/60 transition-all duration-500"
                    :style="{ width: manaBarPercent(atk.defender_mana, atk.attacker_mana + atk.defender_mana) + '%' }"></div>
                </div>
              </div>
            </div>

            <div class="mt-3 grid grid-cols-2 sm:grid-cols-3 gap-2 text-xs">
              <div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ atk.attacker_workers }}</div>
                <div class="text-theme-text-dim">Enemy Workers</div>
              </div>
              <div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-yellow-500">{{ atk.gold_stolen || 0 }} 💰</div>
                <div class="text-theme-text-dim">Gold Leech</div>
              </div>
              <div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ atk.ticks_total - atk.ticks_remaining }} / {{ atk.ticks_total }}</div>
                <div class="text-theme-text-dim">Ticks</div>
              </div>
            </div>

            <button
              @click="handleSurrenderSiege(atk.session_id)"
              class="btn-danger mt-4 w-full py-2 text-xs"
              title="Immediately become their Vassal. 10% tithe on all production."
            >
              <span class="relative z-10 font-medium">Surrender (Become Vassal)</span>
            </button>
          </div>
        </section>

        <!-- Launch Siege (shown when NOT in combat AND not attacking) -->
        <section v-if="!combat.myCombatTargetId && combat.attackersOnMe.length === 0" class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-red-500">⚔️</span>
            Launch Siege
          </h2>

          <div class="mt-4 rounded-lg border border-theme-border bg-theme-panel/35 p-4">
            <p class="text-xs text-theme-text-muted leading-relaxed">
              <span class="font-semibold text-theme-text">3-day siege</span> (4,320 ticks, one per minute).
              Your <span class="font-semibold text-blue-400">Workers</span> deal damage to their <span class="font-semibold text-blue-400">Mana</span> pool each tick.
              Their Workers counter-attack. You leech <span class="font-semibold text-yellow-500">0.5% Gold</span> per tick.
            </p>
            <div class="mt-3 flex flex-wrap gap-3 text-xs">
              <span class="chip gap-1 px-2 py-1">
                <span>🛠 Workers:</span>
                <span class="font-semibold text-blue-400">{{ workerCount }}</span>
                <span class="text-theme-text-dim">({{ workerCount }} DPS/tick)</span>
              </span>
              <span class="chip gap-1 px-2 py-1">
                <span>💎 Mana:</span>
                <span class="font-semibold text-blue-400">{{ economy.mana }}</span>
                <span class="text-theme-text-dim">HP</span>
              </span>
              <span class="chip gap-1 px-2 py-1">
                <span>💰 Cost:</span>
                <span class="font-semibold text-yellow-500">50 Gold</span>
                <span class="text-theme-text-dim">initiation + 2/min</span>
              </span>
            </div>
            <p class="mt-2 text-[0.65rem] text-theme-text-dim">Workers = Novices, Monks, Clerics, Bishops, Cardinals, Cultists</p>
          </div>

          <div class="mt-5 flex flex-col gap-3 sm:flex-row sm:items-end">
            <div class="flex-1">
              <label class="mb-1 block text-xs text-theme-text-muted">Target Username</label>
              <input
                v-model="targetUsername"
                @keyup.enter="searchPlayer"
                type="text"
                placeholder="Enter player name..."
                class="form-field w-full px-4 py-3 text-sm"
              />
            </div>
            <button
              @click="searchPlayer"
              :disabled="searching || !targetUsername.trim()"
              class="btn-secondary px-5 py-3 text-sm"
            >
              <span class="relative z-10 font-medium">{{ searching ? 'Searching...' : 'Search' }}</span>
            </button>
          </div>

          <div v-if="targetSearchResults.length > 0" class="mt-4 space-y-3">
            <div
              v-for="player in targetSearchResults"
              :key="player.id"
              class="rounded-lg border border-theme-border bg-theme-panel/35 p-4"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-sm font-medium text-theme-text">{{ player.username }}</p>
                  <p v-if="player.faith" class="text-xs text-theme-text-muted">{{ player.faith }}</p>
                  <p v-if="isPlayerShielded(player)" class="text-xs text-amber-500 mt-0.5">🛡 Divine Shield active</p>
                </div>
                <button
                  @click="selectTarget(player)"
                  :disabled="isPlayerShielded(player) || combat.myCombatTargetId"
                  class="btn-danger px-4 py-2 text-xs"
                  :class="{ 'opacity-50 cursor-not-allowed': isPlayerShielded(player) || combat.myCombatTargetId }"
                >
                  <span class="relative z-10 font-medium">{{ isPlayerShielded(player) ? '🛡 Shielded' : 'Siege' }}</span>
                </button>
              </div>
            </div>
          </div>

          <div v-if="combat.lastResult && combat.lastResult.type === 'initiated'" class="mt-5 rounded-lg border border-theme-accent/25 bg-theme-accent/10 p-4">
            <p class="text-sm font-semibold text-theme-accent-light">Siege Launched!</p>
            <p class="text-xs text-theme-text-muted mt-1">{{ combat.lastResult.siege_days }} days. {{ combat.lastResult.max_ticks }} ticks. Check the Active Siege card above.</p>
          </div>

          <div v-if="combat.error" class="mt-4 rounded-lg border border-red-500/25 bg-red-500/10 p-4">
            <p class="text-xs text-red-600">{{ combat.error }}</p>
          </div>
        </section>

        <!-- Subjugation Progress -->
        <section v-if="vassalage.isSubjugatingSomeone || vassalage.isBeingSubjugated" class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-purple-500">💰</span>
            Subjugation Progress
          </h2>

          <div v-if="vassalage.isSubjugatingSomeone" class="mt-4 space-y-3">
            <div v-for="sub in vassalage.subjugationAsLiege" :key="sub.vassal_id"
              class="rounded-lg border border-theme-accent/20 bg-theme-panel/35 p-4">
              <div class="flex items-center justify-between mb-2">
                <p class="text-sm font-medium text-theme-text">{{ sub.vassal_name }}</p>
                <span class="text-xs text-theme-text-dim">{{ Math.floor(sub.accumulated_hours) }} / 168 hours</span>
              </div>
              <div class="h-2 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                <div class="h-full bg-purple-500/60 transition-all duration-500"
                  :style="{ width: (sub.accumulated_hours / 168 * 100) + '%' }"></div>
              </div>
              <p class="mt-1 text-[0.65rem] text-theme-text-dim">Each minute of active siege = +1/60th hour. At 168, they become your Vassal.</p>
            </div>
          </div>

          <div v-if="vassalage.isBeingSubjugated" class="mt-4 space-y-3">
            <div v-for="sub in vassalage.subjugationAsVassal" :key="sub.liege_id"
              class="rounded-lg border border-theme-purgatory/25 bg-theme-purgatory/5 p-4">
              <p class="text-xs text-theme-text-muted mb-2">
                <span class="font-semibold text-red-400">{{ sub.liege_name }}</span> is subjugating you
              </p>
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs text-theme-text-dim">{{ Math.floor(sub.accumulated_hours) }} / 168 hours</span>
                <span class="text-xs font-semibold text-theme-purgatory-dark">{{ Math.max(0, Math.floor(sub.remaining_hours)) }}h remaining</span>
              </div>
              <div class="h-2 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                <div class="h-full bg-red-500/60 transition-all duration-500"
                  :style="{ width: (sub.accumulated_hours / 168 * 100) + '%' }"></div>
              </div>
              <div class="mt-3 flex gap-2">
                <button
                  @click="vassalage.resistSubjugation(sub.liege_id)"
                  :disabled="vassalage.resisting || economy.gold < 1000"
                  class="btn-secondary flex-1 py-1.5 text-xs"
                  title="Pay 1000 Gold to reduce timer by 24 hours"
                >
                  <span class="relative z-10 font-medium">Resist (1000 ⚁EↁE-24h)</span>
                </button>
                <button
                  @click="vassalage.attemptRebellion()"
                  :disabled="vassalage.rebelling"
                  class="btn-ghost flex-1 py-1.5 text-xs"
                  title="Break free if liege hasn't attacked in 3+ days"
                >
                  <span class="relative z-10 font-medium">Rebel</span>
                </button>
              </div>
            </div>
          </div>
        </section>

        <section class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text flex items-center gap-2">
            <span class="text-theme-accent">📜</span>
            Akashic Records
          </h2>

          <div v-if="vassalage.akashicLogs.length === 0" class="mt-4 rounded-lg border border-theme-border bg-theme-panel/35 p-4">
            <p class="text-sm text-theme-text-dim">No recorded events yet.</p>
          </div>

          <div v-else class="mt-4 space-y-3 max-h-72 overflow-y-auto pr-1">
            <div
              v-for="log in vassalage.akashicLogs"
              :key="log.id"
              class="rounded-lg border border-theme-border bg-theme-panel/35 p-4 transition-all duration-200 hover:-translate-y-0.5 hover:border-theme-accent/20"
            >
              <div class="flex items-start gap-3">
                <div class="mt-0.5 flex-shrink-0">
                  <span v-if="log.action_type === 'crusade'" class="text-red-500">⚔️</span>
                  <span v-else-if="log.action_type === 'schism'" class="text-purple-500">✨</span>
                  <span v-else-if="log.action_type === 'plague'" class="text-emerald-500">☠</span>
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
                      Anonymous curse struck {{ log.target_username }} - {{ log.result_data?.food_destroyed || 0 }} food destroyed
                    </template>
                  </p>
                </div>
              </div>
            </div>
          </div>

          <button
            @click="vassalage.fetchAkashicLogs(50)"
            :disabled="vassalage.logsLoading"
            class="btn-secondary mt-4 w-full py-3 text-xs"
          >
            <span class="relative z-10 font-medium">{{ vassalage.logsLoading ? 'Loading...' : 'Refresh Logs' }}</span>
          </button>
        </section>
      </div>

      <div v-if="activeTab === 'dark'" class="space-y-8">
        <section class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text mb-4 flex items-center gap-2">
            <span>🔮</span>
            Shadow Holdings
          </h2>

          <div v-if="catacombs.loading && catacombs.allCatacombsItems.length === 0" class="p-12 text-center text-theme-text-muted">
            <div class="mb-3 text-4xl animate-pulse">Loading the dark...</div>
          </div>

          <div v-else class="grid gap-5 sm:grid-cols-2 xl:grid-cols-2">
            <div
              v-for="item in catacombs.allCatacombsItems"
              :key="item.id"
              class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden p-5 transition-all duration-300 hover:-translate-y-1"
              :class="{
                'opacity-60': !canAffordItem(item),
                'ring-1 ring-theme-accent/35': ownedCount(item.effect_data?.building_type) > 0
              }"
            >
              <div class="mb-2 flex items-center justify-between">
                <span class="text-[0.65rem] font-bold uppercase tracking-wider text-theme-accent/70">
                  {{ item.effect_data?.building_type === 'cultist' ? 'Worker' : 'Infrastructure' }}
                </span>
                <span v-if="ownedCount(item.effect_data?.building_type) > 0" class="chip gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                  x{{ ownedCount(item.effect_data?.building_type) }}
                </span>
              </div>

              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-14 w-14 items-center justify-center rounded-lg border border-theme-accent/20 bg-theme-panel/60 text-3xl shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                  {{ item.emoji_icon }}
                </span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ item.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ formatItemCost(item) }}</span>
                  </div>
                </div>
              </div>

              <p class="mb-3 text-xs leading-relaxed text-theme-text-dim">{{ item.description }}</p>

              <div v-if="item.effect_type === 'add_building'" class="mb-3 space-y-1 text-[0.7rem] text-theme-text-muted">
                <div v-if="buildingProduction(item.effect_data.building_type, 'heresy_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-theme-accent">+</span>
                  <span>{{ buildingProduction(item.effect_data.building_type, 'heresy_per_day') }} heresy/day each</span>
                </div>
                <div v-if="item.effect_data?.building_type === 'cultist' && buildingProduction('cultist', 'food_consumption_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-theme-purgatory">-</span>
                  <span>{{ buildingProduction('cultist', 'food_consumption_per_day') }} food/day each</span>
                </div>
                <div v-if="item.effect_data?.building_type === 'coven'" class="flex items-center gap-1">
                  <span class="text-theme-accent">+</span>
                  <span>{{ economy.gameConfig?.['building.coven.heresy_cap_bonus'] || 50 }} heresy cap each</span>
                </div>
                <div v-if="item.effect_data?.building_type === 'coven' && buildingProduction('coven', 'gold_upkeep_per_day') > 0" class="flex items-center gap-1">
                  <span class="text-theme-purgatory">-</span>
                  <span>{{ buildingProduction('coven', 'gold_upkeep_per_day') }} gold upkeep/day each</span>
                </div>
              </div>

              <div v-if="item.cost_scaling && ownedCount(item.effect_data?.building_type) > 0" class="mb-2 text-[0.65rem] text-theme-text-muted">
                Next: {{ formatNextCost(item) }}
              </div>

              <div v-if="item.requires_building && !hasPrereq(item)" class="mb-3 flex items-center gap-1 text-[0.7rem] text-theme-purgatory">
                <span>🔒</span>
                <span>Requires {{ catacombs.catacombsBuildingInfo[item.requires_building]?.name || item.requires_building }}</span>
              </div>

              <button
                @click="catacombs.purchaseItem(item.id)"
                :disabled="!canAffordItem(item) || catacombs.purchasing"
                class="btn-secondary w-full py-2 text-sm"
              >
                <span class="relative z-10 font-medium" v-if="catacombs.purchasing && catacombs.lastPurchase?.item_id === item.id">Purchasing...</span>
                <span class="relative z-10 font-medium" v-else-if="item.requires_building && !hasPrereq(item)">🔒 Requires {{ catacombs.catacombsBuildingInfo[item.requires_building]?.name || item.requires_building }}</span>
                <span class="relative z-10 font-medium" v-else-if="!canAffordItem(item)">Not enough resources</span>
                <span class="relative z-10 font-medium" v-else>Purchase</span>
              </button>
            </div>
          </div>

          <div v-if="catacombs.purchaseError" class="mt-4 rounded-lg border border-theme-purgatory/25 bg-theme-purgatory/10 p-3">
            <p class="text-xs text-theme-purgatory-dark">{{ catacombs.purchaseError }}</p>
            <button @click="catacombs.clearPurchaseError()" class="mt-2 text-xs text-theme-purgatory-dark hover:text-theme-text">Dismiss</button>
          </div>
        </section>

        <section class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text mb-3 flex items-center gap-2">
            <span>☠</span>
            Cast Curse
          </h2>

          <p class="text-xs text-theme-text-muted mb-4">
            Spend <span class="font-semibold text-theme-accent">{{ plagueCost }} heresy</span> to anonymously zero out a target's Food storage.
            Cannot target players with an active Divine Shield. Your identity is hidden in the Akashic Records.
          </p>

          <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div class="flex-1">
              <label class="block text-xs text-theme-text-muted mb-1">Target Username</label>
              <input
                v-model="plagueTarget"
                @keyup.enter="searchPlagueTarget"
                type="text"
                placeholder="Enter player name..."
                class="form-field w-full px-3 py-2 text-sm"
              />
            </div>
            <button
              @click="searchPlagueTarget"
              :disabled="searchingPlague || !plagueTarget.trim()"
              class="btn-secondary px-4 py-2 text-sm"
            >
              <span class="relative z-10 font-medium">{{ searchingPlague ? 'Searching...' : 'Search' }}</span>
            </button>
          </div>

          <div v-if="plagueSearchResults.length > 0" class="mt-3 space-y-2">
            <div
              v-for="player in plagueSearchResults"
              :key="player.id"
              class="rounded-lg border border-theme-border bg-theme-panel/35 p-3"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-sm font-medium text-theme-text">{{ player.username }}</p>
                  <p v-if="player.faith" class="text-xs text-theme-text-muted">{{ player.faith }}</p>
                  <p v-if="isPlayerShielded(player)" class="text-xs text-amber-500 mt-0.5">🛡 Divine Shield active</p>
                </div>
                <button
                  @click="selectPlagueTarget(player)"
                  :disabled="catacombs.heresy < plagueCost || isPlayerShielded(player)"
                  class="btn-secondary px-3 py-1.5 text-xs"
                  :class="{ 'opacity-50 cursor-not-allowed': isPlayerShielded(player) }"
                >
                  <span class="relative z-10 font-medium">{{ isPlayerShielded(player) ? '🛡 Shielded' : 'Target' }}</span>
                </button>
              </div>
            </div>
          </div>

          <div v-if="vassalage.combatResult && vassalage.combatResult.type === 'plague'" class="mt-4 rounded-lg border border-emerald-500/25 bg-emerald-500/10 p-4">
            <p class="text-sm font-semibold text-emerald-400">Curse Cast Successfully!</p>
            <p class="text-xs text-theme-text-muted mt-1">{{ vassalage.combatResult.food_destroyed }} food destroyed. Your identity remains hidden.</p>
          </div>

          <div v-if="vassalage.combatError && !showPlagueConfirm" class="mt-4 rounded-lg border border-theme-purgatory/25 bg-theme-purgatory/10 p-3">
            <p class="text-xs text-theme-purgatory-dark">{{ vassalage.combatError }}</p>
          </div>
        </section>

        <section v-if="vassalage.isVassal" class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text mb-3 flex items-center gap-2">
            <span>✨</span>
            Declare Schism
          </h2>

          <p class="text-xs text-theme-text-muted mb-3">
            Break free from <span class="font-semibold text-theme-text">{{ vassalage.suzerain?.username || 'your suzerain' }}</span>.
            Costs heresy and grants 24h Divine Shield protection from crusades.
            Cost scales exponentially with each schism.
          </p>

          <div class="rounded-lg border border-theme-border bg-theme-panel/35 p-4">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p class="text-sm font-medium text-theme-text">Schism Cost: <span class="font-bold text-theme-accent">{{ vassalage.schismCost }} heresy</span></p>
                <p class="text-xs text-theme-text-muted mt-1">Current heresy: {{ catacombs.heresy }}</p>
              </div>
              <button
                @click="showSchismConfirm = true"
                :disabled="catacombs.heresy < vassalage.schismCost || vassalage.schismLoading"
                class="btn-secondary px-4 py-2 text-sm"
              >
                <span class="relative z-10 font-medium">Declare Schism</span>
              </button>
            </div>
          </div>

          <div v-if="vassalage.combatResult && vassalage.combatResult.type === 'schism'" class="mt-4 rounded-lg border border-theme-accent/25 bg-theme-accent/10 p-4">
            <p class="text-sm font-semibold text-theme-accent-light">Schism Declared!</p>
            <p class="text-xs text-theme-text-muted mt-1">
              You are free! Divine Shield active until {{ new Date(vassalage.combatResult.shield_until).toLocaleString() }}
            </p>
          </div>
        </section>

        <section class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-theme-text mb-3 flex items-center gap-2">
            <span>📊</span>
            Heresy Economy
          </h2>

          <div class="grid gap-4 sm:grid-cols-3">
            <div class="rounded-lg border border-theme-border bg-theme-panel/35 p-4">
              <p class="text-xs text-theme-text-muted">Generation</p>
              <p class="text-lg font-semibold text-theme-accent">+{{ catacombs.heresyPerDay }}/day</p>
            </div>
            <div class="rounded-lg border border-theme-border bg-theme-panel/35 p-4">
              <p class="text-xs text-theme-text-muted">Capacity</p>
              <p class="text-lg font-semibold text-theme-accent">{{ catacombs.heresyCap }}</p>
            </div>
            <div class="rounded-lg border border-theme-border bg-theme-panel/35 p-4">
              <p class="text-xs text-theme-text-muted">Schisms Declared</p>
              <p class="text-lg font-semibold text-theme-accent">{{ economy.schismCount || 0 }}</p>
            </div>
          </div>
        </section>
      </div>
    </main>

    <div v-if="showCrusadeConfirm" class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4" @click.self="showCrusadeConfirm = false">
      <div class="glass-panel glass-panel-strong glass-gloss w-full max-w-md p-6 space-y-4">
        <h3 class="text-lg font-semibold text-theme-text">Confirm Siege</h3>
        <div v-if="selectedTarget && isPlayerShielded(selectedTarget)" class="rounded-lg border border-amber-500/25 bg-amber-500/10 p-3">
          <p class="text-xs text-amber-600">🛡 This player is protected by Divine Shield and cannot be attacked.</p>
        </div>
        <p class="text-sm text-theme-text-muted">
          Launch a 3-day siege against <span class="font-semibold text-red-500">{{ selectedTarget?.username }}</span>?
        </p>
        <div class="rounded-lg border border-theme-border bg-theme-panel/35 p-3 space-y-1 text-xs text-theme-text-muted">
          <p>💰 <span class="font-semibold text-yellow-500">50 Gold</span> to initiate + 2 Gold per minute</p>
          <p>🛠 Your Workers: <span class="font-semibold text-blue-400">{{ workerCount }}</span> ({{ workerCount }} DPS/tick)</p>
          <p>💎 Your Mana: <span class="font-semibold text-blue-400">{{ economy.mana }}</span> (HP pool)</p>
          <p>⚁EIf victorious, they become your Vassal (10% tithe)</p>
          <p>⚁EYou can withdraw at any time (50% remaining gold cost + -5 Karma)</p>
        </div>
        <div class="flex gap-3">
          <button
            @click="executeSiege"
            :disabled="combat.initiating || (selectedTarget && isPlayerShielded(selectedTarget))"
            class="btn-danger flex-1 px-4 py-2 text-sm"
            :class="{ 'opacity-50 cursor-not-allowed': selectedTarget && isPlayerShielded(selectedTarget) }"
          >
            <span class="relative z-10 font-medium">{{ combat.initiating ? 'Launching...' : 'Launch Siege' }}</span>
          </button>
          <button
            @click="showCrusadeConfirm = false"
            class="btn-ghost flex-1 px-4 py-2 text-sm"
          >
            <span class="relative z-10 font-medium">Cancel</span>
          </button>
        </div>
      </div>
    </div>

    <div v-if="showPlagueConfirm" class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4" @click.self="showPlagueConfirm = false">
      <div class="glass-panel glass-panel-strong glass-gloss w-full max-w-md p-6 space-y-4">
        <h3 class="text-lg font-semibold text-theme-text">Confirm Curse</h3>
        <div v-if="selectedPlagueTarget && isPlayerShielded(selectedPlagueTarget)" class="rounded-lg border border-amber-500/25 bg-amber-500/10 p-3">
          <p class="text-xs text-amber-600">🛡 This player is protected by Divine Shield and cannot be cursed.</p>
        </div>
        <p class="text-sm text-theme-text-muted">
          Cast a curse on <span class="font-semibold text-theme-text">{{ selectedPlagueTarget?.username }}</span>?
          This will cost <span class="font-semibold text-theme-accent">{{ plagueCost }} heresy</span> and destroy all their Food.
          Your identity will remain anonymous.
        </p>
        <div class="flex gap-3">
          <button
            @click="executePlague"
            :disabled="vassalage.plagueLoading || (selectedPlagueTarget && isPlayerShielded(selectedPlagueTarget))"
            class="btn-primary flex-1 px-4 py-2 text-sm"
            :class="{ 'opacity-50 cursor-not-allowed': selectedPlagueTarget && isPlayerShielded(selectedPlagueTarget) }"
          >
            <span class="relative z-10 font-medium">{{ vassalage.plagueLoading ? 'Casting...' : 'Cast Curse' }}</span>
          </button>
          <button
            @click="showPlagueConfirm = false"
            class="btn-ghost flex-1 px-4 py-2 text-sm"
          >
            <span class="relative z-10 font-medium">Cancel</span>
          </button>
        </div>
      </div>
    </div>

    <div v-if="showSchismConfirm" class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4" @click.self="showSchismConfirm = false">
      <div class="glass-panel glass-panel-strong glass-gloss w-full max-w-md p-6 space-y-4">
        <h3 class="text-lg font-semibold text-theme-text">Confirm Schism</h3>
        <p class="text-sm text-theme-text-muted">
          Break free from <span class="font-semibold text-theme-text">{{ vassalage.suzerain?.username || 'your suzerain' }}</span>?
          This will cost <span class="font-semibold text-theme-accent">{{ vassalage.schismCost }} heresy</span> and grant you 24 hours of Divine Shield.
        </p>
        <p class="text-xs text-theme-text-muted">After this schism, the next one will cost {{ Math.floor(100 * Math.pow(2, (economy.schismCount || 0) + 1)) }} heresy.</p>
        <div class="flex gap-3">
          <button
            @click="executeSchism"
            :disabled="vassalage.schismLoading"
            class="btn-primary flex-1 px-4 py-2 text-sm"
          >
            <span class="relative z-10 font-medium">{{ vassalage.schismLoading ? 'Declaring...' : 'Declare Schism' }}</span>
          </button>
          <button
            @click="showSchismConfirm = false"
            class="btn-ghost flex-1 px-4 py-2 text-sm"
          >
            <span class="relative z-10 font-medium">Cancel</span>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, inject } from 'vue'
import { useVassalage } from '@/composables/useVassalage'
import { useCatacombs } from '@/composables/useCatacombs'
import { useEconomy } from '@/composables/useEconomy'
import { useCombat } from '@/composables/useCombat'
import MiracleBuffBar from '@/components/molecules/MiracleBuffBar.vue'

const vassalage = useVassalage()
const catacombs = useCatacombs()
const economy = useEconomy()
const combat = useCombat()

const forceEvilTheme = inject('forceEvilTheme', ref(false))
const forceWarTheme = inject('forceWarTheme', ref(false))
const activeTab = ref('light')

const targetUsername = ref('')
const targetSearchResults = ref([])
const searching = ref(false)
const showCrusadeConfirm = ref(false)
const selectedTarget = ref(null)

const plagueTarget = ref('')
const plagueSearchResults = ref([])
const searchingPlague = ref(false)
const showPlagueConfirm = ref(false)
const selectedPlagueTarget = ref(null)
const showSchismConfirm = ref(false)

// Combat helpers
const workerCount = computed(() => {
  const counts = economy.buildingCounts || {}
  return (counts.novice || 0) + (counts.monk || 0) + (counts.cleric || 0) +
    (counts.bishop || 0) + (counts.cardinal || 0) + (counts.cultist || 0)
})

function manaBarPercent(value, total) {
  if (!total || total <= 0) return 0
  return Math.min(100, Math.max(0, (value / total) * 100))
}

function siegeProgressText(combat) {
  if (!combat) return ''
  const elapsed = combat.ticks_total - combat.ticks_remaining
  const days = Math.floor(elapsed / 1440)
  const hours = Math.floor((elapsed % 1440) / 60)
  const remaining = combat.ticks_remaining
  const rDays = Math.floor(remaining / 1440)
  const rHours = Math.floor((remaining % 1440) / 60)
  return `Day ${days + 1} · ${rDays}d ${rHours}h left`
}

function withdrawCost(combat) {
  if (!combat) return 0
  const goldPerTick = combat.combat_type === 'holy_war' ? 10 : 2
  return Math.max(1, Math.floor(combat.ticks_remaining * goldPerTick * 0.5))
}

async function handleCancelSiege(sessionId) {
  try {
    await combat.cancelCombat(sessionId)
  } catch {
    // handled in composable
  }
}

async function handleSurrenderSiege(sessionId) {
  try {
    await combat.surrenderCombat(sessionId)
  } catch {
    // handled in composable
  }
}

// Filter blessing_shield out of MiracleBuffBar  EShieldTimer handles that display
const nonShieldMiracles = computed(() =>
  economy.activeMiracles.filter(m => m.miracle_type !== 'blessing_shield')
)

watch(activeTab, (tab) => {
  forceEvilTheme.value = (tab === 'dark')
  forceWarTheme.value = (tab === 'light')
}, { immediate: true })

onMounted(async () => {
  await Promise.all([
    vassalage.fetchVassalageInfo(),
    vassalage.fetchAkashicLogs(20),
    catacombs.fetchCatacombsItems(),
  ])
  combat.startPolling()
})

onUnmounted(() => {
  combat.stopPolling()
})

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

function selectTarget(player) {
  selectedTarget.value = player
  showCrusadeConfirm.value = true
}

async function executeSiege() {
  if (!selectedTarget.value) return
  try {
    await combat.initiateCombat(selectedTarget.value.id)
    showCrusadeConfirm.value = false
    selectedTarget.value = null
    targetUsername.value = ''
    targetSearchResults.value = []
  } catch {
    // handled in composable
  }
}

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

function selectPlagueTarget(player) {
  selectedPlagueTarget.value = player
  showPlagueConfirm.value = true
}

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

async function executeSchism() {
  try {
    await vassalage.declareSchism()
    showSchismConfirm.value = false
  } catch {
    // handled in composable
  }
}

function formatTime(timestamp) {
  if (!timestamp) return ''
  return new Date(timestamp).toLocaleString()
}

const actionNames = {
  crusade: 'Crusade',
  schism: 'Schism',
  plague: 'Curse',
}

const actionColors = {
  crusade: 'text-red-500',
  schism: 'text-purple-500',
  plague: 'text-emerald-500',
}

const hasDailyTithes = computed(() => {
  const tithes = vassalage.dailyTithes || {}
  return (tithes.mana_per_day || 0) > 0 || (tithes.gold_per_day || 0) > 0 || (tithes.food_per_day || 0) > 0
})

const plagueCost = computed(() => {
  const config = economy.gameConfig?.['plague.heresy_cost'] || 75
  return config
})

function isPlayerShielded(player) {
  if (!player || !player.divine_shield_until) return false
  return new Date(player.divine_shield_until) > new Date()
}

function buildingProduction(buildingType, stat) {
  const key = `building.${buildingType}.${stat}`
  return economy.gameConfig?.[key] || 0
}

function formatItemCost(item) {
  return catacombs.formatCosts(item)
}

function canAffordItem(item) {
  return catacombs.canAfford(item)
}

function hasPrereq(item) {
  return catacombs.hasPrerequisite(item)
}

function ownedCount(buildingType) {
  return economy.buildingCounts?.[buildingType] || 0
}

function formatNextCost(item) {
  const costs = catacombs.scaledCosts(item)
  const parts = []
  if (costs.karma > 0) parts.push(`${costs.karma} karma`)
  if (costs.gold > 0) parts.push(`${costs.gold} gold`)
  if (costs.heresy > 0) parts.push(`${costs.heresy} heresy`)
  return parts.join(', ')
}
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

.evil-shell .nav-tab-active {
  color: #f2f5f7;
  border-color: rgba(126, 255, 161, 0.24);
  background:
    linear-gradient(180deg, rgba(233, 241, 247, 0.16), rgba(233, 241, 247, 0.06)),
    linear-gradient(180deg, rgba(38, 40, 48, 0.94), rgba(21, 24, 31, 0.94));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.18),
    0 14px 28px rgba(0, 0, 0, 0.32),
    0 0 22px rgba(126, 255, 161, 0.08);
}

.evil-shell .nav-tab-inactive {
  color: #a9b6c4;
  border-color: rgba(137, 108, 178, 0.18);
  background: rgba(255, 255, 255, 0.04);
  backdrop-filter: blur(10px);
}

.evil-shell .nav-tab-inactive:hover {
  color: #d5ffe0;
  border-color: rgba(126, 255, 161, 0.18);
  background: rgba(126, 255, 161, 0.08);
  transform: translateY(-1px);
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

.war-shell .merged-header-glow {
  background: radial-gradient(circle, rgba(187, 198, 209, 0.16) 0%, rgba(135, 147, 159, 0.08) 42%, transparent 74%);
}

.evil-shell .merged-header-glow {
  background: radial-gradient(circle, rgba(177, 128, 255, 0.24) 0%, rgba(177, 128, 255, 0.1) 42%, transparent 74%);
}

.war-shell .nav-tab-active {
  color: #d7e0e8;
  border-color: rgba(182, 144, 91, 0.24);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0.04)),
    linear-gradient(145deg, rgba(62, 72, 82, 0.92), rgba(35, 43, 51, 0.96));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.14),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03),
    0 14px 28px rgba(0, 0, 0, 0.32),
    0 0 0 1px rgba(182, 144, 91, 0.06);
}

.war-shell .nav-tab-inactive {
  color: #8291a0;
  border-color: rgba(164, 176, 189, 0.14);
  background: rgba(255, 255, 255, 0.03);
  backdrop-filter: blur(10px);
}

.war-shell .nav-tab-inactive:hover {
  color: #b9c5cf;
  border-color: rgba(182, 144, 91, 0.18);
  background: rgba(182, 144, 91, 0.06);
  transform: translateY(-1px);
}

@media (max-width: 640px) {
  .nav-tab-active,
  .nav-tab-inactive {
    min-width: 0;
    width: 100%;
  }
}
</style>
