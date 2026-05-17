<template>
  <div
    v-if="blessings && blessings.length > 0"
    class="blessing-badge-bar flex flex-wrap items-center gap-1.5"
    @click="$emit('showDetail')"
  >
    <span
      v-for="b in visibleBlessings"
      :key="b.blessing_type_id"
      class="chip gap-1 px-2 py-0.5 text-xs font-medium text-theme-accent cursor-pointer transition-colors duration-200 hover:bg-theme-accent/15"
      :title="`${b.name} ×${b.count}`"
    >
      <span>{{ b.emoji }}</span>
      <span v-if="b.count > 1" class="text-[0.65rem] text-theme-text-muted">×{{ b.count }}</span>
    </span>
    <button
      v-if="overflowCount > 0"
      class="chip cursor-pointer px-2 py-0.5 text-[0.65rem] font-medium text-theme-text-muted transition-colors duration-200 hover:text-theme-accent hover:bg-theme-accent/15"
      @click.stop="$emit('showDetail')"
    >
      +{{ overflowCount }} more
    </button>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  blessings: { type: Array, default: () => [] },
  maxVisible: { type: Number, default: 5 },
})

defineEmits(['showDetail'])

const visibleBlessings = computed(() => {
  return props.blessings.slice(0, props.maxVisible)
})

const overflowCount = computed(() => {
  const total = props.blessings.length
  return total > props.maxVisible ? total - props.maxVisible : 0
})
</script>

<style scoped>
.blessing-badge-bar {
  cursor: pointer;
}
</style>