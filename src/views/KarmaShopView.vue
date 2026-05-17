<template>
  <div>
    <header class="shop-header border-b surface-divider bg-theme-panel/55 backdrop-blur-[16px]">
      <div class="app-frame py-6">
        <div class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="relative">
              <div class="shop-header-glow"></div>
              <h1 class="ritual-heading relative text-3xl font-bold text-theme-accent sm:text-4xl">🛒 Karma Shop</h1>
            </div>
            <div class="chip gap-2 self-start px-4 py-2 text-sm text-theme-text-dim shadow-[0_12px_24px_rgba(48,38,21,0.08)] lg:self-auto">
              <span class="text-lg">{{ prayers.karmaEmoji }}</span>
              <span>Karma: <span :class="karmaClass" class="font-semibold">{{ prayers.karma }}</span></span>
            </div>
          </div>

          <div class="segmented-shell self-start">
            <button
              @click="shop.activeTab = 'blessings'"
              class="pill-tab"
              :class="shop.activeTab === 'blessings' ? 'pill-tab-active' : 'pill-tab-inactive'"
            >
              ✨ Blessings
            </button>
            <button
              class="pill-tab pill-tab-inactive cursor-not-allowed opacity-50"
              disabled
              title="Coming soon"
            >
              🎨 Avatars
            </button>
            <button
              class="pill-tab pill-tab-inactive cursor-not-allowed opacity-50"
              disabled
              title="Coming soon"
            >
              🏷️ Titles
            </button>
          </div>
        </div>
      </div>
    </header>

    <main class="app-frame py-8 lg:py-10">
      <!-- Blessings Tab -->
      <div v-if="shop.activeTab === 'blessings'" class="space-y-6">
        <div class="glass-panel glass-panel-soft glass-gloss flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <p class="text-sm text-theme-text-muted">
            Bless prayers in the Akashic Records with divine emojis. Each blessing grants karma to the receiver.
          </p>
        </div>

        <div v-if="blessings.loading && blessings.blessingTypes.length === 0" class="glass-panel glass-panel-soft p-12 text-center text-theme-text-dim">
          <div class="mb-3 text-4xl animate-pulse">✨</div>
          <p>Loading blessings...</p>
        </div>

        <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          <div
            v-for="blessing in blessings.blessingTypes"
            :key="blessing.id"
            class="glass-panel glass-panel-soft glass-gloss group relative overflow-hidden border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]"
          >
            <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)] opacity-0 transition-opacity duration-300 group-hover:opacity-100"></div>

            <div class="relative">
              <div class="mb-3 flex items-center gap-3">
                <span class="flex h-12 w-12 items-center justify-center rounded-2xl border border-theme-accent/20 bg-white/55 text-2xl shadow-[0_10px_20px_rgba(213,154,23,0.12)] backdrop-blur-sm">{{ blessing.emoji }}</span>
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-theme-text">{{ blessing.name }}</h3>
                  <div class="chip mt-0.5 gap-1 px-2 py-0.5 text-[0.65rem] font-semibold text-theme-accent">
                    <span>{{ blessing.karma_cost }}</span>
                    <span class="text-theme-text-muted">karma</span>
                  </div>
                </div>
              </div>

              <p class="mb-4 text-xs leading-relaxed text-theme-text-dim">{{ blessing.description }}</p>

              <div class="flex items-center gap-3 border-t border-theme-border/50 pt-3 text-[0.7rem] text-theme-text-muted">
                <div class="flex items-center gap-1">
                  <span class="text-theme-accent">↑</span>
                  <span>Giver +{{ blessing.karma_to_giver }}</span>
                </div>
                <div class="flex items-center gap-1">
                  <span class="text-theme-accent">↓</span>
                  <span>Receiver +{{ blessing.karma_to_receiver }}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="glass-panel glass-panel-soft glass-gloss border border-theme-border/50 p-4 text-center text-xs text-theme-text-muted">
          <p>To bless a prayer, navigate to the <span class="font-medium text-theme-accent">📜 Akashic Records</span> and tap the Bless button on any prayer card.</p>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { computed, onMounted } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useBlessings } from '@/composables/useBlessings'
import { useKarmaShop } from '@/composables/useKarmaShop'

const prayers = usePrayers()
const blessings = useBlessings()
const shop = useKarmaShop()

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
}

onMounted(async () => {
  await blessings.fetchBlessingTypes()
  await prayers.fetchProfile()
})
</script>

<style scoped>
.shop-header {
  position: relative;
  overflow: clip;
}

.shop-header::after {
  content: "";
  position: absolute;
  inset: auto 0 -1px 0;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(213, 154, 23, 0.28), transparent);
}

.shop-header-glow {
  position: absolute;
  inset: -1.1rem auto auto -1rem;
  width: 12rem;
  height: 5.5rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.28) 0%, rgba(255, 223, 147, 0.1) 42%, transparent 74%);
  filter: blur(12px);
  pointer-events: none;
}
</style>