<template>
  <div :class="[activeTab === 'reliquary' ? 'evil-shell' : 'war-shell', 'min-h-screen']">
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="relative min-w-0">
            <div class="merged-header-glow" aria-hidden="true"></div>
            <h1 class="ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">
              {{ headerTitle }}
            </h1>
            <p class="relative mt-1 text-sm text-theme-text-muted">
              {{ headerSubtitle }}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <template v-if="activeTab === 'synod'">
              <div v-if="synod.inSynod" class="chip status-chip gap-2 px-4 py-2 text-sm">
                <span class="text-lg">&#x2694;&#xFE0F;</span>
                <span>{{ synod.synodInfo?.name || 'Synod' }}</span>
                <span class="text-theme-text-muted">&#xB7; {{ synod.memberCount }} members</span>
              </div>
              <div v-else class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim">
                <span class="text-theme-text-muted">No Synod</span>
              </div>
            </template>
            <template v-else-if="activeTab === 'reliquary'">
              <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim">
                <span class="text-lg">&#x1F3C6;</span>
                <span>Held: <span class="font-semibold text-theme-accent">{{ myRelicCount }}</span>/10</span>
              </div>
              <div v-if="economy.synodId" class="chip status-chip gap-2 px-4 py-2 text-sm">
                <span>&#x2694;&#xFE0F; Synod Steal Available</span>
              </div>
            </template>
            <template v-else-if="activeTab === 'war'">
              <div v-if="synod.hasActiveWar" class="chip status-chip gap-2 px-4 py-2 text-sm">
                At War
              </div>
              <div v-if="sr.underAttack" class="chip gap-2 px-4 py-2 text-sm text-theme-purgatory-dark border border-theme-purgatory/25 bg-theme-purgatory/5">
                &#x1F6E1;&#xFE0F; Under Attack by {{ sr.attackerName || 'Unknown' }}
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
            @click="activeTab = 'synod'"
            :class="activeTab === 'synod' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            {{ synod.inSynod ? '&#x2694;&#xFE0F; Synod' : '&#x1F50D; Find Synod' }}
          </button>
          <button
            v-if="synod.inSynod"
            @click="activeTab = 'forum'"
            :class="activeTab === 'forum' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            &#x1F4E2; Forum
          </button>
          <button
            v-if="synod.inSynod"
            @click="activeTab = 'reliquary'"
            :class="activeTab === 'reliquary' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            &#x1F3FA; Reliquary
          </button>
          <button
            v-if="synod.inSynod"
            @click="activeTab = 'war'"
            :class="activeTab === 'war' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            &#x2694;&#xFE0F; War
          </button>
          <button
            @click="activeTab = 'rankings'"
            :class="activeTab === 'rankings' ? 'nav-tab-active' : 'nav-tab-inactive'"
          >
            &#x1F3C6; Rankings
          </button>
        </div>
      </div>

      <!-- ==================== SYNOD TAB ==================== -->
      <div v-if="activeTab === 'synod'">
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
                class="flex items-center justify-between p-4 rounded-sm border border-theme-border bg-theme-panel/40"
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

            <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-4">
              <div class="rounded-sm border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-theme-accent">{{ synod.memberCount }}</div>
                <div class="text-xs text-theme-text-muted mt-1">Members</div>
              </div>
              <div class="rounded-sm border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-yellow-500">{{ synod.synodInfo?.vault_gold || 0 }}</div>
                <div class="text-xs text-theme-text-muted mt-1">Vault Gold</div>
              </div>
              <div class="rounded-sm border border-theme-border bg-theme-panel/40 p-4 text-center">
                <div class="text-2xl font-bold text-blue-400">{{ synod.synodInfo?.tax_rate || 0 }}%</div>
                <div class="text-xs text-theme-text-muted mt-1">Tax Rate</div>
              </div>
              <div class="rounded-sm border border-theme-border bg-theme-panel/40 p-4 text-center">
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
                class="flex items-center gap-3 p-3 rounded-sm border border-theme-accent/20 bg-theme-accent/5"
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
                class="flex items-center justify-between p-3 rounded-sm border border-theme-border/50 bg-theme-panel/30"
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
                class="flex items-center justify-between p-3 rounded-sm border border-theme-border/50 bg-theme-panel/30"
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

          <!-- Holy Wars (summary, shown in dashboard) -->
          <div v-if="synod.wars.length > 0" class="glass-panel glass-panel-soft p-6 sm:p-8">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
              <h3 class="ritual-heading text-xl font-bold text-theme-text">Holy Wars</h3>
            </div>

            <div class="space-y-4">
              <div
                v-for="war in synod.wars"
                :key="war.id"
                class="p-4 rounded-sm border border-theme-purgatory/25 bg-theme-purgatory/5"
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

      <!-- ==================== FORUM TAB ==================== -->
      <div v-if="activeTab === 'forum' && synod.inSynod" class="space-y-6">
        <!-- Forum Header -->
        <div class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
          <h2 class="ritual-heading mb-2 text-2xl font-bold text-theme-text">📢 Synod Forum</h2>
          <p class="text-sm text-theme-text-muted">
            Post messages to your Synod's private forum. Shouts are filtered through the Town Crier.
          </p>
          <p class="mt-1 text-xs text-theme-text-dim">
            <span v-if="canManage" class="text-theme-accent">50 Gold from Synod Vault</span>
            <span v-else class="text-theme-accent">100 Gold (personal)</span>
            per shout · 50 Gold per reply · Shouts are permanent
          </p>
        </div>

        <!-- Shout Submission Form -->
        <div class="glass-panel glass-panel-strong glass-gloss p-5 sm:p-6">
          <div v-if="forumShouts.submitError" class="mb-3 rounded-sm border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark">
            {{ forumShouts.submitError }}
          </div>

          <form @submit.prevent="handleForumShoutSubmit" class="flex flex-col gap-3">
            <textarea
              v-model="forumShoutContent"
              :disabled="forumShouts.submitting"
              rows="3"
              class="form-field resize-none px-4 py-3 text-sm"
              placeholder="Address your Synod..."
              maxlength="500"
            ></textarea>

            <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <div class="flex items-center gap-3">
                <span class="text-xs text-theme-text-muted">
                  {{ forumShoutContent.length }} / 500
                </span>
                <span v-if="canManage" class="text-xs font-medium text-theme-accent">💰 50 Gold (Synod Vault: {{ synod.synodInfo?.vault_gold || 0 }})</span>
                <span v-else class="text-xs font-medium text-theme-accent">💰 100 Gold</span>
              </div>
              <button
                type="submit"
                :disabled="!forumShoutContent.trim() || forumShouts.submitting || (canManage ? (synod.synodInfo?.vault_gold || 0) < 50 : economy.gold < 100)"
                class="btn-primary px-6 py-2 text-sm"
              >
                {{ forumShouts.submitting ? 'Crier is announcing...' : '📢 Post to Forum' }}
              </button>
            </div>

            <p v-if="canManage && (synod.synodInfo?.vault_gold || 0) < 50" class="text-xs text-theme-purgatory-dark">Synod vault has insufficient gold (need 50).</p>
            <p v-else-if="!canManage && economy.gold < 100" class="text-xs text-theme-purgatory-dark">Insufficient gold (need 100).</p>
          </form>
        </div>

        <!-- Forum Shouts Feed -->
        <div v-if="forumShouts.loading && forumShouts.shouts.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">📢</div>
          <p>Loading forum...</p>
        </div>

        <div v-else-if="forumShouts.shouts.length === 0 && !forumShouts.loading" class="glass-panel glass-panel-strong glass-gloss border-2 border-dashed border-theme-border p-12 text-center">
          <div class="mb-4 text-6xl">📯</div>
          <h3 class="mb-2 text-lg font-medium text-theme-text">No Posts Yet</h3>
          <p class="text-theme-text-dim">Be the first to post in your Synod's forum!</p>
        </div>

        <div v-else class="grid gap-3 sm:grid-cols-2">
          <ShoutCard
            v-for="shout in forumShouts.shouts"
            :key="shout.id"
            :shout="shout"
            @select="openForumShoutDetail"
          />
        </div>

        <!-- Load More -->
        <div v-if="forumShouts.hasMore" class="pt-2 text-center">
          <button
            @click="forumShouts.loadMoreShouts()"
            :disabled="forumShouts.loading"
            class="btn-secondary px-6 py-3 text-sm disabled:opacity-50"
          >
            {{ forumShouts.loading ? 'Loading...' : 'Load More' }}
          </button>
        </div>

        <!-- Shout Detail Modal (reusing for forum) -->
        <ShoutDetailModal
          :visible="forumDetailVisible"
          :shout="forumShouts.currentShout"
          :replies="forumShouts.replies"
          :total-replies="forumShouts.totalReplies"
          :has-more-replies="forumShouts.repliesHasMore"
          :loading="forumDetailLoading"
          :replies-loading="forumShouts.repliesLoading"
          :submitting="forumShouts.submitting"
          :submit-error="forumShouts.submitError"
          :blessing-loading="forumShouts.blessingLoading"
          :blessing-error="forumShouts.blessingError"
          :blessing-types="blessings.blessingTypes"
          @close="forumDetailVisible = false"
          @submit-reply="handleForumReplySubmit"
          @grant-blessing="handleForumBlessing"
          @load-more-replies="forumShouts.loadMoreReplies()"
        />
      </div>

      <!-- Town Crier Aether Modal (mirrors AkashicRecordsView's crier modal) -->
      <Teleport to="body">
        <Transition name="fade">
          <div v-if="forumShouts.isCrierProcessing || forumShouts.crierResult" class="aether-modal-overlay">
            <div class="aether-modal-container glass-panel glass-panel-strong glass-gloss">
              <!-- Processing State -->
              <div v-if="forumShouts.isCrierProcessing" class="aether-processing-state">
                <div class="aether-icon animate-pulse">
                  <img
                    src="@/assets/icons/town_crier_icon.png"
                    alt="The Town Crier"
                    class="crier-icon-img"
                  />
                </div>
                <h3 class="aether-title text-theme-accent">Hear ye, hear ye!</h3>
                <p class="aether-description text-theme-text-dim">The Town Crier is proclaiming your message...</p>
                <div class="aether-loader">
                  <div class="aether-loader-bar"></div>
                </div>
              </div>

              <!-- Result State -->
              <div v-else-if="forumShouts.crierResult" class="aether-result-state">
                <div class="aether-judgment-icon" :class="forumShouts.crierResult.success ? (forumShouts.crierResult.judgment === 'approved' ? 'approved' : 'rejected') : 'error'">
                  <svg v-if="forumShouts.crierResult.success && forumShouts.crierResult.judgment === 'approved'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                  <svg v-else-if="forumShouts.crierResult.success && forumShouts.crierResult.judgment === 'rejected'" class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                  <svg v-else class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                  </svg>
                </div>

                <h3 class="aether-title font-bold" :class="forumCrierStatusTitle">
                  {{ forumCrierStatusTitleText }}
                </h3>

                <div v-if="forumShouts.crierResult.response" class="aether-response-content glass-panel glass-gloss p-4 my-4">
                  <p class="text-theme-text font-semibold leading-relaxed">
                    {{ displayedForumCrierResponse }}<span v-if="!forumCrierTypewriterFinished" class="typewriter-cursor">▊</span>
                  </p>
                </div>

                <div v-else class="aether-error-content glass-panel glass-gloss p-4 my-4 border-2 border-theme-purgatory">
                  <p class="text-theme-purgatory-dark font-bold mb-2">⚠️ Town Crier Unavailable</p>
                  <p class="text-theme-text text-sm leading-relaxed">
                    {{ forumShouts.crierResult.error || 'The Town Crier could not proclaim your message.' }}
                  </p>
                </div>

                <div v-if="forumShouts.crierResult.rejection_reason" class="aether-rejection-reason text-sm text-theme-purgatory mb-3">
                  <span class="font-semibold">Reason:</span> {{ forumShouts.crierResult.rejection_reason }}
                </div>

                <button
                  @click="handleForumCrierContinue"
                  :disabled="!forumCrierTypewriterFinished"
                  class="btn-primary w-full mt-2"
                >
                  <span class="relative z-10 font-medium">
                    {{ forumCrierTypewriterFinished ? 'Continue' : 'The Crier is speaking...' }}
                  </span>
                </button>
              </div>
            </div>
          </div>
        </Transition>
      </Teleport>

      <!-- ==================== RELIQUARY TAB ==================== -->
      <div v-if="activeTab === 'reliquary' && synod.inSynod">
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
                <div class="flex h-14 w-14 items-center justify-center rounded-sm border border-theme-border bg-theme-panel/60 text-3xl">
                  {{ relic.icon || '\uD83C\uDFFA' }}
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="ritual-heading text-lg font-bold text-theme-text truncate">{{ relic.name }}</h3>
                  <p class="text-xs text-theme-text-muted mt-0.5 line-clamp-2">{{ relic.description }}</p>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-3 mb-4">
                <div class="rounded-sm border border-theme-border/50 bg-theme-panel/30 p-2.5 text-center">
                  <div class="text-xs text-theme-text-muted">Power</div>
                  <div class="text-sm font-semibold text-theme-accent">{{ relic.power_level || 1 }}</div>
                </div>
                <div class="rounded-sm border border-theme-border/50 bg-theme-panel/30 p-2.5 text-center">
                  <div class="text-xs text-theme-text-muted">Steal Cost</div>
                  <div class="text-sm font-semibold text-yellow-500">{{ relic.steal_cost || 50 }} Gold</div>
                </div>
              </div>

              <div class="rounded-sm border border-theme-border/50 bg-theme-panel/30 p-3 mb-4">
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

              <div v-if="relic.holder_id && relic.holder_id !== currentUserId && isRelicFromSynodMember(relic)" class="rounded-sm border border-theme-accent/30 bg-theme-accent/5 p-2 mb-4 text-center">
                <span class="text-xs text-theme-accent font-medium">&#x2694;&#xFE0F; Synod Buff Active</span>
              </div>

              <button
                v-if="relic.holder_id !== currentUserId"
                @click="handleSteal(relic.id)"
                :disabled="relics.stealing || !economy.synodId"
                class="btn-secondary w-full py-2.5 text-sm"
              >
                <span class="relative z-10 font-medium">
                  {{ !economy.synodId ? 'Requires Synod' : (relics.stealing ? 'Stealing...' : '&#x2694;&#xFE0F; Attempt Steal') }}
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
              <div class="rounded-sm border border-theme-border bg-theme-panel/40 p-5">
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

              <div class="rounded-sm border border-theme-border bg-theme-panel/40 p-5">
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

              <div class="rounded-sm border border-theme-accent/20 bg-theme-accent/5 p-5 text-center">
                <div class="text-4xl mb-2">&#x2728;</div>
                <h4 class="font-semibold text-theme-text mb-1">Indulgence Balance</h4>
                <div class="text-3xl font-bold text-theme-accent">{{ economy.indulgences || 0 }}</div>
                <p class="text-xs text-theme-text-muted mt-2">Purchase indulgences via the Karma Shop</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ==================== WAR TAB ==================== -->
      <div v-if="activeTab === 'war' && synod.inSynod">
        <!-- Declare War (leader only) -->
        <div v-if="synod.isLeader" class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8 mb-8">
          <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Declare Crusade</h2>

          <div v-if="synod.hasActiveWar" class="text-center py-4 text-theme-text-muted text-sm">
            Your Synod is already waging a Holy War. Finish it before declaring another.
          </div>

          <div v-else-if="sr.underAttack" class="text-center py-4 text-theme-text-muted text-sm">
            &#x1F6E1;&#xFE0F; Your Synod is under attack by <strong>{{ sr.attackerName || 'another Synod' }}</strong>. Defend first.
          </div>

          <template v-else>
            <p class="text-sm text-theme-text-muted mb-4">
              Enter the exact name of the target Synod. Costs 200 Gold to initiate. 30-day siege.
            </p>

            <div class="flex flex-col sm:flex-row gap-3 mb-4">
              <input
                v-model="warTargetName"
                type="text"
                placeholder="Enter exact Synod name..."
                class="form-field px-4 py-3 flex-1"
                @keyup.enter="handleFindTarget"
              />
              <button
                @click="handleFindTarget"
                :disabled="!warTargetName.trim() || hw.finding"
                class="btn-secondary px-6 py-3"
              >
                <span class="relative z-10 font-medium">{{ hw.finding ? 'Searching...' : 'Find' }}</span>
              </button>
            </div>

            <div v-if="hw.warTarget?.found" class="rounded-sm border border-theme-accent/30 bg-theme-accent/5 p-5">
              <div class="flex items-center justify-between">
                <div>
                  <div class="font-semibold text-theme-text text-lg">{{ hw.warTarget.name }}</div>
                  <div class="text-sm text-theme-text-muted mt-1">
                    {{ hw.warTarget.member_count }} members
                  </div>
                </div>
                <button
                  @click="handleDeclareWar(hw.warTarget.id)"
                  :disabled="hw.initiating"
                  class="btn-danger px-6 py-3 text-sm"
                >
                  <span class="relative z-10 font-medium">
                    {{ hw.initiating ? 'Declaring...' : 'Declare War (200 Gold)' }}
                  </span>
                </button>
              </div>
            </div>
          </template>

          <div v-if="hw.lastResult?.success" class="mt-4 rounded-sm border border-theme-accent/30 bg-theme-accent/5 p-4 text-sm text-theme-text">
            Crusade declared! {{ hw.lastResult.siege_days }}-day siege. {{ hw.lastResult.attacker_mana }} Mana / {{ hw.lastResult.attacker_workers }} Workers committed.
          </div>
        </div>

        <div v-else class="glass-panel glass-panel-soft p-6 sm:p-8 mb-8 text-center">
          <p class="text-theme-text-muted text-sm">Only the Synod leader can declare Holy Wars.</p>
        </div>

        <!-- Active Wars / Defense Scanner -->
        <div v-if="hw.activeWars.length > 0" class="glass-panel glass-panel-soft p-6 sm:p-8">
          <div class="flex items-center justify-between mb-4">
            <h2 class="ritual-heading text-2xl font-bold text-theme-text">
              {{ hw.activeWars.length === 1 ? 'Active War' : 'Defenses (' + hw.activeWars.length + ')' }}
            </h2>
            <div v-if="hw.activeWars.length > 1" class="flex items-center gap-2">
              <button @click="hw.prevDefense()" class="btn-ghost px-3 py-1 text-sm">&larr;</button>
              <span class="text-xs text-theme-text-muted">{{ hw.defenseIndex + 1 }} / {{ hw.activeWars.length }}</span>
              <button @click="hw.nextDefense()" class="btn-ghost px-3 py-1 text-sm">&rarr;</button>
            </div>
          </div>

          <div v-for="(war, idx) in [hw.activeWars[hw.defenseIndex]]" :key="war?.session_id || idx">
            <div v-if="war" class="p-5 rounded-sm border"
              :class="war.is_attacker ? 'border-theme-accent/25 bg-theme-accent/5' : 'border-theme-purgatory/25 bg-theme-purgatory/5'">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h3 class="font-semibold text-theme-text">
                    {{ war.attacker_synod_name }} vs {{ war.defender_synod_name }}
                  </h3>
                  <p class="text-xs text-theme-text-muted mt-0.5">
                    You are the {{ war.is_attacker ? 'Attacker' : 'Defender' }}
                    <span v-if="war.ticks_total > 1000" class="ml-2 text-theme-text-dim">
                      ({{ Math.round((war.ticks_total - war.ticks_remaining) / 1440) }}d / {{ Math.round(war.ticks_total / 1440) }}d siege)
                    </span>
                  </p>
                </div>
                <span class="chip status-chip text-xs">Active</span>
              </div>

              <div class="space-y-2 mb-3">
                <div>
                  <div class="flex justify-between text-xs text-theme-text-muted mb-1">
                    <span>Attacker Mana</span><span class="font-semibold text-blue-400">{{ war.attacker_mana }}</span>
                  </div>
                  <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                    <div class="h-full bg-blue-500/60 transition-all duration-500"
                      :style="{ width: manaPercent(war.attacker_mana, war.attacker_mana + war.defender_mana) + '%' }"></div>
                  </div>
                </div>
                <div>
                  <div class="flex justify-between text-xs text-theme-text-muted mb-1">
                    <span>Defender Mana</span><span class="font-semibold text-red-400">{{ war.defender_mana }}</span>
                  </div>
                  <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                    <div class="h-full bg-red-500/60 transition-all duration-500"
                      :style="{ width: manaPercent(war.defender_mana, war.attacker_mana + war.defender_mana) + '%' }"></div>
                  </div>
                </div>
              </div>

              <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs text-theme-text-muted">
                <div class="rounded-sm border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-theme-text">{{ war.attacker_workers }}</div><div>Atk Workers</div>
                </div>
                <div class="rounded-sm border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-theme-text">{{ war.defender_workers }}</div><div>Def Workers</div>
                </div>
                <div class="rounded-sm border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-theme-text">{{ war.ticks_remaining }}/{{ war.ticks_total }}</div><div>Ticks</div>
                </div>
                <div class="rounded-sm border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                  <div class="font-semibold text-yellow-500">{{ war.gold_stolen || 0 }}</div><div>Gold Stolen</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div v-else class="glass-panel glass-panel-soft p-8 text-center text-theme-text-muted text-sm">
          No active Holy Wars.
        </div>
      </div>

      <!-- ==================== RANKINGS TAB ==================== -->
      <div v-if="activeTab === 'rankings'">
        <div v-if="sr.loading" class="glass-panel glass-panel-soft p-12 text-center">
          <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">&#x1F3C6;</div>
          <p class="text-theme-text-dim">Consulting the divine ledger...</p>
        </div>

        <div v-else-if="sr.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
          <div class="text-4xl mb-4">&#x26A0;&#xFE0F;</div>
          <p class="text-theme-purgatory-dark">{{ sr.error }}</p>
          <button @click="sr.fetchRankings()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
        </div>

        <div v-else class="space-y-6">
          <!-- Global Synod Rankings Summary -->
          <div class="glass-panel glass-panel-soft glass-gloss p-5 sm:p-6">
            <h2 class="ritual-heading text-xl font-bold text-theme-accent mb-4 text-center">&#x1F3C6; Synod Rankings by Sect</h2>

            <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-5">
              <div
                v-for="sectKey in sr.SECT_KEYS"
                :key="sectKey"
                class="glass-panel glass-panel-soft p-4 sm:p-5 flex flex-col"
                style="min-height: 320px;"
              >
                <!-- Column Header -->
                <h3 class="ritual-heading text-base font-bold text-theme-accent mb-3 text-center flex items-center justify-center gap-2 flex-shrink-0">
                  <span class="text-lg">{{ sr.SECT_ICONS[sectKey] }}</span>
                  <span class="truncate">{{ sr.SECT_NAMES[sectKey] }}</span>
                </h3>

                <!-- Synod List -->
                <div class="space-y-2 flex-1 min-h-0 max-h-[340px] overflow-y-auto pr-1 synod-rankings-scroll">
                  <div
                    v-for="synodEntry in sr.sectColumns[sectKey]"
                    :key="synodEntry.synod_id"
                    class="flex items-center gap-2.5 py-2.5 px-3 rounded-sm transition-colors duration-200 hover:bg-theme-accent/5"
                    :class="{ 'bg-theme-accent/10 ring-1 ring-theme-accent/20': economy.synodId === synodEntry.synod_id }"
                  >
                    <span class="inline-flex items-center justify-center w-8 h-8 flex-shrink-0 rounded-sm text-xs font-bold"
                      :class="rankBadgeClass(synodEntry.rank)"
                    >
                      {{ synodEntry.rank }}
                    </span>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-semibold text-theme-text truncate">
                        {{ synodEntry.name }}
                        <span v-if="synodEntry.has_active_war" class="text-red-400 text-xs ml-1" title="At War">&#x2694;</span>
                      </div>
                      <div class="text-xs text-theme-text-muted truncate">
                        {{ synodEntry.leader_name || 'Unknown' }} &#xB7; {{ synodEntry.member_count }} members
                      </div>
                    </div>
                    <div class="text-xs text-yellow-500 font-semibold flex-shrink-0" :title="'Vault Gold'">
                      &#x1F4B0;{{ synodEntry.vault_gold || 0 }}
                    </div>
                  </div>

                  <div
                    v-if="(!sr.sectColumns[sectKey] || sr.sectColumns[sectKey].length === 0) && !sr.loading"
                    class="text-center py-6 text-sm text-theme-text-muted"
                  >
                    No Synods yet
                  </div>
                </div>
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
import { ref, onMounted, onUnmounted, computed, watch, inject } from 'vue'
import { useSynod } from '@/composables/useSynod'
import { useEconomy } from '@/composables/useEconomy'
import { useRelics } from '@/composables/useRelics'
import { useIndulgences } from '@/composables/useIndulgences'
import { useHolyWar } from '@/composables/useHolyWar'
import { useSynodRankings } from '@/composables/useSynodRankings'
import { useAuth } from '@/composables/useAuth'
import { useShouts } from '@/composables/useShouts'
import { useBlessings } from '@/composables/useBlessings'
import { useBanTimer } from '@/composables/useBanTimer'
import ShoutCard from '@/components/molecules/ShoutCard.vue'
import ShoutDetailModal from '@/components/organisms/ShoutDetailModal.vue'

const synod = useSynod()
const economy = useEconomy()
const relics = useRelics()
const indulgences = useIndulgences()
const hw = useHolyWar()
const sr = useSynodRankings()
const auth = useAuth()
const forumShouts = useShouts()
const blessings = useBlessings()
const banTimer = useBanTimer()

const forceEvilTheme = inject('forceEvilTheme', ref(false))
const forceWarTheme = inject('forceWarTheme', ref(false))
const activeTab = ref('synod')

const newSynodName = ref('')
const newSynodPrivacy = ref('public')
const forumShoutContent = ref('')
const forumDetailVisible = ref(false)
const forumDetailLoading = ref(false)
const newSynodMessage = ref('')
const editMessage = ref('')
const confirmAction = ref(null)
const warTargetName = ref('')

// Town Crier typewriter state
const displayedForumCrierResponse = ref('')
const forumCrierTypewriterFinished = ref(false)
let forumCrierTypewriterInterval = null

const forumCrierStatusTitle = computed(() => {
  if (!forumShouts.crierResult?.success) return 'text-theme-accent-dark'
  if (forumShouts.crierResult.judgment === 'approved') return 'text-theme-accent'
  return 'text-theme-purgatory'
})

const forumCrierStatusTitleText = computed(() => {
  if (!forumShouts.crierResult?.success) return 'Town Crier Unavailable'
  if (forumShouts.crierResult.judgment === 'approved') return 'Proclamation Announced!'
  return 'Proclamation Rejected'
})

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

// Header computed props
const headerTitle = computed(() => {
  switch (activeTab.value) {
    case 'forum': return 'Synod Forum'
    case 'reliquary': return 'Reliquary'
    case 'war': return 'Holy Wars'
    case 'rankings': return 'Synod Rankings'
    case 'synod':
    default:
      return synod.inSynod ? 'Synod Hall' : 'Find a Synod'
  }
})

const headerSubtitle = computed(() => {
  switch (activeTab.value) {
    case 'forum': return 'Private Synod messaging. Shouts are permanent and blessed by the Town Crier.'
    case 'reliquary': return 'Ten Sacred Relics. Hold them or steal them.'
    case 'war': return '30-day sieges. One attack at a time. Vanquish to destroy enemy Synods.'
    case 'rankings': return 'Every Synod, ranked by power and devotion.'
    case 'synod':
    default:
      return synod.inSynod ? 'Unite in faith, wage holy war.' : 'Browse public Synods or found your own.'
  }
})

// Theme management  Eonly synod/war/rankings use war-shell; reliquary uses evil-shell
watch(activeTab, (tab) => {
  forceEvilTheme.value = (tab === 'reliquary')
  forceWarTheme.value = (tab === 'synod' || tab === 'war' || tab === 'rankings' || tab === 'forum')
}, { immediate: true })

// Poll holy wars when watching the war tab; fetch forum when switching to forum
watch(activeTab, (tab) => {
  if (tab === 'forum') {
    forumShouts.fetchShouts(false, 'synod')
    blessings.fetchBlessingTypes()
  }
  if (tab === 'war') {
    hw.startPolling()
    sr.fetchDefenseStatus()
  } else {
    hw.stopPolling()
  }
})

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

function manaPercent(value, total) {
  if (!total || total <= 0) return 0
  return Math.min(100, Math.max(0, (value / total) * 100))
}

function rankBadgeClass(rank) {
  if (rank === 1) return 'rank-gold rank-badge-sm'
  if (rank === 2) return 'rank-silver rank-badge-sm'
  if (rank === 3) return 'rank-bronze rank-badge-sm'
  return 'rank-default rank-badge-sm'
}

// -- Forum actions --
// Watch for crier result to trigger typewriter effect
watch(() => forumShouts.crierResult, (result) => {
  if (forumCrierTypewriterInterval) {
    clearInterval(forumCrierTypewriterInterval)
    forumCrierTypewriterInterval = null
  }
  displayedForumCrierResponse.value = ''
  forumCrierTypewriterFinished.value = false

  if (result?.response) {
    let i = 0
    const text = result.response
    forumCrierTypewriterInterval = setInterval(() => {
      if (i < text.length) {
        displayedForumCrierResponse.value += text[i]
        i++
      } else {
        clearInterval(forumCrierTypewriterInterval)
        forumCrierTypewriterInterval = null
        forumCrierTypewriterFinished.value = true
      }
    }, 25)
  } else {
    forumCrierTypewriterFinished.value = true
  }
})

async function handleForumCrierContinue() {
  if (forumCrierTypewriterInterval) {
    clearInterval(forumCrierTypewriterInterval)
    forumCrierTypewriterInterval = null
  }
  const wasRejected = forumShouts.crierResult?.judgment === 'rejected'
  forumShouts.clearCrierResult()

  await forumShouts.fetchShouts(false, 'synod')
  await economy.fetchEconomy()
  await synod.fetchSynodInfo()

  // If rejected, check ban status for Purgatory redirect
  if (wasRejected) {
    await banTimer.checkBanStatus()
  }
}

async function handleForumShoutSubmit() {
  if (!forumShoutContent.value.trim()) return
  const result = await forumShouts.submitShout(forumShoutContent.value.trim(), 'synod')
  if (result?.success) {
    forumShoutContent.value = ''
    // Feed/economy refresh happens in handleForumCrierContinue after modal dismiss
  }
}

async function openForumShoutDetail(shout) {
  forumDetailVisible.value = true
  forumDetailLoading.value = true
  await forumShouts.fetchShoutDetail(shout.id)
  forumDetailLoading.value = false
}

async function handleForumReplySubmit(content) {
  if (!forumShouts.currentShout) return
  const result = await forumShouts.submitReply(forumShouts.currentShout.id, content)
  if (result?.success) {
    await economy.fetchEconomy()
  }
}

async function handleForumBlessing({ blessingTypeId, replyId }) {
  if (!forumShouts.currentShout) return
  const result = await forumShouts.grantShoutBlessing(forumShouts.currentShout.id, blessingTypeId, replyId)
  if (result?.success) {
    // No karma toast needed in synod context, just refresh
  }
}

// -- Synod actions --
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
  try { await synod.petitionSynod(synodId) } catch { /* captured */ }
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
    message: 'Kick ' + (username || 'this member') + ' from the Synod?',
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

// -- War actions --
function handleFindTarget() {
  if (!warTargetName.value.trim()) return
  hw.findTarget(warTargetName.value.trim())
}

async function handleDeclareWar(synodId) {
  try {
    await synod.initiateHolyWar(synodId)
    warTargetName.value = ''
    hw.warTarget.value = null
  } catch { /* captured */ }
}

onMounted(() => {
  forceWarTheme.value = true
  synod.fetchSynodInfo()
  synod.fetchPublicSynods()
  relics.fetchRelics()
  indulgences.fetchActiveMiracles()
  sr.fetchRankings()
})

onUnmounted(() => {
  hw.stopPolling()
  if (forumCrierTypewriterInterval) {
    clearInterval(forumCrierTypewriterInterval)
    forumCrierTypewriterInterval = null
  }
})
</script>

<style scoped>
.nav-tab-active,
.nav-tab-inactive {
  min-width: 8rem;
}

.nav-tab-active {
  color: #d7e0e8;
  border: 1px solid rgba(182, 144, 91, 0.24);
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0.04)), linear-gradient(145deg, rgba(62, 72, 82, 0.92), rgba(35, 43, 51, 0.96));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.14), inset 0 -1px 0 rgba(255, 255, 255, 0.03), 0 14px 28px rgba(0, 0, 0, 0.32), 0 0 0 1px rgba(182, 144, 91, 0.06);
  border-radius: 999px;
  padding: 0.625rem 1.5rem;
  font-weight: 600;
  cursor: pointer;
}

.nav-tab-inactive {
  color: #8291a0;
  border: 1px solid rgba(164, 176, 189, 0.14);
  background: rgba(255, 255, 255, 0.03);
  backdrop-filter: blur(10px);
  border-radius: 999px;
  padding: 0.625rem 1.5rem;
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
  flex-wrap: wrap;
  justify-content: center;
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

/* Rank badges (for Rankings tab) */
.rank-badge-sm {
  width: 2rem;
  height: 2rem;
  font-size: 0.72rem;
  font-weight: 700;
}

.rank-gold {
  color: #5c3d0a;
  background: linear-gradient(145deg, rgba(255, 193, 59, 0.95), rgba(213, 154, 23, 0.88));
  border: 1px solid rgba(213, 154, 23, 0.42);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), 0 8px 16px rgba(213, 154, 23, 0.18);
}

.rank-silver {
  color: #3a3f48;
  background: linear-gradient(145deg, rgba(192, 200, 212, 0.92), rgba(156, 164, 176, 0.84));
  border: 1px solid rgba(156, 164, 176, 0.36);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.32), 0 8px 16px rgba(156, 164, 176, 0.14);
}

.rank-bronze {
  color: #4a2e1a;
  background: linear-gradient(145deg, rgba(196, 138, 88, 0.9), rgba(168, 108, 58, 0.82));
  border: 1px solid rgba(168, 108, 58, 0.34);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28), 0 8px 16px rgba(168, 108, 58, 0.12);
}

.rank-default {
  color: var(--theme-text-dim);
  background: rgba(139, 125, 91, 0.12);
  border: 1px solid rgba(139, 125, 91, 0.14);
}

/* Scrollbar for ranking columns */
.synod-rankings-scroll {
  scrollbar-width: thin;
  scrollbar-color: rgba(185, 197, 207, 0.32) rgba(139, 125, 91, 0.06);
}

.synod-rankings-scroll::-webkit-scrollbar {
  width: 7px;
}

.synod-rankings-scroll::-webkit-scrollbar-track {
  background: rgba(139, 125, 91, 0.06);
  border-radius: 999px;
  margin: 4px 0;
}

.synod-rankings-scroll::-webkit-scrollbar-thumb {
  background: linear-gradient(
    180deg,
    rgba(185, 197, 207, 0.42),
    rgba(161, 173, 183, 0.32) 35%,
    rgba(139, 125, 91, 0.28) 65%,
    rgba(185, 197, 207, 0.38)
  );
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.15);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.28),
    inset 0 -1px 0 rgba(0, 0, 0, 0.06),
    0 1px 3px rgba(0, 0, 0, 0.08);
  min-height: 28px;
}

.synod-rankings-scroll::-webkit-scrollbar-thumb:hover {
  background: linear-gradient(
    180deg,
    rgba(213, 154, 23, 0.30),
    rgba(185, 197, 207, 0.42) 35%,
    rgba(161, 173, 183, 0.36) 65%,
    rgba(213, 154, 23, 0.26)
  );
  border-color: rgba(255, 255, 255, 0.22);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.35),
    inset 0 -1px 0 rgba(0, 0, 0, 0.04),
    0 2px 6px rgba(0, 0, 0, 0.1);
}

.synod-rankings-scroll::-webkit-scrollbar-thumb:active {
  background: linear-gradient(
    180deg,
    rgba(213, 154, 23, 0.38),
    rgba(185, 197, 207, 0.5) 40%,
    rgba(213, 154, 23, 0.34)
  );
}

@media (max-width: 640px) {
  .nav-tab-active,
  .nav-tab-inactive {
    min-width: 0;
    flex: 1 1 auto;
    padding: 0.5rem 1rem;
    font-size: 0.78rem;
  }

  .segmented-shell {
    gap: 0.35rem;
  }

  .rank-badge-sm {
    width: 1.75rem;
    height: 1.75rem;
    font-size: 0.68rem;
  }
}

@media (max-width: 420px) {
  .nav-tab-active,
  .nav-tab-inactive {
    flex-basis: calc(50% - 0.35rem);
    justify-content: center;
    text-align: center;
  }
}
.crier-icon-img {
  width: 5rem;
  height: 5rem;
  object-fit: contain;
  border-radius: 999px;
}

/* Town Crier Aether Modal (mirrors AltarView) */
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

.aether-response-content {
  margin: 1.25rem 0;
  text-align: left;
  border-radius: 12px;
  border: 1px solid rgba(213, 154, 23, 0.26);
  background: linear-gradient(180deg, rgba(255, 252, 244, 0.84), rgba(255, 247, 228, 0.78));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.76), inset 0 -1px 0 rgba(213, 154, 23, 0.08);
}

.aether-error-content {
  margin: 1.25rem 0;
  text-align: left;
  border-radius: 12px;
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

@keyframes overlay-fade {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes modal-rise {
  from {
    opacity: 0;
    transform: translateY(1.5rem) scale(0.96);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}
</style>