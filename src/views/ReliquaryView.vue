<template>
  <div>
    <!-- Header -->
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div>
            <h1 class="ritual-heading text-4xl font-bold text-theme-accent sm:text-5xl">Reliquary</h1>
            <p class="mt-1 text-sm text-theme-text-muted">Ten Sacred Relics. Hold them or steal them.</p>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">🏆</span>
              <span>Held: <span class="font-semibold text-theme-accent">{{ myRelicCount }}</span>/10</span>
            </div>
            <div v-if="economy.synodId" class="chip status-chip gap-2 px-4 py-2 text-sm">
              <span>⚔️ Synod Steal Available</span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Loading -->
      <div v-if="relics.loading" class="glass-panel glass-panel-soft p-12 text-center">
        <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">✨</div>
        <p class="text-theme-text-dim">Summoning the sacred artifacts...</p>
      </div>

      <!-- Error -->
      <div v-else-if="relics.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
        <div class="text-4xl mb-4">⚠️</div>
        <p class="text-theme-purgatory-dark">{{ relics.error }}</p>
        <button @click="relics.fetchRelics()" class="btn-secondary mt-4 px-6 py-2">Try Again</button>
      </div>

      <!-- Relic Grid -->
      <div v-else class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <div
          v-for="relic in relics.relics"
          :key="relic.id"
          class="glass-panel glass-panel-soft p-5 sm:p-6 transition-all duration-[var(--dur-standard)] hover:shadow-glow-gold"
          :class="{ 'ring-1 ring-theme-accent/30': relic.holder_id === currentUserId }"
        >
          <!-- Relic Icon & Name -->
          <div class="flex items-start gap-4 mb-4">
            <div class="flex h-14 w-14 items-center justify-center rounded-[20px] border border-theme-border bg-theme-panel/60 text-3xl shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              {{ relic.icon || '🏺' }}
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="ritual-heading text-lg font-bold text-theme-text truncate">{{ relic.name }}</h3>
              <p class="text-xs text-theme-text-muted mt-0.5 line-clamp-2">{{ relic.description }}</p>
            </div>
          </div>

          <!-- Relic Stats -->
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

          <!-- Holder Info -->
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

          <!-- Steal Button -->
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

      <!-- Empty State -->
      <div v-if="!relics.loading && !relics.error && relics.relics.length === 0" class="glass-panel glass-panel-soft p-12 text-center">
        <div class="text-5xl mb-4">🏺</div>
        <h3 class="mb-2 text-2xl font-medium text-theme-text">The Reliquary is Empty</h3>
        <p class="text-theme-text-dim">The relics have not yet materialized. Check back soon.</p>
      </div>

      <!-- Indulgences Section -->
      <div class="mt-10 glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
        <h2 class="ritual-heading text-2xl font-bold text-theme-text mb-2">Indulgences</h2>
        <p class="text-sm text-theme-text-muted mb-6">Premium blessings purchased with devotion.</p>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <!-- Papal Bull -->
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

          <!-- Divine Architect -->
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

          <!-- Indulgence Balance -->
          <div class="rounded-[20px] border border-theme-accent/20 bg-theme-accent/5 p-5 text-center">
            <div class="text-4xl mb-2">✨</div>
            <h4 class="font-semibold text-theme-text mb-1">Indulgence Balance</h4>
            <div class="text-3xl font-bold text-theme-accent">{{ economy.indulgences || 0 }}</div>
            <p class="text-xs text-theme-text-muted mt-2">Purchase indulgences via the Karma Shop</p>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { computed, onMounted } from 'vue'
import { useRelics } from '@/composables/useRelics'
import { useEconomy } from '@/composables/useEconomy'
import { useIndulgences } from '@/composables/useIndulgences'
import { useAuth } from '@/composables/useAuth'

const relics = useRelics()
const economy = useEconomy()
const indulgences = useIndulgences()
const auth = useAuth()

const currentUserId = computed(() => auth.user?.id)
const myRelicCount = computed(() => relics.heldRelics(currentUserId.value)?.length || 0)

async function handleSteal(relicId) {
  try {
    await relics.attemptSteal(relicId)
  } catch (err) {
    // Error captured in composable
  }
}

async function handleActivatePapalBull() {
  try {
    await indulgences.activatePapalBull()
  } catch (err) {
    // Error captured in composable
  }
}

async function handleActivateDivineArchitect() {
  try {
    await indulgences.activateDivineArchitect()
  } catch (err) {
    // Error captured in composable
  }
}

function formatDate(dateString) {
  if (!dateString) return 'N/A'
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

onMounted(() => {
  relics.fetchRelics()
  indulgences.fetchActiveMiracles()
})
</script>