<template>
  <div class="war-shell min-h-screen">
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="relative min-w-0">
            <div class="merged-header-glow" aria-hidden="true"></div>
            <h1 class="ritual-heading relative text-4xl font-bold text-theme-accent sm:text-5xl">
              Holy Wars
            </h1>
            <p class="relative mt-1 text-sm text-theme-text-muted">
              Synod vs Synod crusades. Leader declares, all members fight.
            </p>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Error -->
      <div v-if="hw.error" class="glass-panel p-8 text-center border border-theme-purgatory/25 mb-8">
        <div class="text-4xl mb-4">&#x26A0;&#xFE0F;</div>
        <p class="text-theme-purgatory-dark">{{ hw.error }}</p>
      </div>

      <!-- Declare War (leader only, if in synod) -->
      <div v-if="synod.inSynod && synod.isLeader" class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8 mb-8">
        <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Declare Crusade</h2>
        <p class="text-sm text-theme-text-muted mb-4">
          Enter the exact name of the target Synod. Costs 200 Gold to initiate + 100 Gold per minute.
        </p>

        <div class="flex flex-col sm:flex-row gap-3 mb-4">
          <input
            v-model="targetName"
            type="text"
            placeholder="Enter exact Synod name..."
            class="form-field px-4 py-3 flex-1"
            @keyup.enter="handleFindTarget"
          />
          <button
            @click="handleFindTarget"
            :disabled="!targetName.trim() || hw.finding"
            class="btn-secondary px-6 py-3"
          >
            <span class="relative z-10 font-medium">{{ hw.finding ? 'Searching...' : 'Find' }}</span>
          </button>
        </div>

        <!-- Target Found -->
        <div v-if="hw.warTarget?.found" class="rounded-[20px] border border-theme-accent/30 bg-theme-accent/5 p-5">
          <div class="flex items-center justify-between">
            <div>
              <div class="font-semibold text-theme-text text-lg">{{ hw.warTarget.name }}</div>
              <div class="text-sm text-theme-text-muted mt-1">
                {{ hw.warTarget.member_count }} members
                <span class="ml-2 text-xs">{{ hw.warTarget.sect_key || 'Unknown faction' }}</span>
              </div>
              <div class="text-xs text-theme-text-dim mt-1">Led by {{ hw.warTarget.leader_name || 'Unknown' }}</div>
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

        <!-- Target Not Found -->
        <div v-else-if="hw.warTarget && !hw.warTarget.found" class="text-center py-4 text-theme-text-muted text-sm">
          No Synod found with that exact name.
        </div>

        <!-- Initiation Result -->
        <div v-if="hw.lastResult?.success" class="mt-4 rounded-[16px] border border-theme-accent/30 bg-theme-accent/5 p-4 text-sm text-theme-text">
          Crusade declared! Your Synod commits {{ hw.lastResult.attacker_mana }} Mana and {{ hw.lastResult.attacker_workers }} Workers.
          Enemy has {{ hw.lastResult.defender_mana }} Mana.
        </div>
      </div>

      <!-- Not a Leader -->
      <div v-else-if="synod.inSynod && !synod.isLeader" class="glass-panel glass-panel-soft p-6 sm:p-8 mb-8 text-center">
        <p class="text-theme-text-muted text-sm">Only the Synod leader can declare Holy Wars.</p>
      </div>

      <!-- Not in a Synod -->
      <div v-else-if="!synod.inSynod" class="glass-panel glass-panel-soft p-6 sm:p-8 mb-8 text-center">
        <p class="text-theme-text-muted text-sm">Join a Synod to participate in Holy Wars.</p>
      </div>

      <!-- Active Wars -->
      <div class="glass-panel glass-panel-soft p-6 sm:p-8">
        <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Active Crusades</h2>

        <div v-if="hw.loading && hw.activeWars.length === 0" class="text-center py-8 text-theme-text-muted text-sm">
          Loading wars...
        </div>

        <div v-else-if="hw.activeWars.length === 0" class="text-center py-8 text-theme-text-muted text-sm">
          No active Holy Wars.
        </div>

        <div v-else class="space-y-4">
          <div
            v-for="war in hw.activeWars"
            :key="war.session_id"
            class="p-5 rounded-[20px] border"
            :class="war.is_attacker ? 'border-theme-accent/25 bg-theme-accent/5' : 'border-theme-purgatory/25 bg-theme-purgatory/5'"
          >
            <!-- Header -->
            <div class="flex items-center justify-between mb-3">
              <div>
                <h3 class="font-semibold text-theme-text">
                  {{ war.attacker_synod_name }} vs {{ war.defender_synod_name }}
                </h3>
                <p class="text-xs text-theme-text-muted mt-0.5">
                  You are the {{ war.is_attacker ? 'Attacker' : 'Defender' }}
                </p>
              </div>
              <span class="chip status-chip text-xs">Active</span>
            </div>

            <!-- Mana Bars -->
            <div class="space-y-2 mb-3">
              <div>
                <div class="flex justify-between text-xs text-theme-text-muted mb-1">
                  <span>Attacker Mana</span>
                  <span class="font-semibold text-blue-400">{{ war.attacker_mana }}</span>
                </div>
                <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                  <div
                    class="h-full bg-blue-500/60 transition-all duration-500"
                    :style="{ width: manaPercent(war.attacker_mana, war.attacker_mana + war.defender_mana) + '%' }"
                  ></div>
                </div>
              </div>
              <div>
                <div class="flex justify-between text-xs text-theme-text-muted mb-1">
                  <span>Defender Mana</span>
                  <span class="font-semibold text-red-400">{{ war.defender_mana }}</span>
                </div>
                <div class="h-3 rounded-full border border-theme-border/30 bg-theme-panel/50 overflow-hidden">
                  <div
                    class="h-full bg-red-500/60 transition-all duration-500"
                    :style="{ width: manaPercent(war.defender_mana, war.attacker_mana + war.defender_mana) + '%' }"
                  ></div>
                </div>
              </div>
            </div>

            <!-- Stats Grid -->
            <div class="grid grid-cols-4 gap-2 text-xs text-theme-text-muted">
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ war.attacker_workers }}</div>
                <div>Atk Workers</div>
              </div>
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ war.defender_workers }}</div>
                <div>Def Workers</div>
              </div>
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ war.ticks_remaining }}/{{ war.ticks_total }}</div>
                <div>Ticks</div>
              </div>
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-yellow-500">{{ war.gold_stolen || 0 }}</div>
                <div>Gold Stolen</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, inject } from 'vue'
import { useSynod } from '@/composables/useSynod'
import { useHolyWar } from '@/composables/useHolyWar'

const synod = useSynod()
const hw = useHolyWar()
const targetName = ref('')

const forceWarTheme = inject('forceWarTheme', ref(false))

onMounted(() => {
  forceWarTheme.value = true
  synod.fetchSynodInfo()
  hw.startPolling()
})

onUnmounted(() => {
  forceWarTheme.value = false
  hw.stopPolling()
})

function handleFindTarget() {
  if (!targetName.value.trim()) return
  hw.findTarget(targetName.value.trim())
}

async function handleDeclareWar(synodId) {
  try {
    await synod.initiateHolyWar(synodId)
    targetName.value = ''
    hw.warTarget.value = null
  } catch {
    // Error captured in hw.error
  }
}

function manaPercent(value, total) {
  if (!total || total <= 0) return 0
  return Math.min(100, Math.max(0, (value / total) * 100))
}
</script>

<style scoped>
.merged-header-glow {
  position: absolute;
  inset: -1rem auto auto -1rem;
  width: 13rem;
  height: 6rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(187, 198, 209, 0.16) 0%, rgba(135, 147, 159, 0.08) 42%, transparent 74%);
  filter: blur(12px);
  pointer-events: none;
}
</style>