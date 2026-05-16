<template>
  <Transition name="karma-toast">
    <div v-if="visible" class="karma-toast" :class="type">
      <span class="karma-toast-icon">{{ type === 'positive' ? '✨' : '😈' }}</span>
      <span class="karma-toast-text">
        {{ type === 'positive' ? '+' : '' }}{{ amount }} Karma
      </span>
      <span class="karma-toast-label">{{ label }}</span>
    </div>
  </Transition>
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
  top: 1rem;
  right: 1rem;
  z-index: 10000;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1.25rem;
  border-radius: 12px;
  font-weight: 600;
  font-size: 0.95rem;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.3);
  backdrop-filter: blur(8px);
  animation: slideIn 0.3s ease-out;
}

.karma-toast.positive {
  background: linear-gradient(135deg, rgba(201, 168, 76, 0.2), rgba(245, 230, 163, 0.15));
  border: 1px solid rgba(201, 168, 76, 0.5);
  color: #f5e6a3;
}

.karma-toast.negative {
  background: linear-gradient(135deg, rgba(220, 38, 38, 0.2), rgba(248, 113, 113, 0.15));
  border: 1px solid rgba(220, 38, 38, 0.5);
  color: #fca5a5;
}

.karma-toast-icon {
  font-size: 1.25rem;
}

.karma-toast-text {
  font-size: 1.1rem;
  font-weight: 700;
}

.karma-toast-label {
  font-size: 0.8rem;
  font-weight: 400;
  opacity: 0.8;
}

/* Transition */
.karma-toast-enter-active {
  animation: slideIn 0.3s ease-out;
}

.karma-toast-leave-active {
  animation: slideOut 0.3s ease-in;
}

@keyframes slideIn {
  from {
    opacity: 0;
    transform: translateX(100%) scale(0.9);
  }
  to {
    opacity: 1;
    transform: translateX(0) scale(1);
  }
}

@keyframes slideOut {
  from {
    opacity: 1;
    transform: translateX(0) scale(1);
  }
  to {
    opacity: 0;
    transform: translateX(100%) scale(0.9);
  }
}
</style>