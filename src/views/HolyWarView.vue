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
              30-day sieges. One attack at a time. Vanquish to destroy enemy Synods.
            </p>
          </div>
          <div v-if="synod.inSynod" class="flex flex-wrap items-center gap-3">
            <div v-if="synod.hasActiveWar" class="chip status-chip gap-2 px-4 py-2 text-sm">
              At War
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <div v-if="hw.error" class="glass-panel p-8 text-center border border-theme-purgatory/25 mb-8">
        <p class="text-theme-purgatory-dark">{{ hw.error }}</p>
      </div>

      <!-- Declare War (leader only) -->
      <div v-if="synod.inSynod && synod.isLeader" class="glass-panel glass-panel-strong glass-gloss p-6 sm:p-8 mb-8">
        <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-4">Declare Crusade</h2>

        <div v-if="synod.hasActiveWar" class="text-center py-4 text-theme-text-muted text-sm">
          You are already waging a Holy War. Finish it before declaring another.
        </div>

        <template v-else>
          <p class="text-sm text-theme-text-muted mb-4">
            Enter the exact name of the target Synod. Costs 200 Gold to initiate. 30-day siege.
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

          <div v-if="hw.warTarget?.found" class="rounded-[20px] border border-theme-accent/30 bg-theme-accent/5 p-5">
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

        <div v-if="hw.lastResult?.success" class="mt-4 rounded-[16px] border border-theme-accent/30 bg-theme-accent/5 p-4 text-sm text-theme-text">
          Crusade declared! {{ hw.lastResult.siege_days }}-day siege. {{ hw.lastResult.attacker_mana }} Mana / {{ hw.lastResult.attacker_workers }} Workers committed.
        </div>
      </div>

      <div v-else-if="synod.inSynod && !synod.isLeader" class="glass-panel glass-panel-soft p-6 sm:p-8 mb-8 text-center">
        <p class="text-theme-text-muted text-sm">Only the Synod leader can declare Holy Wars.</p>
      </div>

      <div v-else-if="!synod.inSynod" class="glass-panel glass-panel-soft p-6 sm:p-8 mb-8 text-center">
        <p class="text-theme-text-muted text-sm">Join a Synod to participate in Holy Wars.</p>
      </div>

      <!-- Defense Scanner (Exodus 2) -->
      <div v-if="hw.activeWars.length > 0" class="glass-panel glass-panel-soft p-6 sm:p-8">
        <div class="flex items-center justify-between mb-4">
          <h2 class="ritual-heading text-2xl font-bold text-theme-text">
            {{ hw.activeWars.length === 1 ? 'Active War' : `Defenses (${hw.activeWars.length})` }}
          </h2>
          <div v-if="hw.activeWars.length > 1" class="flex items-center gap-2">
            <button @click="hw.prevDefense()" class="btn-ghost px-3 py-1 text-sm">&larr;</button>
            <span class="text-xs text-theme-text-muted">{{ hw.defenseIndex + 1 }} / {{ hw.activeWars.length }}</span>
            <button @click="hw.nextDefense()" class="btn-ghost px-3 py-1 text-sm">&rarr;</button>
          </div>
        </div>

        <div v-for="(war, idx) in [hw.activeWars[hw.defenseIndex]]" :key="war?.session_id || idx">
          <div v-if="war" class="p-5 rounded-[20px] border"
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

            <div class="grid grid-cols-4 gap-2 text-xs text-theme-text-muted">
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ war.attacker_workers }}</div><div>Atk Workers</div>
              </div>
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ war.defender_workers }}</div><div>Def Workers</div>
              </div>
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-theme-text">{{ war.ticks_remaining }}/{{ war.ticks_total }}</div><div>Ticks</div>
              </div>
              <div class="rounded-[12px] border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
                <div class="font-semibold text-yellow-500">{{ war.gold_stolen || 0 }}</div><div>Gold Stolen</div>
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
  } catch { /* captured */ }
}

function manaPercent(value, total) {
  if (!total || total <= 0) return 0
  return Math.min(100, Math.max(0, (value / total) * 100))
}
</script>

<style scoped>
.merged-header-glow {
  position: absolute; inset: -1rem auto auto -1rem;
  width: 13rem; height: 6rem; border-radius: 999px;
  background: radial-gradient(circle, rgba(187, 198, 209, 0.16) 0%, rgba(135, 147, 159, 0.08) 42%, transparent 74%);
  filter: blur(12px); pointer-events: none;
}
</style>