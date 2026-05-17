<template>
  <div>
    <!-- Header -->
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div>
            <h1 class="ritual-heading text-4xl font-bold text-theme-accent sm:text-5xl">Synod Hall</h1>
            <p class="mt-1 text-sm text-theme-text-muted">Unite in faith, wage holy war.</p>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <div v-if="synod.inSynod" class="chip status-chip gap-2 px-4 py-2 text-sm">
              <span class="text-lg">⚔️</span>
              <span>{{ synod.synodInfo?.name || 'Synod' }}</span>
              <span class="text-theme-text-muted">· {{ synod.memberCount }} members</span>
            </div>
            <div v-else class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-theme-text-muted">No Synod</span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
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
        <!-- Create Synod -->
        <div class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
          <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Found a Synod</h2>
          <p class="text-sm text-theme-text-muted mb-6">Create a new Synod for 100 Gold. You will become its leader.</p>
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

        <!-- Search & Join Synod -->
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

          <!-- Search Results -->
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
        <!-- Synod Info Card -->
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

          <!-- Synod Stats -->
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

        <!-- Members List -->
        <div class="glass-panel glass-panel-soft p-6 sm:p-8">
          <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">Members</h3>
          <div v-if="synod.members.length === 0" class="text-center py-6 text-theme-text-muted text-sm">
            No members found.
          </div>
          <div v-else class="space-y-2">
            <div
              v-for="member in synod.members"
              :key="member.user_id"
              class="flex items-center justify-between p-3 rounded-[16px] border border-theme-border/50 bg-theme-panel/30"
            >
              <div class="flex items-center gap-3">
                <span class="text-lg">{{ member.role === 'leader' ? '👑' : '🕊️' }}</span>
                <div>
                  <div class="font-medium text-theme-text text-sm">{{ member.username || 'Unknown' }}</div>
                  <div class="text-xs text-theme-text-muted">{{ member.role }}</div>
                </div>
              </div>
              <div class="text-xs text-theme-text-muted">
                Joined {{ formatDate(member.joined_at) }}
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

        <!-- War Declaration Modal -->
        <Teleport to="body">
          <div v-if="showWarDeclaration" class="fixed inset-0 z-50 flex items-center justify-center p-4" style="animation: overlay-fade var(--dur-standard) var(--ease-ritual-lift)">
            <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="showWarDeclaration = false"></div>
            <div class="relative z-10 w-full max-w-md glass-panel glass-panel-strong glass-gloss p-6" style="animation: modal-rise var(--dur-enter) var(--ease-ritual-lift)">
              <h3 class="ritual-heading text-xl font-bold text-theme-text mb-4">⚔️ Declare Holy War</h3>
              <p class="text-sm text-theme-text-muted mb-4">Enter the Synod name you wish to declare war on. This costs 200 Gold from your Synod vault.</p>
              <input
                v-model="warTargetName"
                type="text"
                placeholder="Enemy Synod name..."
                class="form-field px-4 py-3 w-full mb-4"
              />
              <div class="flex gap-3 justify-end">
                <button @click="showWarDeclaration = false" class="btn-ghost px-4 py-2 text-sm">Cancel</button>
                <button
                  @click="handleDeclareWar"
                  :disabled="!warTargetName.trim() || synod.declaring"
                  class="btn-danger px-5 py-2 text-sm"
                >
                  <span class="relative z-10 font-medium">{{ synod.declaring ? 'Declaring...' : 'Declare War' }}</span>
                </button>
              </div>
            </div>
          </div>
        </Teleport>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useSynod } from '@/composables/useSynod'
import { useEconomy } from '@/composables/useEconomy'

const synod = useSynod()
const economy = useEconomy()

const newSynodName = ref('')
const searchQuery = ref('')
const searchResults = ref([])
const hasSearched = ref(false)
const showWarDeclaration = ref(false)
const warTargetName = ref('')

async function handleCreateSynod() {
  if (!newSynodName.value.trim()) return
  try {
    await synod.createSynod(newSynodName.value.trim())
    newSynodName.value = ''
  } catch (err) {
    // Error captured in composable
  }
}

async function handleSearchSynods() {
  if (!searchQuery.value.trim()) return
  try {
    const results = await synod.searchSynods(searchQuery.value.trim())
    searchResults.value = results || []
    hasSearched.value = true
  } catch (err) {
    searchResults.value = []
    hasSearched.value = true
  }
}

async function handleJoinSynod(synodId) {
  try {
    await synod.joinSynod(synodId)
  } catch (err) {
    // Error captured in composable
  }
}

async function handleLeaveSynod() {
  if (!confirm('Are you sure you want to leave your Synod? If you are the leader, leadership will transfer.')) return
  try {
    await synod.leaveSynod()
  } catch (err) {
    // Error captured in composable
  }
}

async function handleDeclareWar() {
  if (!warTargetName.value.trim()) return
  try {
    await synod.declareHolyWar(warTargetName.value.trim())
    showWarDeclaration.value = false
    warTargetName.value = ''
  } catch (err) {
    // Error captured in composable
  }
}

function formatDate(dateString) {
  if (!dateString) return ''
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

onMounted(() => {
  synod.fetchSynodInfo()
})
</script>