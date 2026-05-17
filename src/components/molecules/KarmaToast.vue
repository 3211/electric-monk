<template>
  <Teleport to="body">
    <Transition name="karma-toast">
      <div v-if="visible" class="karma-toast" :class="type">
        <span class="karma-toast-icon">{{ type === 'positive' ? '✨' : '😈' }}</span>
        <span class="karma-toast-text">
          {{ type === 'positive' ? '+' : '' }}{{ amount }} Karma
        </span>
        <span class="karma-toast-label">{{ label }}</span>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ref, watch } from 'vue'

const props = defineProps({
  amount: { type: Number, default: 0 },
  type: { type: String, default: 'positive' }, // 'positive' or 'negative'
  label: { type: String, default: '' },
  duration: { type: Number, default: 3000 },
})

const emit = defineEmits(['dismiss'])

const visible = ref(false)
let dismissTimer = null

watch(() => props.amount, (newVal) => {
  if (newVal !== 0) {
    // Show the toast
    visible.value = true
    // Auto-dismiss after duration
    if (dismissTimer) clearTimeout(dismissTimer)
    dismissTimer = setTimeout(() => {
      visible.value = false
      emit('dismiss')
    }, props.duration)
  }
})
</script>

<style scoped>
.karma-toast {
  position: fixed;
  top: 1.5rem;
  right: 1.5rem;
  z-index: 2147483000;
  pointer-events: none;
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.55rem;
  max-width: min(92vw, 28rem);
  padding: 0.9rem 1.15rem;
  border-radius: 20px;
  font-size: 0.95rem;
  font-weight: 600;
  backdrop-filter: blur(14px);
  box-shadow: 0 18px 38px rgba(48, 38, 21, 0.16), 0 0 32px rgba(240, 182, 59, 0.08);
}

.karma-toast.positive {
  background: linear-gradient(135deg, rgba(255, 252, 245, 0.92), rgba(247, 231, 190, 0.88));
  border: 1px solid rgba(201, 168, 76, 0.34);
  color: var(--theme-text);
}

.karma-toast.negative {
  background: linear-gradient(135deg, rgba(255, 248, 241, 0.92), rgba(233, 209, 188, 0.88));
  border: 1px solid rgba(168, 93, 50, 0.3);
  color: var(--theme-purgatory-dark);
}

.karma-toast-icon {
  font-size: 1.2rem;
}

.karma-toast-text {
  font-size: 1.05rem;
  font-weight: 700;
  letter-spacing: -0.03em;
  font-variant-numeric: tabular-nums;
}

.karma-toast-label {
  font-size: 0.8rem;
  font-weight: 500;
  opacity: 0.84;
}

.karma-toast-enter-active {
  animation: toastSpringIn 320ms var(--ease-silk-settle);
}

.karma-toast-leave-active {
  animation: toastSpringOut 220ms var(--ease-standard);
}

@media (max-width: 640px) {
  .karma-toast {
    left: 1rem;
    right: 1rem;
    top: 1rem;
    max-width: none;
  }
}
</style>