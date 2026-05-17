<template>
  <div :class="activeTab === 'dark' ? 'evil-shell' : ''">
    <!-- Header -->
    <header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
      <div class="app-frame py-5">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div>
            <h1 class="ritual-heading text-4xl font-bold text-theme-accent sm:text-5xl">Scriptorium</h1>
            <p class="mt-1 text-sm text-theme-text-muted">Illuminate the darkness, or embrace it.</p>
          </div>
          <div class="flex flex-wrap items-center justify-start gap-3 xl:justify-end">
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">📑</span>
              <span>Dogma: <span class="font-semibold text-amber-600">{{ economy.dogma }}</span></span>
            </div>
            <div class="chip gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
              <span class="text-lg">✝</span>
              <span>Heresy: <span class="font-semibold text-red-500">{{ economy.heresy }}</span></span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Alignment Toggle -->
      <div class="mb-8 flex justify-center">
        <div class="segmented-shell">
          <button
            @click="activeTab = 'light'"
            class="pill-tab"
            :class="activeTab === 'light' ? 'pill-tab-active' : 'pill-tab-inactive'"
          >
            ☀️ Scriptorium
          </button>
          <button
            @click="activeTab = 'dark'"
            class="pill-tab"
            :class="activeTab === 'dark' ? 'pill-tab-active' : 'pill-tab-inactive'"
          >
            🌑 Occult Library
          </button>
        </div>
      </div>

      <!-- Loading State -->
      <div v-if="research.loading" class="glass-panel glass-panel-soft p-12 text-center">
        <div class="text-4xl mb-4" style="animation: ritual-breathe 3s ease-in-out infinite">📖</div>
        <p class="text-theme-text-dim">Unrolling the ancient scrolls...</p>
      </div>

      <!-- Error State -->
      <div v-else-if="research.error" class="glass-panel p-8 text-center border border-theme-purgatory/25">
        <div class="text-4xl mb-4">⚠️</div>
        <p class="text-theme-purgatory-dark">{{ research.error }}</p>
        <button @click="research.fetchResearchTree()" class="btn-secondary mt-4 px-6 py-2">
          Try Again
        </button>
      </div>

      <!-- Tech Tree -->
      <div v-else>
        <!-- Light Tech Tree -->
        <div v-if="activeTab === 'light'" class="space-y-6">
          <div v-if="research.lightNodes.length === 0" class="glass-panel glass-panel-soft p-8 text-center">
            <p class="text-theme-text-muted">No scriptorium research available yet.</p>
          </div>
          <div
            v-for="node in research.lightNodes"
            :key="node.id"
            class="glass-panel glass-panel-soft p-5 sm:p-6 transition-all duration-[var(--dur-standard)]"
            :class="{ 'opacity-50': !canResearchLight(node), 'ring-1 ring-theme-accent/30': isUnlocked(node.id) }"
          >
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div class="flex-1">
                <div class="flex items-center gap-3 mb-1">
                  <span class="text-2xl">{{ node.icon || '📜' }}</span>
                  <h3 class="text-lg font-semibold text-theme-text">{{ node.name }}</h3>
                  <span v-if="isUnlocked(node.id)" class="chip status-chip text-xs">✓ Researched</span>
                </div>
                <p class="text-sm text-theme-text-muted leading-relaxed">{{ node.description }}</p>
                <div v-if="node.requires_node" class="mt-1 text-xs text-theme-text-muted">
                  Requires: {{ getNodeName(node.requires_node) }}
                </div>
              </div>
              <div class="flex items-center gap-3">
                <div class="text-right">
                  <div class="text-sm font-medium text-amber-600">Cost: {{ node.cost }} Dogma</div>
                </div>
                <button
                  v-if="!isUnlocked(node.id)"
                  @click="handleResearch(node.id)"
                  :disabled="!canResearchLight(node) || research.researching"
                  class="btn-primary px-5 py-2 text-sm"
                >
                  <span class="relative z-10 font-medium">
                    {{ research.researching ? 'Researching...' : 'Research' }}
                  </span>
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Dark Tech Tree -->
        <div v-if="activeTab === 'dark'" class="rounded-[var(--radius-panel)] p-6 sm:p-8 space-y-6">
          <div class="relative z-10">
            <div v-if="research.darkNodes.length === 0" class="text-center py-8">
              <p class="text-theme-text-muted">No occult research available yet.</p>
            </div>
            <div
              v-for="node in research.darkNodes"
              :key="node.id"
              class="glass-panel glass-panel-soft p-5 sm:p-6 transition-all duration-[var(--dur-standard)]"
              :class="{ 'opacity-50': !canResearchDark(node), 'ring-1 ring-[#b180ff]/40': isUnlocked(node.id) }"
            >
              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
                <div class="flex-1">
                  <div class="flex items-center gap-3 mb-1">
                    <span class="text-2xl">{{ node.icon || '🔮' }}</span>
                    <h3 class="text-lg font-semibold text-theme-text">{{ node.name }}</h3>
                    <span v-if="isUnlocked(node.id)" class="chip text-xs" style="border-color: rgba(206,170,255,0.3); background: linear-gradient(180deg, rgba(177,128,255,0.15), rgba(177,128,255,0.05)); color: #efd2ff;">✓ Unlocked</span>
                  </div>
                  <p class="text-sm text-theme-text-muted leading-relaxed">{{ node.description }}</p>
                  <div v-if="node.requires_node" class="mt-1 text-xs text-theme-text-muted">
                    Requires: {{ getNodeName(node.requires_node) }}
                  </div>
                </div>
                <div class="flex items-center gap-3">
                  <div class="text-right">
                    <div class="text-sm font-medium text-[#ff6bd6]">Cost: {{ node.cost }} Heresy</div>
                  </div>
                  <button
                    v-if="!isUnlocked(node.id)"
                    @click="handleResearch(node.id)"
                    :disabled="!canResearchDark(node) || research.researching"
                    class="btn-primary px-5 py-2 text-sm"
                  >
                    <span class="relative z-10 font-medium">
                      {{ research.researching ? 'Channeling...' : 'Channel' }}
                    </span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch, inject } from 'vue'
import { useResearch } from '@/composables/useResearch'
import { useEconomy } from '@/composables/useEconomy'

const research = useResearch()
const economy = useEconomy()
const activeTab = ref('light')

// Inject forceEvilTheme from App.vue for Occult Library tab
const forceEvilTheme = inject('forceEvilTheme', ref(false))

// Toggle evil theme when viewing Occult Library tab
watch(activeTab, (tab) => {
  forceEvilTheme.value = (tab === 'dark')
}, { immediate: true })

function isUnlocked(nodeId) {
  return research.unlockedIds.has(nodeId)
}

function canResearchLight(node) {
  if (isUnlocked(node.id)) return false
  if (node.requires_node && !isUnlocked(node.requires_node)) return false
  return (economy.dogma || 0) >= node.cost
}

function canResearchDark(node) {
  if (isUnlocked(node.id)) return false
  if (node.requires_node && !isUnlocked(node.requires_node)) return false
  return (economy.heresy || 0) >= node.cost
}

function getNodeName(nodeId) {
  const node = research.nodes.find(n => n.id === nodeId)
  return node ? node.name : nodeId
}

async function handleResearch(nodeId) {
  try {
    await research.researchTech(nodeId)
  } catch (err) {
    // Error captured in composable
  }
}

onMounted(() => {
  research.fetchResearchTree()
})
</script>