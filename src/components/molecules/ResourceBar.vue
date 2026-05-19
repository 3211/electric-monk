<template>
  <div class="resource-bar">
    <div class="resource-grid">
      <!-- Karma -->
      <div class="resource-chip" title="Karma">
        <span class="resource-emoji">{{ prayers.karmaEmoji }}</span>
        <span class="resource-label">Karma</span>
        <span class="resource-value" :class="karmaClass">{{ prayers.karma }}</span>
      </div>
      <!-- Mana -->
      <div class="resource-chip" title="Mana">
        <span class="resource-emoji">💧</span>
        <span class="resource-label">Mana</span>
        <span class="resource-value resource-mana">{{ economy.mana }}</span>
      </div>
      <!-- Gold -->
      <div class="resource-chip" title="Gold">
        <span class="resource-emoji">💰</span>
        <span class="resource-label">Gold</span>
        <span class="resource-value resource-gold">{{ economy.gold }}</span>
      </div>
      <!-- Food -->
      <div class="resource-chip" title="Food">
        <span class="resource-emoji">🌾</span>
        <span class="resource-label">Food</span>
        <span class="resource-value resource-food">{{ economy.food }}</span>
      </div>
      <!-- Dogma -->
      <div v-if="economy.dogma > 0 || economy.sectType" class="resource-chip" title="Dogma">
        <span class="resource-emoji">📑</span>
        <span class="resource-label">Dogma</span>
        <span class="resource-value resource-dogma">{{ economy.dogma }}</span>
      </div>
      <!-- Heresy -->
      <div v-if="economy.heresy > 0" class="resource-chip" title="Heresy">
        <span class="resource-emoji">✝️</span>
        <span class="resource-label">Heresy</span>
        <span class="resource-value resource-heresy">{{ economy.heresy }}</span>
      </div>
      <!-- Sacred Acres (conditional) -->
      <div v-if="showAcres && economy.sectType" class="resource-chip" title="Sacred Acres">
        <span class="resource-emoji">🏘️</span>
        <span class="resource-label">Acres</span>
        <span class="resource-value resource-acres">{{ economy.sacredAcresFree }}<span class="resource-value-muted">/{{ economy.sacredAcres }}</span></span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { usePrayers } from '@/composables/usePrayers'
import { useEconomy } from '@/composables/useEconomy'

const props = defineProps({
  /** Whether to show the Sacred Acres indicator (only on Altar and Shop tabs) */
  showAcres: { type: Boolean, default: false },
})

const prayers = usePrayers()
const economy = useEconomy()

const karmaClass = computed(() => {
  if (prayers.karma > 0) return 'resource-karma-positive'
  if (prayers.karma < 0) return 'resource-karma-negative'
  return 'resource-karma-zero'
})
</script>

<style scoped>
.resource-bar {
  display: flex;
  align-items: center;
}

.resource-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 0.375rem;
  align-items: center;
}

/* Mobile: 3-column grid */
@media (max-width: 767px) {
  .resource-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 0.375rem;
    width: 100%;
  }

  .resource-chip {
    justify-content: center;
    text-align: center;
  }
}

.resource-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 0.25rem 0.5rem;
  border-radius: var(--radius-chip, 999px);
  border: 1px solid rgba(139, 125, 91, 0.14);
  background: rgba(255, 253, 248, 0.55);
  backdrop-filter: blur(8px);
  font-size: 0.7rem;
  line-height: 1.3;
  white-space: nowrap;
  transition: all 180ms ease-out;
}

.resource-chip:hover {
  border-color: rgba(213, 154, 23, 0.22);
  background: rgba(255, 251, 243, 0.72);
}

.resource-emoji {
  font-size: 0.8rem;
  line-height: 1;
}

.resource-label {
  color: var(--theme-text-muted, #8b7d5b);
  font-weight: 500;
}

.resource-value {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.resource-value-muted {
  color: var(--theme-text-muted, #8b7d5b);
  font-weight: 400;
}

/* Value color classes */
.resource-karma-positive {
  color: var(--theme-accent, #d59a17);
}

.resource-karma-negative {
  color: var(--theme-purgatory, #a85d32);
}

.resource-karma-zero {
  color: var(--theme-text-dim, #6b5e3e);
}

.resource-mana {
  color: #3b82f6;
}

.resource-gold {
  color: #d97706;
}

.resource-food {
  color: #16a34a;
}

.resource-dogma {
  color: #d97706;
}

.resource-heresy {
  color: #ef4444;
}

.resource-acres {
  color: #16a34a;
}

/* ─── Evil theme ─── */
.app-shell--evil .resource-chip {
  border-color: rgba(137, 108, 178, 0.22);
  background: rgba(255, 255, 255, 0.04);
}

.app-shell--evil .resource-chip:hover {
  border-color: rgba(126, 255, 161, 0.18);
  background: rgba(126, 255, 161, 0.08);
}

.app-shell--evil .resource-label {
  color: #8b9ba8;
}

.app-shell--evil .resource-karma-positive {
  color: #7effa1;
}

.app-shell--evil .resource-karma-negative {
  color: #ff6bd6;
}

.app-shell--evil .resource-karma-zero {
  color: #6b7a88;
}

.app-shell--evil .resource-mana {
  color: #7eaaff;
}

.app-shell--evil .resource-gold {
  color: #f0b942;
}

.app-shell--evil .resource-food {
  color: #4ade80;
}

.app-shell--evil .resource-dogma {
  color: #f0b942;
}

.app-shell--evil .resource-heresy {
  color: #ff6bd6;
}

.app-shell--evil .resource-acres {
  color: #4ade80;
}

.app-shell--evil .resource-value-muted {
  color: #5a6878;
}

/* ─── War theme ─── */
.app-shell--war .resource-chip {
  border-color: rgba(164, 176, 189, 0.14);
  background: rgba(255, 255, 255, 0.03);
}

.app-shell--war .resource-chip:hover {
  border-color: rgba(182, 144, 91, 0.18);
  background: rgba(182, 144, 91, 0.06);
}

.app-shell--war .resource-label {
  color: #6b7a88;
}

.app-shell--war .resource-karma-positive {
  color: #d4ba8e;
}

.app-shell--war .resource-karma-negative {
  color: #e07070;
}

.app-shell--war .resource-karma-zero {
  color: #5a6878;
}

.app-shell--war .resource-mana {
  color: #7eaaff;
}

.app-shell--war .resource-gold {
  color: #d4ba8e;
}

.app-shell--war .resource-food {
  color: #6bc98e;
}

.app-shell--war .resource-dogma {
  color: #d4ba8e;
}

.app-shell--war .resource-heresy {
  color: #e07070;
}

.app-shell--war .resource-acres {
  color: #6bc98e;
}

.app-shell--war .resource-value-muted {
  color: #4a5568;
}
</style>