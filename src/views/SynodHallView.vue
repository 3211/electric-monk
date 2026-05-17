<template>
  <div :class="[activeTab === 'dark' ? 'evil-shell' : '', 'min-h-screen']">
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="relative min-w-0">
            <div class="merged-header-glow" aria-hidden="true"></div>
            <h1 class="ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">
              {{ activeTab === 'light' ? 'Synod Hall' : 'Reliquary' }}
            </h1>
            <p class="relative mt-1 text-sm text-theme-text-muted">
              {{ activeTab === 'light' ? 'Unite in faith, wage holy war.' : 'Ten Sacred Relics. Hold them or steal them.' }}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <template v-if="activeTab === 'light'">
              <div v-if="synod.inSynod" class="chip status-chip gap-2 px-4 py-2 text-sm">
                <span class="text-lg">⚔️</span>
                <span>{{ synod.synodInfo?.name || 'Synod' }}</span>
                <span class="text-theme-text-muted">· {{ synod.memberCount }} members</span>
              </div>
              <div v-else class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span class="text-theme-text-muted">No Synod</span>
              </div>
            </template>
            <template v-else>
              <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                <span class="text-lg">🏆</span>
                <span>Held: <span class="font-semibold text-theme-accent">{{ myRelicCount }}</span>/10</span>
              </div>
              <div v-if="economy.synodId" class="chip status-chip gap-2 px-4 py-2 text-sm">
                <span>⚔️ Synod Steal Available</span>
              </div>
            </template>
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
            ⚔️ Synod
          </button>
          <button
            @click="activeTab = 'dark'"
            :class="activeTab === 'dark' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            🏺 Reliquary
          </button>
        </div>
      </div>

      <div v-if="activeTab === 'light'">
        <!-- Loading -->
        <div v-if="synod.loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">⛪</div>
          <p class="text-theme-text-dim">Gathering the faithful...</p>
        </div>

        <!-- Error -->
        <div v-else-if="synod.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="text-theme-purgatory-dark">{{ synod.error }}</p>
          <button @click="synod.fetchSynodInfo()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
        </div>

        <!-- Not in a Synod -->
        <div v-else-if="!synod.inSynod" class="space-y-8">
          <div class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Found a Synod</h2>
            <p class="text-sm text-theme-text-muted mb-6">Create a new Synod for 500 Gold. You will become its leader.</p>
            <div class="flex flex-col sm:flex-row gap-3">
              <input
                v-model="newSynodName"
                type="text"
                placeholder="Enter Synod name..."
                class="form-field px-4 py-3 flex-1"
                maxlength="30"
                @keyup.enter="handleCreateSynod"
              />
              <button
                @click="handleCreateSynod"
                :disabled="!newSynodName.trim() || synod.creating || economy.gold < 100"
                class="btn-primary px-6 py-3"
              >
                <span class="relative z-10 font-medium">
                  {{ synod.creating ? 'Founding...' : 'Found Synod (100 💰)' }}
                </span>
              </button>
            </div>
            <p v-if="economy.gold < 100" class="mt-2 text-xs text-theme-purgatory-dark">You need 100 Gold to found a Synod.</p>
          </div>

          <div class="glass-panel glass-panel-soft p-6 sm:p-8">
            <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Join a Synod</h2>
            <p class="text-sm text-theme-text-muted mb-4">Search for an existing Synod to join.</p>
            <div class="flex flex-col sm:flex-row gap-3 mb-6">
              <input
                v-model="searchQuery"
                type="text"
                placeholder="Search by name..."
                class="form-field px-4 py-3 flex-1"
                @keyup.enter="handleSearchSynods"
              />
              <button @click="handleSearchSynods" :disabled="!searchQuery.trim()" class="btn-secondary px-6 py-3">
                <span class="relative z-10 font-medium">Search</span>
              </button>
            </div>

            <div v-if="searchResults.length > 0" class="space-y-3">
              <div
                v-for="synodItem in searchResults"
                :key="synodItem.id"
                class="flex items-center justify-between p-4 rounded-[20px] border border-theme-border bg-theme-panel/40"
              >
                <div>
                  <h3 class="font-semibold text-theme-text">{{ synodItem.name }}</h3>
                  <p class="text-xs text-theme-text-muted">{{ synodItem.member_count || 0 }} members · Vault: {{ synodItem.vault_gold || 0 }} 💰</p>
                </div>
                <button
                  @click="handleJoinSynod(synodItem.id)"
                  :disabled="synod.joining"
                  class="btn-secondary px-4 py-2 text-sm"
                >
                  <span class="relative z-10 font-medium">{{ synod.joining ? 'Joining...' : 'Join' }}</span>
                </button>
              </div>
            </div>
            <div v-else-if="hasSearched" class="text-center py-6 text-theme-text-muted text-sm">
              No Synods found matching "{{ searchQuery }}"
            </div>
          </div>
        </div>

        <!-- In a Synod -->
        <div v-else class="space-y-8">
          <div class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
              <div>
                <h2 class="ritual-heading text-2xl font-bold text-theme-text">{{ synod.synodInfo?.name }}</h2>
                <p class="text-sm text-theme-text-muted mt-1">
                  {{ synod.isLeader ? 'You are the Leader' : `Leader: ${synod.synodInfo?.leader_name || 'Unknown'}` }}
                  · {{ synod.memberCount }} members
                </p>
              </div>
              <div class="flex gap-3">
                <button @click="handleLeaveSynod" :disabled="synod.loading" class="btn-danger px-4 py-2 text-sm">
                  <span class="relative z-10 font-medium">Leave Synod</span>
                </button>
              </div>
            </div>

            <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-theme-accent">{{ synod.memberCount }}</div>
                <div class="text-xs text-theme-text-muted mt-1">Members</div>
              </div>
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-yellow-500">{{ synod.synodInfo?.vault_gold || 0 }}</div>
                <div class="text-xs text-theme-text-muted mt-1">Vault 💰</div>
              </div>
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-blue-400">{{ synod.synodInfo?.tax_rate || 0 }}%</div>
                <div class="text-xs text-theme-text-muted mt-1">Tax Rate</div>
              </div>
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-green-600">{{ synod.synodInfo?.level || 1 }}</div>
                <div class="text-xs text-theme-text-muted mt-1">Level</div>
              </div>
            </div>
          </div>

          <!-- Synod Relic Buffs -->
          <div v-if="synod.synodRelics && synod.synodRelics.length > 0" class="glass-panel glass-panel-soft p-6 sm:p-8">
            <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">Synod Relic Buffs</h3>
            <p class="text-sm text-theme-text-muted mb-4">Relics held by your Synod members benefit the entire Synod.</p>
            <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <div
                v-for="relic in synod.synodRelics"
                :key="relic.id"
                class="flex items-center gap-3 p-3 rounded-[16px] border border-theme-accent/20 bg-theme-accent/5"
              >
                <span class="text-2xl">🏺</span>
                <div class="min-w-0 flex-1">
                  <div class="font-medium text-theme-text text-sm truncate">{{ relic.name }}</div>
                  <div class="text-xs text-theme-text-muted">held by {{ relic.holder_name || 'Unknown' }}</div>
                </div>
                <span class="chip status-chip text-xs">Active</span>
              </div>
            </div>
          </div>

          <!-- Members -->
          <div class="glass-panel glass-panel-soft p-6 sm:p-8">
            <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">Members</h3>
            <div v-if="synod.members.length === 0" class="text-center py-6 text-theme-text-muted text-sm">
              No members found.
            </div>
            <div v-else class="space-y-2">
              <div
                v-for="member in sortedMembers"
                :key="member.user_id"
                class="flex items-center justify-between p-3 rounded-[16px] border border-theme-border/50 bg-theme-panel/30"
              >
                <div class="flex items-center gap-3">
                  <span class="text-lg">{{ roleIcon(member.role) }}</span>
                  <div>
                    <div class="font-medium text-theme-text text-sm">{{ member.username || 'Unknown' }}</div>
                    <div class="text-xs text-theme-text-muted capitalize">{{ member.role || 'member' }}</div>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <div class="text-xs text-theme-text-muted">
                    Joined {{ formatDate(member.joined_at) }}
                  </div>
                  <!-- Management buttons (visible to leaders and officers) -->
                  <template v-if="canManageMember(member)">
                    <button
                      v-if="member.role === 'member' && synod.isLeader"
                      @click="handlePromote(member.user_id)"
                      :disabled="synod.managing"
                      class="btn-secondary px-2 py-1 text-xs"
                      title="Promote to Officer"
                    >
                      ⬆️
                    </button>
                    <button
                      v-if="member.role === 'officer' && synod.isLeader"
                      @click="handleDemote(member.user_id)"
                      :disabled="synod.managing"
                      class="btn-secondary px-2 py-1 text-xs"
                      title="Demote to Member"
                    >
                      ⬇️
                    </button>
                    <button
                      v-if="member.user_id !== currentUserId"
                      @click="handleKick(member.user_id, member.username)"
                      :disabled="synod.managing"
                      class="btn-danger px-2 py-1 text-xs"
                      title="Kick Member"
                    >
                      �-boot
                    </button>
                  </template>
                </div>
              </div>
            </div>
          </div>

          <!-- Holy Wars -->
          <div class="glass-panel glass-panel-soft p-6 sm:p-8">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
              <h3 class="ritual-heading text-xl font-bold text-theme-text">Holy Wars</h3>
              <button
                v-if="synod.isLeader"
                @click="showWarDeclaration = true"
                class="btn-primary px-4 py-2 text-sm"
              >
                <span class="relative z-10 font-medium">⚔️ Declare War</span>
              </button>
            </div>

            <div v-if="synod.wars.length === 0" class="text-center py-8 text-theme-text-muted text-sm">
              No active Holy Wars. {{ synod.isLeader ? 'Declare one!' : '' }}
            </div>
            <div v-else class="space-y-4">
              <div
                v-for="war in synod.wars"
                :key="war.id"
                class="p-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/5"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <h4 class="font-semibold text-theme-text">vs. {{ war.target_name || 'Enemy Synod' }}</h4>
                    <p class="text-xs text-theme-text-muted mt-1">
                      {{ war.status }} · Started {{ formatDate(war.declared_at) }}
                    </p>
                  </div>
                  <span class="chip text-xs" :class="war.status === 'active' ? 'status-chip' : ''">
                    {{ war.status }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div v-if="activeTab === 'dark'">
        <div v-if="relics.loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">✨</div>
          <p class="text-theme-text-dim">Summoning the sacred artifacts...</p>
        </div>

        <div v-else-if="relics.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">⚠️</div>
          <p class="text-theme-purgatory-dark">{{ relics.error }}</p>
          <button @click="relics.fetchRelics()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
        </div>

        <div v-else class="space-y-10">
          <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <div
              v-for="relic in relics.relics"
              :key="relic.id"
              class="glass-panel glass-panel-soft p-5 sm:p-6 transition-all duration-[var(--dur-standard)] hover:shadow-glow-gold"
              :class="{ 'ring-1 ring-theme-accent/30': relic.holder_id === currentUserId }"
            >
              <div class="flex items-start gap-4 mb-4">
                <div class="flex h-14 w-14 items-center justify-center rounded-[20px] border border-theme-border bg-theme-panel/60 text-3xl shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
                  {{ relic.icon || '🏺' }}
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="ritual-heading text-lg font-bold text-theme-text truncate">{{ relic.name }}</h3>
                  <p class="text-xs text-theme-text-muted mt-0.5 line-clamp-2">{{ relic.description }}</p>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-3 mb-4">
                <div class="rounded-[14px] border border-theme-border/50 bg-theme-panel/30 p-2.5 text-center">
                  <div class="text-xs text-theme-text-muted">Power</div>
                  <div class="text-sm font-semibold text-theme-accent">{{ relic.power_level || 1 }}</div>
                </div>
                <div class="rounded-[14px] border border-theme-border/50 bg-theme-panel/30 p-2.5 text-center">
                  <div class="text-xs text-theme-text-muted">Steal Cost</div>
                  <div class="text-sm font-semibold text-yellow-500">{{ relic.steal_cost || 50 }} 💰</div>
                </div>
              </div>

              <div class="rounded-[16px] border border-theme-border/50 bg-theme-panel/30 p-3 mb-4">
                <div v-if="relic.holder_id" class="flex items-center gap-2">
                  <span class="text-lg">👑</span>
                  <div>
                    <div class="text-sm font-medium text-theme-text">{{ relic.holder_name || 'Unknown' }}</div>
                    <div class="text-xs text-theme-text-muted">
                      Held since {{ formatDate(relic.captured_at) }}
                    </div>
                  </div>
                </div>
                <div v-else class="text-center text-sm text-theme-text-muted py-1">
                  ✦ Unclaimed — Free for the taking
                </div>
              </div>

              <!-- Show synod-wide buff indicator if holder is in your synod -->
              <div v-if="relic.holder_id && relic.holder_id !== currentUserId && isRelicFromSynodMember(relic)" class="rounded-[14px] border border-theme-accent/30 bg-theme-accent/5 p-2 mb-4 text-center">
                <span class="text-xs text-theme-accent font-medium">⚔️ Synod Buff Active</span>
              </div>

              <button
                v-if="relic.holder_id !== currentUserId"
                @click="handleSteal(relic.id)"
                :disabled="relics.stealing || !economy.synodId"
                class="btn-secondary w-full py-2.5 text-sm"
              >
                <span class="relative z-10 font-medium">
                  {{ !economy.synodId ? 'Requires Synod' : (relics.stealing ? 'Stealing...' : '⚔️ Attempt Steal') }}
                </span>
              </button>
              <div v-else class="text-center py-2">
                <span class="chip status-chip text-xs">✓ In Your Possession</span>
              </div>
            </div>
          </div>

          <div v-if="!relics.loading && !relics.error && relics.relics.length === 0" class="glass-panel glass-panel-soft p-12 text-center">
            <div class="text-5xl mb-4">🏺</div>
            <h3 class="mb-2 text-2xl font-medium text-theme-text">The Reliquary is Empty</h3>
            <p class="text-theme-text-dim">The relics have not yet materialized. Check back soon.</p>
          </div>

          <div class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-2">Indulgences</h2>
            <p class="text-sm text-theme-text-muted mb-6">Premium blessings purchased with devotion.</p>

            <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-5">
                <div class="flex items-center gap-3 mb-3">
                  <span class="text-3xl">🐂</span>
                  <div>
                    <h4 class="font-semibold text-theme-text">Papal Bull</h4>
                    <p class="text-xs text-theme-text-muted">12h Crusade Immunity</p>
                  </div>
                </div>
                <div v-if="indulgences.hasPapalBull" class="mb-3">
                  <span class="chip status-chip text-xs">✓ Active — {{ indulgences.papalBullRemaining }} remaining</span>
                </div>
                <div v-else class="mb-3">
                  <p class="text-xs text-theme-text-muted">Cost: 1 Indulgence</p>
                </div>
                <button
                  v-if="!indulgences.hasPapalBull"
                  @click="handleActivatePapalBull"
                  :disabled="indulgences.activating || (economy.indulgences || 0) < 1"
                  class="btn-primary w-full py-2 text-sm"
                >
                  <span class="relative z-10 font-medium">
                    {{ economy.indulgences < 1 ? 'No Indulgences' : (indulgences.activating ? 'Activating...' : 'Activate') }}
                  </span>
                </button>
                <div v-else class="text-center">
                  <span class="text-xs text-green-600 font-medium">🛡️ Protected</span>
                </div>
              </div>

              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-5">
                <div class="flex items-center gap-3 mb-3">
                  <span class="text-3xl">🏗️</span>
                  <div>
                    <h4 class="font-semibold text-theme-text">Divine Architect</h4>
                    <p class="text-xs text-theme-text-muted">Instant Build Queue</p>
                  </div>
                </div>
                <div v-if="indulgences.hasDivineArchitect" class="mb-3">
                  <span class="chip status-chip text-xs">✓ Active</span>
                </div>
                <div v-else class="mb-3">
                  <p class="text-xs text-theme-text-muted">Cost: 1 Indulgence</p>
                </div>
                <button
                  v-if="!indulgences.hasDivineArchitect"
                  @click="handleActivateDivineArchitect"
                  :disabled="indulgences.activating || (economy.indulgences || 0) < 1"
                  class="btn-primary w-full py-2 text-sm"
                >
                  <span class="relative z-10 font-medium">
                    {{ economy.indulgences < 1 ? 'No Indulgences' : (indulgences.activating ? 'Activating...' : 'Activate') }}
                  </span>
                </button>
                <div v-else class="text-center">
                  <span class="text-xs text-green-600 font-medium">⚡ Building</span>
                </div>
              </div>

              <div class="rounded-[20px] border border-theme-accent/20 bg-theme-accent/5 p-5 text-center">
                <div class="text-4xl mb-2">✨</div>
                <h4 class="font-semibold text-theme-text mb-1">Indulgence Balance</h4>
                <div class="text-3xl font-bold text-theme-accent">{{ economy.indulgences || 0 }}</div>
                <p class="text-xs text-theme-text-muted mt-2">Purchase indulgences via the Karma Shop</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>

    <Teleport to="body">
      <!-- War Declaration Modal (search-based) -->
      <div v-if="showWarDeclaration" class="fixed inset-0 z-50 flex items-center justify-center p-4" style="animation: overlay-fade var(--dur-standard) var(--ease-ritual-lift)">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="showWarDeclaration = false"></div>
        <div class="relative z-10 w-full max-w-md glass-panel glass-panel-strong glass-gloss p-6" style="animation: modal-rise var(--dur-enter) var(--ease-ritual-lift)">
          <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">⚔️ Declare Holy War</h3>
          <p class="text-sm text-theme-text-muted mb-4">Search for a Synod to declare war on. This costs 200 Gold from your Synod vault.</p>
          <div class="flex flex-col gap-3 mb-4">
            <input
              v-model="warSearchQuery"
              type="text"
              placeholder="Search Synod name..."
              class="form-field px-4 py-3"
              @keyup.enter="handleSearchWarTargets"
            />
            <button @click="handleSearchWarTargets" :disabled="!warSearchQuery.trim()" class="btn-secondary px-6 py-2">
              <span class="relative z-10 font-medium">Search</span>
            </button>
          </div>
          <div v-if="warSearchResults.length > 0" class="space-y-2 mb-4">
            <div
              v-for="target in warSearchResults"
              :key="target.id"
              class="flex items-center justify-between p-3 rounded-[16px] border border-theme-border/50 bg-theme-panel/30"
            >
              <div>
                <div class="font-medium text-theme-text text-sm">{{ target.name }}</div>
              </div>
              <button
                @click="handleDeclareWar(target.id)"
                :disabled="synod.declaring"
                class="btn-danger px-4 py-2 text-sm"
              >
                <span class="relative z-10 font-medium">{{ synod.declaring ? 'Declaring...' : 'Declare War' }}</span>
              </button>
            </div>
          </div>
          <div v-else-if="warSearchPerformed" class="text-center py-4 text-theme-text-muted text-sm">
            No Synods found matching "{{ warSearchQuery }}"
          </div>
          <div class="flex justify-end">
            <button @click="showWarDeclaration = false" class="btn-ghost px-4 py-2 text-sm">Cancel</button>
          </div>
        </div>
      </div>

      <!-- Promote/Demote Confirmation Modal -->
      <div v-if="confirmAction" class="fixed inset-0 z-50 flex items-center justify-center p-4" style="animation: overlay-fade var(--dur-standard) var(--ease-ritual-lift)">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="confirmAction = null"></div>
        <div class="relative z-10 w-full max-w-sm glass-panel glass-panel-strong glass-gloss p-6" style="animation: modal-rise var(--dur-enter) var(--ease-ritual-lift)">
          <h3 class="ritual-heading text-lg font-bold text-theme-text mb-3">{{ confirmAction.title }}</h3>
          <p class="text-sm text-theme-text-muted mb-4">{{ confirmAction.message }}</p>
          <div class="flex gap-3 justify-end">
            <button @click="confirmAction = null" class="btn-ghost px-4 py-2 text-sm">Cancel</button>
            <button
              @click="confirmAction.handler(); confirmAction = null"
              :disabled="synod.managing"
              :class="confirmAction.danger ? 'btn-danger' : 'btn-primary'"
              class="px-4 py-2 text-sm"
            >
              <span class="relative z-10 font-medium">{{ synod.managing ? 'Processing...' : confirmAction.buttonText }}</span>
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, onMounted, computed, watch, inject } from 'vue'
import { useSynod } from '@/composables/useSynod'
import { useEconomy } from '@/composables/useEconomy'
import { useRelics } from '@/composables/useRelics'
import { useIndulgences } from '@/composables/useIndulgences'
import { useAuth } from '@/composables/useAuth'

const synod = useSynod()
const economy = useEconomy()
const relics = useRelics()
const indulgences = useIndulgences()
const auth = useAuth()

const forceEvilTheme = inject('forceEvilTheme', ref(false))
const activeTab = ref('light')

const newSynodName = ref('')
const searchQuery = ref('')
const searchResults = ref([])
const hasSearched = ref(false)
const showWarDeclaration = ref(false)
const warSearchQuery = ref('')
const warSearchResults = ref([])
const warSearchPerformed = ref(false)
const confirmAction = ref(null)

const currentUserId = computed(() => auth.user?.id)
const myRelicCount = computed(() => relics.heldRelics(currentUserId.value)?.length || 0)

// Sort members: leader first, then officers, then members
const sortedMembers = computed(() => {
  const roleOrder = { leader: 0, officer: 1, member: 2 }
  return [...(synod.members || [])].sort((a, b) => {
    const aRole = roleOrder[a.role] ?? 99
    const bRole = roleOrder[b.role] ?? 99
    return aRole - bRole
  })
})

watch(activeTab, (tab) => {
  forceEvilTheme.value = (tab === 'dark')
}, { immediate: true })

function roleIcon(role) {
  switch (role) {
    case 'leader': return '👑'
    case 'officer': return '🛡️'
    default: return '🕊️'
  }
}

function canManageMember(member) {
  if (!synod.currentUserRole) return false
  if (member.user_id === currentUserId.value) return false
  // Leaders can manage anyone
  if (synod.currentUserRole === 'leader') return true
  // Officers can manage members (not officers or leaders)
  if (synod.currentUserRole === 'officer' && member.role === 'member') return true
  return false
}

function isRelicFromSynodMember(relic) {
  if (!synod.synodRelics || !economy.synodId) return false
  return synod.synodRelics.some(r => r.id === relic.id)
}

async function handleCreateSynod() {
  if (!newSynodName.value.trim()) return
  try {
    await synod.createSynod(newSynodName.value.trim())
    newSynodName.value = ''
  } catch {
    // Error captured in composable
  }
}

async function handleSearchSynods() {
  if (!searchQuery.value.trim()) return
  try {
    const results = await synod.searchSynods(searchQuery.value.trim())
    searchResults.value = results || []
    hasSearched.value = true
  } catch {
    searchResults.value = []
    hasSearched.value = true
  }
}

async function handleJoinSynod(synodId) {
  try {
    await synod.joinSynod(synodId)
  } catch {
    // Error captured in composable
  }
}

async function handleLeaveSynod() {
  if (!confirm('Are you sure you want to leave your Synod? If you are the leader, leadership will transfer.')) return
  try {
    await synod.leaveSynod()
  } catch {
    // Error captured in composable
  }
}

function handlePromote(userId) {
  confirmAction.value = {
    title: 'Promote Member',
    message: 'Are you sure you want to promote this member? Officers can kick regular members.',
    buttonText: 'Promote',
    danger: false,
    handler: () => synod.promoteMember(userId),
  }
}

function handleDemote(userId) {
  confirmAction.value = {
    title: 'Demote Member',
    message: 'Are you sure you want to demote this officer to member?',
    buttonText: 'Demote',
    danger: false,
    handler: () => synod.demoteMember(userId),
  }
}

function handleKick(userId, username) {
  confirmAction.value = {
    title: 'Kick Member',
    message: `Are you sure you want to kick ${username || 'this member'} from the Synod?`,
    buttonText: 'Kick',
    danger: true,
    handler: () => synod.kickMember(userId),
  }
}

async function handleSearchWarTargets() {
  if (!warSearchQuery.value.trim()) return
  try {
    const results = await synod.searchSynods(warSearchQuery.value.trim())
    warSearchResults.value = results || []
    warSearchPerformed.value = true
  } catch {
    warSearchResults.value = []
    warSearchPerformed.value = true
  }
}

async function handleDeclareWar(targetSynodId) {
  try {
    await synod.declareHolyWar(targetSynodId)
    showWarDeclaration.value = false
    warSearchQuery.value = ''
    warSearchResults.value = []
    warSearchPerformed.value = false
  } catch {
    // Error captured in composable
  }
}

async function handleSteal(relicId) {
  try {
    await relics.attemptSteal(relicId)
  } catch {
    // Error captured in composable
  }
}

async function handleActivatePapalBull() {
  try {
    await indulgences.activatePapalBull()
  } catch {
    // Error captured in composable
  }
}

async function handleActivateDivineArchitect() {
  try {
    await indulgences.activateDivineArchitect()
  } catch {
    // Error captured in composable
  }
}

function formatDate(dateString) {
  if (!dateString) return 'N/A'
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

onMounted(() => {
  synod.fetchSynodInfo()
  relics.fetchRelics()
  indulgences.fetchActiveMiracles()
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

.evil-shell .merged-header-glow {
  background: radial-gradient(circle, rgba(177, 128, 255, 0.24) 0%, rgba(177, 128, 255, 0.1) 42%, transparent 74%);
}

@media (max-width: 640px) {
  .nav-tab-active,
  .nav-tab-inactive {
    min-width: 0;
    width: 100%;
  }
}
</style>