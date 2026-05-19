<template>
  <div
    class="glass-panel glass-panel-soft glass-gloss relative cursor-pointer border border-theme-border p-5 transition-all duration-300 hover:-translate-y-0.5 hover:border-theme-accent/30"
    @click="$emit('select', shout)"
  >
    <!-- Author Row -->
    <div class="mb-3 flex items-center gap-3">
      <!-- PFP -->
      <div class="h-10 w-10 flex-shrink-0 overflow-hidden rounded-full border-2 border-theme-accent/20 bg-theme-panel">
        <img
          v-if="shout.pfp_index != null"
          :src="`/pfp/${shout.pfp_index}.png`"
          :alt="shout.username"
          class="h-full w-full object-cover"
        />
        <span v-else class="flex h-full w-full items-center justify-center text-sm text-theme-text-muted">
          {{ (shout.username || '?')[0].toUpperCase() }}
        </span>
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-semibold text-theme-text truncate">{{ shout.username || 'Unknown' }}</span>
          <!-- Sect Badge -->
          <span
            v-if="shout.author_sect_type"
            class="rounded-full px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wider"
            :class="sectBadgeClass(shout.author_sect_type)"
          >
            {{ sectLabel(shout.author_sect_type) }}
          </span>
          <!-- Sect-Only Badge -->
          <span
            v-if="shout.is_sect_only"
            class="rounded-full border border-amber-500/30 bg-amber-500/10 px-2 py-0.5 text-[0.65rem] font-medium text-amber-400"
            title="Only visible to your sect"
          >
            🔒 Sect
          </span>
          <!-- Synod Context Badge -->
          <span
            v-if="shout.context === 'synod'"
            class="rounded-full border border-purple-500/30 bg-purple-500/10 px-2 py-0.5 text-[0.65rem] font-medium text-purple-400"
          >
            Synod
          </span>
        </div>
        <p class="text-xs text-theme-text-muted">{{ formatDate(shout.created_at) }}</p>
      </div>
    </div>

    <!-- Content -->
    <p class="mb-3 text-sm leading-relaxed text-theme-text">
      {{ shout.crier_content || shout.content }}
    </p>

    <!-- Footer: Blessings + Reply Count -->
    <div class="flex items-center justify-between">
      <!-- Blessing Badges -->
      <div class="flex flex-wrap items-center gap-1.5">
        <span
          v-for="blessing in (shout.blessings || [])"
          :key="blessing.blessing_type_id"
          class="chip inline-flex items-center gap-1 px-2 py-0.5 text-xs"
          :title="blessing.name"
        >
          {{ blessing.emoji }} <span class="text-theme-text-muted">{{ blessing.count }}</span>
        </span>
      </div>

      <!-- Reply Count -->
      <div class="flex items-center gap-1 text-xs text-theme-text-muted">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
        </svg>
        <span>{{ shout.reply_count || 0 }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
const props = defineProps({
  shout: { type: Object, required: true },
})

defineEmits(['select'])

const SECT_LABELS = {
  gilded_path: 'GP',
  holy_way: 'HW',
  final_watch: 'FW',
  black_tribunal: 'BT',
}

const SECT_CLASSES = {
  gilded_path: 'border-yellow-500/30 bg-yellow-500/10 text-yellow-400',
  holy_way: 'border-blue-400/30 bg-blue-400/10 text-blue-300',
  final_watch: 'border-slate-400/30 bg-slate-400/10 text-slate-300',
  black_tribunal: 'border-red-500/30 bg-red-500/10 text-red-400',
}

function sectLabel(sectType) {
  return SECT_LABELS[sectType] || ''
}

function sectBadgeClass(sectType) {
  return SECT_CLASSES[sectType] || ''
}

function formatDate(dateString) {
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}
</script>