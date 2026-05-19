<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="visible" class="fixed inset-0 z-[9990] flex items-center justify-center p-4" @click.self="$emit('close')">
        <!-- Backdrop -->
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm"></div>

        <!-- Modal -->
        <div class="relative z-10 w-full max-w-2xl max-h-[85vh] overflow-y-auto glass-panel glass-panel-strong glass-gloss rounded-[28px] border border-theme-accent/30 p-6 sm:p-8">
          <!-- Close Button -->
          <button
            @click="$emit('close')"
            class="tactile-icon-btn absolute right-4 top-4 text-theme-text-muted hover:text-theme-purgatory"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>

          <!-- Loading -->
          <div v-if="loading" class="py-12 text-center text-theme-text-dim">
            Loading shout...
          </div>

          <!-- Shout Detail -->
          <template v-else-if="shout">
            <!-- Shout Author + Content -->
            <div class="mb-6">
              <div class="mb-4 flex items-center gap-3">
                <div class="h-12 w-12 flex-shrink-0 overflow-hidden rounded-full border-2 border-theme-accent/30 bg-theme-panel">
                  <img
                    v-if="shout.pfp_index != null"
                    :src="`/pfp/${shout.pfp_index}.png`"
                    :alt="shout.username"
                    class="h-full w-full object-cover"
                  />
                  <span v-else class="flex h-full w-full items-center justify-center text-lg text-theme-text-muted">
                    {{ (shout.username || '?')[0].toUpperCase() }}
                  </span>
                </div>
                <div>
                  <span class="font-semibold text-theme-text">{{ shout.username }}</span>
                  <p class="text-xs text-theme-text-muted">{{ formatDate(shout.created_at) }}</p>
                </div>
              </div>

              <p class="text-base leading-relaxed text-theme-text">
                {{ shout.crier_content || shout.content }}
              </p>

              <!-- Shout Blessings -->
              <div v-if="(shout.blessings || []).length > 0" class="mt-3 flex flex-wrap items-center gap-1.5">
                <span
                  v-for="blessing in shout.blessings"
                  :key="blessing.blessing_type_id"
                  class="chip inline-flex items-center gap-1 px-2 py-0.5 text-xs"
                >
                  {{ blessing.emoji }} {{ blessing.count }}
                </span>
              </div>

              <!-- Bless Shout Button -->
              <button
                @click.stop="showBlessingPicker = 'shout'"
                :disabled="blessingLoading"
                class="btn-ghost mt-3 px-3 py-1.5 text-xs text-theme-accent hover:text-theme-accent-dark"
              >
                ✨ Bless this Shout
              </button>
            </div>

            <!-- Divider -->
            <div class="mb-6 border-t border-theme-border"></div>

            <!-- Replies Header -->
            <div class="mb-4 flex items-center justify-between">
              <h3 class="text-lg font-semibold text-theme-text">
                Replies <span class="text-theme-text-muted">({{ totalReplies }})</span>
              </h3>
            </div>

            <!-- Replies List -->
            <div v-if="replies.length > 0" class="mb-6 space-y-4">
              <div
                v-for="reply in replies"
                :key="reply.id"
                class="rounded-2xl border border-theme-border bg-theme-panel/50 p-4"
              >
                <div class="mb-2 flex items-center gap-2">
                  <div class="h-8 w-8 flex-shrink-0 overflow-hidden rounded-full border border-theme-accent/20 bg-theme-panel">
                    <img
                      v-if="reply.pfp_index != null"
                      :src="`/pfp/${reply.pfp_index}.png`"
                      :alt="reply.username"
                      class="h-full w-full object-cover"
                    />
                    <span v-else class="flex h-full w-full items-center justify-center text-xs text-theme-text-muted">
                      {{ (reply.username || '?')[0].toUpperCase() }}
                    </span>
                  </div>
                  <span class="text-sm font-semibold text-theme-text">{{ reply.username }}</span>
                  <span class="text-xs text-theme-text-muted">{{ formatDate(reply.created_at) }}</span>
                </div>

                <p class="mb-2 text-sm leading-relaxed text-theme-text">
                  {{ reply.crier_content || reply.content }}
                </p>

                <!-- Reply Blessings -->
                <div v-if="(reply.blessings || []).length > 0" class="mb-2 flex flex-wrap items-center gap-1">
                  <span
                    v-for="blessing in reply.blessings"
                    :key="blessing.blessing_type_id"
                    class="chip inline-flex items-center gap-1 px-1.5 py-0.5 text-[0.65rem]"
                  >
                    {{ blessing.emoji }} {{ blessing.count }}
                  </span>
                </div>

                <!-- Bless Reply Button -->
                <button
                  @click="openReplyBlessing(reply)"
                  :disabled="blessingLoading"
                  class="btn-ghost px-2 py-1 text-xs text-theme-text-muted hover:text-theme-accent"
                >
                  ✨ Bless
                </button>
              </div>
            </div>

            <!-- No Replies -->
            <div v-else-if="!repliesLoading" class="mb-6 py-8 text-center text-sm text-theme-text-muted">
              No replies yet. Be the first to respond!
            </div>

            <!-- Load More Replies -->
            <button
              v-if="hasMoreReplies"
              @click="$emit('load-more-replies')"
              :disabled="repliesLoading"
              class="btn-secondary mb-6 w-full px-4 py-2 text-sm"
            >
              {{ repliesLoading ? 'Loading...' : 'Load More Replies' }}
            </button>

            <!-- Reply Form -->
            <div class="border-t border-theme-border pt-4">
              <div v-if="submitError" class="mb-3 rounded-xl border border-theme-purgatory/25 bg-theme-purgatory/10 p-2 text-xs text-theme-purgatory-dark">
                {{ submitError }}
              </div>

              <form @submit.prevent="handleReplySubmit" class="flex gap-2">
                <input
                  v-model="replyContent"
                  :disabled="submitting"
                  type="text"
                  class="form-field flex-1 px-4 py-2 text-sm"
                  placeholder="Write a reply..."
                  maxlength="500"
                />
                <button
                  type="submit"
                  :disabled="!replyContent.trim() || submitting"
                  class="btn-primary px-4 py-2 text-sm"
                >
                  {{ submitting ? 'Posting...' : 'Reply' }}
                </button>
              </form>

              <p class="mt-1.5 text-xs text-theme-text-muted">
                <span class="text-theme-accent">50 Gold</span> per reply • Filtered through the Town Crier
              </p>
            </div>

            <!-- Blessing Picker (Inline) -->
            <div v-if="showBlessingPicker" class="mt-4 rounded-2xl border border-theme-accent/30 bg-theme-panel/80 p-4">
              <div class="mb-3 flex items-center justify-between">
                <h4 class="text-sm font-semibold text-theme-text">
                  Bless this {{ showBlessingPicker === 'reply' ? 'Reply' : 'Shout' }}
                </h4>
                <button @click="showBlessingPicker = null" class="text-theme-text-muted hover:text-theme-text">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              <div v-if="blessingError" class="mb-2 text-xs text-theme-purgatory">{{ blessingError }}</div>

              <div class="flex flex-wrap gap-2">
                <button
                  v-for="blessing in blessingTypes"
                  :key="blessing.id"
                  @click="handleBless(blessing.id)"
                  :disabled="blessingLoading"
                  class="chip flex items-center gap-1.5 px-3 py-2 text-sm transition-all hover:border-theme-accent/40 hover:bg-theme-accent/10"
                  :title="`${blessing.name}: ${blessing.karma_cost} karma`"
                >
                  <span>{{ blessing.emoji }}</span>
                  <span class="text-xs text-theme-text-muted">{{ blessing.name }}</span>
                  <span class="text-xs text-theme-accent">{{ blessing.karma_cost }}</span>
                </button>
              </div>
            </div>
          </template>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ref } from 'vue'

const props = defineProps({
  visible: { type: Boolean, default: false },
  shout: { type: Object, default: null },
  replies: { type: Array, default: () => [] },
  totalReplies: { type: Number, default: 0 },
  hasMoreReplies: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
  repliesLoading: { type: Boolean, default: false },
  submitting: { type: Boolean, default: false },
  submitError: { type: String, default: null },
  blessingLoading: { type: Boolean, default: false },
  blessingError: { type: String, default: null },
  blessingTypes: { type: Array, default: () => [] },
})

const emit = defineEmits([
  'close',
  'submit-reply',
  'grant-blessing',
  'load-more-replies',
])

const replyContent = ref('')
const showBlessingPicker = ref(null) // null | 'shout' | 'reply'
const selectedReplyId = ref(null)

function openReplyBlessing(reply) {
  selectedReplyId.value = reply.id
  showBlessingPicker.value = 'reply'
}

function handleReplySubmit() {
  if (!replyContent.value.trim()) return
  emit('submit-reply', replyContent.value.trim())
  replyContent.value = ''
}

function handleBless(blessingTypeId) {
  const replyId = showBlessingPicker.value === 'reply' ? selectedReplyId.value : null
  emit('grant-blessing', { blessingTypeId, replyId })
  showBlessingPicker.value = null
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