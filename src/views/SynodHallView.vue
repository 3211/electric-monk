<template>
  <div :class="[activeTab === 'dark' ? 'evil-shell' : 'war-shell', 'min-h-screen']">
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="relative min-w-0">
            <div class="merged-header-glow" aria-hidden="true"></div>
            <h1 class="ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">
              {{ activeTab === 'dark' ? 'Reliquary' : (synod.inSynod ? 'Synod Hall' : 'Find a Synod') }}
            </h1>
            <p class="relative mt-1 text-sm text-theme-text-muted">
              {{ activeTab === 'dark' ? 'Ten Sacred Relics. Hold them or steal them.' : (synod.inSynod ? 'Unite in faith, wage holy war.' : 'Browse public Synods or found your own.') }}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <template v-if="activeTab === 'light'">
              <div v-if="synod.inSynod" class="chip status-chip gap-2 px-4 py-2 text-sm">
                <span class="text-lg">&#x2694;&#xFE0F;</span>
                <span>{{ synod.synodInfo?.name || 'Synod' }}</span>
                <span class="text-theme-text-muted">&#xB7; {{ synod.memberCount }} members</span>
              </div>
              <div v-else class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim">
                <span class="text-theme-text-muted">No Synod</span>
              </div>
            </template>
            <template v-else>
              <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim">
                <span class="text-lg">&#x1F3C6;</span>
                <span>Held: <span class="font-semibold text-theme-accent">{{ myRelicCount }}</span>/10</span>
              </div>
              <div v-if="economy.synodId" class="chip status-chip gap-2 px-4 py-2 text-sm">
                <span>&#x2694;&#xFE0F; Synod Steal Available</span>
              </div>
            </template>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Tab Switcher -->
      <div class="mb-8 flex justify-center">
        <div class="segmented-shell">
          <button
            @click="activeTab = 'light'"
            :class="activeTab === 'light' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            {{ synod.inSynod ? '\u2694\uFE0F Synod' : '\uD83D\uDD0D Find Synod' }}
          </button>
          <button
            v-if="synod.inSynod"
            @click="activeTab = 'dark'"
            :class="activeTab === 'dark' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            &#x1F3FA; Reliquary
          </button>
        </div>
      </div>

      <!-- ==================== SYNOD TAB ==================== -->
      <div v-if="activeTab === 'light'">
        <!-- Loading -->
        <div v-if="synod.loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">&#x26EA;</div>
          <p class="text-theme-text-dim">Gathering the faithful...</p>
        </div>

        <!-- Error -->
        <div v-else-if="synod.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">&#x26A0;&#xFE0F;</div>
          <p class="text-theme-purgatory-dark">{{ synod.error }}</p>
          <button @click="synod.fetchSynodInfo()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
        </div>

        <!-- ========== NOT IN A SYNOD: Browser + Create ========== -->
        <div v-else-if="!synod.inSynod" class="space-y-8">
          <!-- Create Synod -->
          <div class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Found a Synod</h2>
            <p class="text-sm text-theme-text-muted mb-4">Create a new Synod for 500 Gold. You will become its leader.</p>

            <div class="flex flex-col sm:flex-row gap-3 mb-4">
              <input
                v-model="newSynodName"
                type="text"
                placeholder="Enter Synod name..."
                class="form-field px-4 py-3 flex-1"
                maxlength="30"
              />
              <button
                @click="handleCreateSynod"
                :disabled="!newSynodName.trim() || synod.creating || economy.gold < 500"
                class="btn-primary px-6 py-3"
              >
                <span class="relative z-10 font-medium">
                  {{ synod.creating ? 'Founding...' : 'Found Synod (500 Gold)' }}
                </span>
              </button>
            </div>

            <!-- Privacy Toggle -->
            <div class="flex items-center gap-2 mb-4">
              <span class="text-xs text-theme-text-muted">Privacy:</span>
              <button
                @click="newSynodPrivacy = newSynodPrivacy === 'public' ? 'private' : 'public'"
                :class="newSynodPrivacy === 'public' ? 'btn-primary' : 'btn-secondary'"
                class="privacy-btn"
              >
                {{ newSynodPrivacy === 'public' ? 'Public' : 'Private' }}
              </button>
              <span class="text-xs text-theme-text-dim">{{ newSynodPrivacy === 'public' ? 'Visible in browser' : 'Invite only' }}</span>
            </div>

            <!-- Custom Message -->
            <div>
              <label class="text-sm text-theme-text-muted mb-1 block">Welcome Message (optional):</label>
              <textarea
                v-model="newSynodMessage"
                class="form-field px-4 py-2 w-full"
                rows="2"
                maxlength="500"
                placeholder="Rules, welcome message, or lore..."
              ></textarea>
            </div>

            <p v-if="economy.gold < 500" class="mt-2 text-xs text-theme-purgatory-dark">You need 500 Gold to found a Synod.</p>
          </div>

          <!-- Public Synod Browser -->
          <div class="glass-panel glass-panel-soft p-6 sm:p-8">
            <div class="flex items-center justify-between mb-4">
              <h2 class="ritual-heading text-2xl font-bold text-theme-text">Public Synods</h2>
              <button
                @click="handleRefreshBrowser"
                :disabled="synod.browsing"
                class="btn-ghost px-3 py-1 text-xs"
              >
                {{ synod.browsing ? 'Refreshing...' : 'Refresh' }}
              </button>
            </div>

            <div v-if="synod.browsing && synod.publicSynods.length === 0" class="text-center py-8 text-theme-text-muted text-sm">
              Loading public Synods...
            </div>

            <div v-else-if="synod.publicSynods.length === 0" class="text-center py-8 text-theme-text-muted text-sm">
              No public Synods available for your faction or allies.
            </div>

            <div v-else class="space-y-3">
              <div
                v-for="s in synod.publicSynods"
                :key="s.id"
                class="flex items-center justify-between p-4 rounded-[20px] border border-theme-border bg-theme-panel/40"
              >
                <div>
                  <h3 class="font-semibold text-theme-text">{{ s.name }}</h3>
                  <p class="text-xs text-theme-text-muted">
                    {{ s.member_count || 0 }} members &#xB7; Leader: {{ s.leader_name || 'Unknown' }}
                    <span v-if="s.sect_key" class="ml-2 text-theme-text-dim">{{ factionLabel(s.sect_key) }}</span>
                  </p>
                </div>
                <button
                  @click="handlePetition(s.id)"
                  :disabled="synod.petitioning || synod.myPetitionSynodId === s.id"
                  class="btn-secondary px-4 py-2 text-sm"
                >
                  <span v-if="synod.myPetitionSynodId === s.id" class="relative z-10 font-medium text-theme-text-muted">Pending...</span>
                  <span v-else class="relative z-10 font-medium">{{ synod.petitioning ? 'Requesting...' : 'Petition' }}</span>
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- ========== IN A SYNOD: Dashboard ========== -->
        <div v-else class="space-y-8">
          <!-- Custom Message Banner -->
          <div v-if="synod.synodInfo?.custom_message" class="glass-panel glass-panel-strong glass-gloss p-5 border border-theme-accent/15">
            <p class="text-sm text-theme-text italic">{{ synod.synodInfo.custom_message }}</p>
          </div>

          <!-- Synod Info -->
          <div class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
              <div>
                <h2 class="ritual-heading text-2xl font-bold text-theme-text">{{ synod.synodInfo?.name }}</h2>
                <p class="text-sm text-theme-text-muted mt-1">
                  {{ synod.isLeader ? 'You are the Leader' : 'Your Role: ' + (synod.currentUserRole === 'officer' ? 'Steward' : 'Member') }}
                  &#xB7; {{ synod.memberCount }} members
                  &#xB7; {{ synod.synodInfo?.privacy === 'private' ? 'Private' : 'Public' }}
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
                <div class="text-xs text-theme-text-muted mt-1">Vault Gold</div>
              </div>
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-blue-400">{{ synod.synodInfo?.tax_rate || 0 }}%</div>
                <div class="text-xs text-theme-text-muted mt-1">Tax Rate</div>
              </div>
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-theme-text">{{ synod.synodInfo?.sect_key ? factionLabel(synod.synodInfo.sect_key) : '-' }}</div>
                <div class="text-xs text-theme-text-muted mt-1">Faction</div>
              </div>
            </div>
          </div>

          <!-- Leader Settings -->
          <div v-if="synod.isLeader" class="glass-panel glass-panel-soft p-6 sm:p-8">
            <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">Synod Settings</h3>
            <div class="space-y-4">
              <!-- Privacy -->
              <div class="flex items-center gap-2">
                <span class="text-xs text-theme-text-muted">Privacy:</span>
                <button
                  @click="handleUpdatePrivacy(synod.synodInfo?.privacy === 'public' ? 'private' : 'public')"
                  :disabled="synod.managing"
                  :class="synod.synodInfo?.privacy === 'public' ? 'btn-primary' : 'btn-secondary'"
                  class="privacy-btn"
                >
                  {{ synod.synodInfo?.privacy === 'public' ? 'Public' : 'Private' }}
                </button>
              </div>
              <!-- Message -->
              <div>
                <label class="text-sm text-theme-text-muted block mb-1">Welcome Message:</label>
                <div class="flex gap-3">
                  <textarea
                    v-model="editMessage"
                    class="form-field px-4 py-2 flex-1"
                    rows="2"
                    maxlength="500"
                    :placeholder="synod.synodInfo?.custom_message || 'Enter welcome message...'"
                  ></textarea>
                  <button
                    @click="handleUpdateMessage"
                    :disabled="synod.managing"
                    class="btn-secondary px-4 py-2 text-sm self-end"
                  >
                    Save
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Synod Relic Buffs -->
          <div v-if="synod.synodRelics && synod.synodRelics.length > 0" class="glass-panel glass-panel-soft p-6 sm:p-8">
            <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">Synod Relic Buffs</h3>
            <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <div
                v-for="relic in synod.synodRelics"
                :key="relic.id"
                class="flex items-center gap-3 p-3 rounded-[16px] border border-theme-accent/20 bg-theme-accent/5"
              >
                <span class="text-2xl">&#x1F3FA;</span>
                <div class="min-w-0 flex-1">
                  <div class="font-medium text-theme-text text-sm truncate">{{ relic.name }}</div>
                  <div class="text-xs text-theme-text-muted">held by {{ relic.holder_name || 'Unknown' }}</div>
                </div>
                <span class="chip status-chip text-xs">Active</span>
              </div>
            </div>
          </div>

          <!-- Applicant Queue (Leader/Steward only) -->
          <div v-if="canManage && synod.applicants.length > 0" class="glass-panel glass-panel-soft p-6 sm:p-8 border border-theme-accent/15">
            <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">Applicant Queue ({{ synod.applicants.length }})</h3>
            <div class="space-y-3">
              <div
                v-for="app in synod.applicants"
                :key="app.user_id"
                class="flex items-center justify-between p-3 rounded-[16px] border border-theme-border/50 bg-theme-panel/30"
              >
                <div>
                  <div class="font-medium text-theme-text text-sm">{{ app.username }}</div>
                  <div class="text-xs text-theme-text-muted">{{ app.sect_type ? factionLabel(app.sect_type) : 'No faction' }}</div>
                </div>
                <div class="flex gap-2">
                  <button @click="handleApprove(app.user_id)" :disabled="synod.managing" class="btn-primary px-3 py-1 text-xs">Approve</button>
                  <button @click="handleReject(app.user_id)" :disabled="synod.managing" class="btn-danger px-3 py-1 text-xs">Reject</button>
                </div>
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
                    <div class="text-xs text-theme-text-muted capitalize">{{ member.role === 'officer' ? 'Steward' : member.role }}</div>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <div class="text-xs text-theme-text-muted">
                    Joined {{ formatDate(member.joined_at) }}
                  </div>
                  <template v-if="canManageMember(member)">
                    <button
                      v-if="member.role === 'member' && synod.isLeader"
                      @click="handlePromote(member.user_id)"
                      :disabled="synod.managing"
                      class="btn-secondary px-2 py-1 text-xs"
                      title="Promote to Steward"
                    >&#x2B06;&#xFE0F;</button>
                    <button
                      v-if="member.role === 'officer' && synod.isLeader"
                      @click="handleDemote(member.user_id)"
                      :disabled="synod.managing"
                      class="btn-secondary px-2 py-1 text-xs"
                      title="Demote to Member"
                    >&#x2B07;&#xFE0F;</button>
                    <button
                      v-if="member.user_id !== currentUserId"
                      @click="handleKick(member.user_id, member.username)"
                      :disabled="synod.managing"
                      class="btn-danger px-2 py-1 text-xs"
                      title="Kick Member"
                    >&#x1F6AB;</button>
                  </template>
                </div>
              </div>
            </div>
          </div>

          <!-- Holy Wars -->
          <div class="glass-panel glass-panel-soft p-6 sm:p-8">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
              <h3 class="ritual-heading text-xl font-bold text-theme-text">Holy Wars</h3>
            </div>

            <div v-if="synod.wars.length === 0" class="text-center py-8 text-theme-text-muted text-sm">
              No active Holy Wars. {{ synod.isLeader ? 'Visit the Holy Wars page to declare one.' : '' }}
            </div>
            <div v-else class="space-y-4">
              <div
                v-for="war in synod.wars"
                :key="war.id"
                class="p-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/5"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <h4 class="font-semibold text-theme-text">Holy War</h4>
                    <p class="text-xs text-theme-text-muted mt-1">
                      Declared {{ formatDate(war.declared_at) }}
                    </p>
                  </div>
                  <span class="chip status-chip text-xs">Active</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ==================== RELIQUARY TAB ==================== -->
      <div v-if="activeTab === 'dark' && synod.inSynod">
        <div v-if="relics.loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">&#x2728;</div>
          <p class="text-theme-text-dim">Summoning the sacred artifacts...</p>
        </div>

        <div v-else-if="relics.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">&#x26A0;&#xFE0F;</div>
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
                <div class="flex h-14 w-14 items-center justify-center rounded-[20px] border border-theme-border bg-theme-panel/60 text-3xl">
                  {{ relic.icon || '\uD83C\uDFFA' }}
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
                  <div class="text-sm font-semibold text-yellow-500">{{ relic.steal_cost || 50 }} Gold</div>
                </div>
              </div>

              <div class="rounded-[16px] border border-theme-border/50 bg-theme-panel/30 p-3 mb-4">
                <div v-if="relic.holder_id" class="flex items-center gap-2">
                  <span class="text-lg">&#x1F451;</span>
                  <div>
                    <div class="text-sm font-medium text-theme-text">{{ relic.holder_name || 'Unknown' }}</div>
                    <div class="text-xs text-theme-text-muted">Held since {{ formatDate(relic.captured_at) }}</div>
                  </div>
                </div>
                <div v-else class="text-center text-sm text-theme-text-muted py-1">
                  &#x2726; Unclaimed
                </div>
              </div>

              <div v-if="relic.holder_id && relic.holder_id !== currentUserId && isRelicFromSynodMember(relic)" class="rounded-[14px] border border-theme-accent/30 bg-theme-accent/5 p-2 mb-4 text-center">
                <span class="text-xs text-theme-accent font-medium">&#x2694;&#xFE0F; Synod Buff Active</span>
              </div>

              <button
                v-if="relic.holder_id !== currentUserId"
                @click="handleSteal(relic.id)"
                :disabled="relics.stealing || !economy.synodId"
                class="btn-secondary w-full py-2.5 text-sm"
              >
                <span class="relative z-10 font-medium">
                  {{ !economy.synodId ? 'Requires Synod' : (relics.stealing ? 'Stealing...' : '\u2694\uFE0F Attempt Steal') }}
                </span>
              </button>
              <div v-else class="text-center py-2">
                <span class="chip status-chip text-xs">&#x2713; In Your Possession</span>
              </div>
            </div>
          </div>

          <!-- Indulgences -->
          <div class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
            <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-2">Indulgences</h2>
            <p class="text-sm text-theme-text-muted mb-6">Premium blessings purchased with devotion.</p>

            <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-5">
                <div class="flex items-center gap-3 mb-3">
                  <span class="text-3xl">&#x1F402;</span>
                  <div>
                    <h4 class="font-semibold text-theme-text">Papal Bull</h4>
                    <p class="text-xs text-theme-text-muted">12h Crusade Immunity</p>
                  </div>
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
                  <span class="text-xs text-green-600 font-medium">&#x1F6E1;&#xFE0F; Protected</span>
                </div>
              </div>

              <div class="rounded-[20px] border border-theme-border bg-theme-panel/40 p-5">
                <div class="flex items-center gap-3 mb-3">
                  <span class="text-3xl">&#x1F3D7;&#xFE0F;</span>
                  <div>
                    <h4 class="font-semibold text-theme-text">Divine Architect</h4>
                    <p class="text-xs text-theme-text-muted">Instant Build Queue</p>
                  </div>
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
                  <span class="text-xs text-green-600 font-medium">&#x26A1; Building</span>
                </div>
              </div>

              <div class="rounded-[20px] border border-theme-accent/20 bg-theme-accent/5 p-5 text-center">
                <div class="text-4xl mb-2">&#x2728;</div>
                <h4 class="font-semibold text-theme-text mb-1">Indulgence Balance</h4>
                <div class="text-3xl font-bold text-theme-accent">{{ economy.indulgences || 0 }}</div>
                <p class="text-xs text-theme-text-muted mt-2">Purchase indulgences via the Karma Shop</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>

    <!-- Confirm Action Modal -->
    <Teleport to="body">
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
const forceWarTheme = inject('forceWarTheme', ref(false))
const activeTab = ref('light')

const newSynodName = ref('')
const newSynodPrivacy = ref('public')
const newSynodMessage = ref('')
const editMessage = ref('')
const confirmAction = ref(null)

const currentUserId = computed(() => auth.user?.id)
const myRelicCount = computed(() => relics.heldRelics(currentUserId.value)?.length || 0)

const canManage = computed(() => {
  return synod.currentUserRole === 'leader' || synod.currentUserRole === 'officer'
})

const sortedMembers = computed(() => {
  const roleOrder = { leader: 0, officer: 1, member: 2 }
  return [...(synod.members || [])].sort((a, b) => {
    return (roleOrder[a.role] ?? 99) - (roleOrder[b.role] ?? 99)
  })
})

const FACTION_NAMES = {
  gilded_path: 'The Gilded Path',
  holy_way: 'The Holy Way',
  final_watch: 'The Final Watch',
  black_tribunal: 'The Black Tribunal',
}

function factionLabel(key) {
  return FACTION_NAMES[key] || key || 'Unknown'
}

watch(activeTab, (tab) => {
  forceEvilTheme.value = (tab === 'dark')
  forceWarTheme.value = (tab === 'light')
}, { immediate: true })

function roleIcon(role) {
  switch (role) {
    case 'leader': return '\uD83D\uDC51'
    case 'officer': return '\uD83D\uDEE1\uFE0F'
    default: return '\uD83D\uDD4A\uFE0F'
  }
}

function canManageMember(member) {
  if (!synod.currentUserRole) return false
  if (member.user_id === currentUserId.value) return false
  if (synod.currentUserRole === 'leader') return true
  if (synod.currentUserRole === 'officer' && member.role === 'member') return true
  return false
}

function isRelicFromSynodMember(relic) {
  if (!synod.synodRelics || !economy.synodId) return false
  return synod.synodRelics.some(r => r.id === relic.id)
}

function formatDate(dateString) {
  if (!dateString) return 'N/A'
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

async function handleCreateSynod() {
  if (!newSynodName.value.trim()) return
  try {
    await synod.createSynod(newSynodName.value.trim(), {
      privacy: newSynodPrivacy.value,
      customMessage: newSynodMessage.value || null,
    })
    newSynodName.value = ''
    newSynodMessage.value = ''
  } catch { /* captured in synod.error */ }
}

async function handleRefreshBrowser() {
  await synod.fetchPublicSynods()
}

async function handlePetition(synodId) {
  try {
    await synod.petitionSynod(synodId)
  } catch { /* captured in synod.error */ }
}

async function handleLeaveSynod() {
  if (!confirm('Are you sure you want to leave your Synod?')) return
  try { await synod.leaveSynod() } catch { /* captured */ }
}

async function handleUpdatePrivacy(privacy) {
  try { await synod.updatePrivacy(privacy) } catch { /* captured */ }
}

async function handleUpdateMessage() {
  try {
    await synod.updateMessage(editMessage.value || null)
    editMessage.value = ''
  } catch { /* captured */ }
}

async function handleApprove(userId) {
  try { await synod.approveApplicant(userId) } catch { /* captured */ }
}

async function handleReject(userId) {
  try { await synod.rejectApplicant(userId) } catch { /* captured */ }
}

function handlePromote(userId) {
  confirmAction.value = {
    title: 'Promote to Steward',
    message: 'Promote this member to Steward? They can approve applicants and kick regular members.',
    buttonText: 'Promote',
    danger: false,
    handler: () => synod.promoteMember(userId),
  }
}

function handleDemote(userId) {
  confirmAction.value = {
    title: 'Demote Steward',
    message: 'Demote this steward to regular member?',
    buttonText: 'Demote',
    danger: false,
    handler: () => synod.demoteMember(userId),
  }
}

function handleKick(userId, username) {
  confirmAction.value = {
    title: 'Kick Member',
    message: `Kick ${username || 'this member'} from the Synod?`,
    buttonText: 'Kick',
    danger: true,
    handler: () => synod.kickMember(userId),
  }
}

async function handleSteal(relicId) {
  try { await relics.attemptSteal(relicId) } catch { /* captured */ }
}

async function handleActivatePapalBull() {
  try { await indulgences.activatePapalBull() } catch { /* captured */ }
}

async function handleActivateDivineArchitect() {
  try { await indulgences.activateDivineArchitect() } catch { /* captured */ }
}

onMounted(() => {
  synod.fetchSynodInfo()
  synod.fetchPublicSynods()
  relics.fetchRelics()
  indulgences.fetchActiveMiracles()
})
</script>

<style scoped>
.nav-tab-active,
.nav-tab-inactive {
  min-width: 10rem;
}

.nav-tab-active {
  color: #d7e0e8;
  border: 1px solid rgba(182, 144, 91, 0.24);
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0.04)), linear-gradient(145deg, rgba(62, 72, 82, 0.92), rgba(35, 43, 51, 0.96));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.14), inset 0 -1px 0 rgba(255, 255, 255, 0.03), 0 14px 28px rgba(0, 0, 0, 0.32), 0 0 0 1px rgba(182, 144, 91, 0.06);
  border-radius: 999px;
  padding: 0.625rem 2rem;
  font-weight: 600;
  cursor: pointer;
}

.nav-tab-inactive {
  color: #8291a0;
  border: 1px solid rgba(164, 176, 189, 0.14);
  background: rgba(255, 255, 255, 0.03);
  backdrop-filter: blur(10px);
  border-radius: 999px;
  padding: 0.625rem 2rem;
  font-weight: 500;
  cursor: pointer;
}

.nav-tab-inactive:hover {
  color: #b9c5cf;
  border-color: rgba(182, 144, 91, 0.18);
  background: rgba(182, 144, 91, 0.06);
  transform: translateY(-1px);
}

.segmented-shell {
  display: flex;
  gap: 0.5rem;
}

.evil-shell .nav-tab-active {
  color: #f2f5f7;
  border-color: rgba(126, 255, 161, 0.24);
  background: linear-gradient(180deg, rgba(233, 241, 247, 0.16), rgba(233, 241, 247, 0.06)), linear-gradient(180deg, rgba(38, 40, 48, 0.94), rgba(21, 24, 31, 0.94));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.18), 0 14px 28px rgba(0, 0, 0, 0.32), 0 0 22px rgba(126, 255, 161, 0.08);
}

.evil-shell .nav-tab-inactive {
  color: #a9b6c4;
  border-color: rgba(137, 108, 178, 0.18);
  background: rgba(255, 255, 255, 0.04);
}

.evil-shell .nav-tab-inactive:hover {
  color: #d5ffe0;
  border-color: rgba(126, 255, 161, 0.18);
  background: rgba(126, 255, 161, 0.08);
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

.privacy-btn {
  padding: 0.25rem 0.75rem;
  font-size: 0.65rem;
  border-radius: 999px;
  line-height: 1.25;
  font-weight: 500;
  border: 1px solid transparent;
  cursor: pointer;
}

@media (max-width: 640px) {
  .nav-tab-active,
  .nav-tab-inactive {
    min-width: 0;
    width: 100%;
  }
}
</style>