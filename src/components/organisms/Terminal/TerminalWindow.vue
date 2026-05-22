<template>
  <div class="term-window" @mouseup="handleMouseUp" @dblclick="handleDblClick">
    <!-- Scanline overlay -->
    <div class="term-scanlines" aria-hidden="true"></div>
    <!-- Subtle CRT flicker -->
    <div class="term-flicker" aria-hidden="true"></div>

    <!-- Terminal content area (scrollable, includes input) -->
    <div class="term-content" ref="contentRef">
      <!-- Output lines -->
      <div
        v-for="(line, i) in terminal.lines"
        :key="i"
        class="term-line"
        :class="[
          line.class || '',
          { 'term-line--typing': line._typing }
        ]"
      >
        <span v-if="line.text" class="term-line-text">{{ line.text }}</span>
        <span v-else class="term-line-spacer">&nbsp;</span>
      </div>

      <!-- Input line (inline with content) -->
      <div class="term-input-row" ref="inputRowRef">
        <span class="term-prompt">{{ terminal.getPrompt() }}</span>
        <textarea
          ref="inputRef"
          v-model="inputValue"
          class="term-input"
          :class="{ 'term-input--blocked': isBlocked }"
          :disabled="isBlocked"
          :placeholder="isBlocked ? 'Please wait...' : ''"
          rows="1"
          spellcheck="false"
          autocomplete="off"
          autocapitalize="off"
          @keydown="handleKeydown"
          @input="autoResize"
          @focus="isFocused = true"
          @blur="isFocused = false"
        ></textarea>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted, getCurrentInstance } from 'vue'

const props = defineProps({
  terminal: { type: Object, required: true },
  title: { type: String, default: 'Terminal' },
})

const contentRef = ref(null)
const inputRowRef = ref(null)
const inputRef = ref(null)
const inputValue = ref('')
const isFocused = ref(false)

/** Vue component instance — used to check if this terminal's DOM owns activeElement */
const instance = getCurrentInstance()

/**
 * Block user input when:
 * - Manually flagged as busy (boot sequence, client scripts), OR
 * - A typewriter animation is running, OR
 * - A command is processing AND no interactive session (readLine/readKey) is waiting
 */
const isBlocked = computed(() => {
  if (props.terminal.busy) return true
  if (props.terminal.isTyping) return true
  if (props.terminal.processingCommand && !props.terminal.hasActiveSession()) return true
  return false
})

function focusInput() {
  inputRef.value?.focus()
}

function hasSelection() {
  const sel = window.getSelection()
  return sel && sel.toString().trim().length > 0
}

function handleMouseUp(e) {
  // Let the user select/copy text without stealing focus
  if (hasSelection()) return
  // Don't focus if clicking a link-like element or interactive child
  if (e.target.closest('a, button, [role="button"]')) return
  focusInput()
}

function handleDblClick() {
  // After double-click selects a word, don't steal focus
  if (hasSelection()) return
  focusInput()
}

/**
 * Auto-resize the textarea to fit its content, allowing multi-line
 * input that properly pushes down elements below.
 */
function autoResize() {
  const el = inputRef.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = el.scrollHeight + 'px'
}

function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    // Guard: don't process if blocked
    if (isBlocked.value) return
    const cmd = inputValue.value
    inputValue.value = ''
    // Reset textarea height
    if (inputRef.value) {
      inputRef.value.style.height = 'auto'
    }
    props.terminal.processCommand(cmd)
  } else if (e.key === 'ArrowUp') {
    e.preventDefault()
    const prev = props.terminal.navigateHistory('up')
    if (prev !== null) inputValue.value = prev
    nextTick(() => autoResize())
  } else if (e.key === 'ArrowDown') {
    e.preventDefault()
    const next = props.terminal.navigateHistory('down')
    if (next !== null) inputValue.value = next
    nextTick(() => autoResize())
  } else if (e.key === 'Tab') {
    e.preventDefault()
    // Tab completion — future feature
  } else if (e.key === 'l' && e.ctrlKey) {
    e.preventDefault()
    props.terminal.clear()
  }
}

function scrollToBottom() {
  if (!contentRef.value) return
  contentRef.value.scrollTo({
    top: contentRef.value.scrollHeight,
    behavior: 'instant',
  })
}

// Auto-scroll on new lines or input changes
watch(
  () => [props.terminal.lines.length, inputValue.value],
  () => {
    nextTick(() => scrollToBottom())
  },
  { deep: true }
)

// Also scroll when input row content changes (wrapping)
watch(
  () => inputRowRef.value?.offsetHeight,
  () => {
    nextTick(() => scrollToBottom())
  }
)

// Typewriter effect: scroll on every character typed
watch(
  () => {
    const lastLine = props.terminal.lines[props.terminal.lines.length - 1]
    return lastLine?.text?.length ?? 0
  },
  () => {
    nextTick(() => scrollToBottom())
  }
)

// When the terminal becomes unblocked (onboarding done, command finished, typewriter
// ended, etc.), scroll to bottom and focus the input — but only if this terminal
// was the last-active window. Universal catch-all for "ready to type" state.
watch(
  isBlocked,
  (blocked, wasBlocked) => {
    if (!blocked && wasBlocked) {
      nextTick(() => {
        scrollToBottom()
        safeFocusInput()
      })
    }
  }
)

// ── Focus & Scroll Handlers ──

/**
 * Check if the currently focused element belongs to THIS terminal instance.
 * Returns false if focus is on body, null, or in a different terminal tab/window.
 */
function isThisTerminalFocused() {
  const el = document.activeElement
  if (!el || el === document.body) return true // nothing focused = safe to claim
  // If the active element is inside this component's DOM tree, it's ours
  if (instance && instance.vnode && instance.vnode.el) {
    return instance.vnode.el.contains(el)
  }
  return true
}

/**
 * Focus the input textarea — but only if this terminal was the last-focused window.
 * Prevents stealing focus from another terminal tab or external element.
 */
function safeFocusInput() {
  if (!isThisTerminalFocused()) return
  focusInput()
}

/** Cleanup handles for event listeners */
const cleanupFns = []

onMounted(() => {
  // Initial auto-focus
  focusInput()

  // When anything requests focus (readLine, readKey, getInput):
  // scroll to bottom unconditionally, then focus if this terminal was last active.
  cleanupFns.push(
    props.terminal.on('focusRequest', () => {
      nextTick(() => {
        scrollToBottom()
        safeFocusInput()
      })
    })
  )

  // Belt-and-suspenders: scroll to bottom whenever a session starts.
  cleanupFns.push(
    props.terminal.on('sessionStart', () => {
      nextTick(() => scrollToBottom())
    })
  )
})

onUnmounted(() => {
  cleanupFns.forEach(fn => { if (typeof fn === 'function') fn() })
})
</script>

<style scoped>
/* ─── Terminal Window ─── */
.term-window {
  position: relative;
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  overflow: hidden;
  background:
    linear-gradient(180deg, rgba(9, 12, 16, 0.98), rgba(11, 15, 19, 0.99)),
    linear-gradient(145deg, rgba(14, 18, 23, 0.97), rgba(7, 9, 12, 0.99));
  font-family: "JetBrains Mono", "Cascadia Code", "Fira Code", monospace;
  font-size: 0.8125rem;
  line-height: 1.55;
  color: var(--war-text, #d7e0e8);
}

/* ─── Scanline Overlay ─── */
.term-scanlines {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 50;
  background:
    repeating-linear-gradient(
      0deg,
      transparent 0px,
      transparent 2px,
      rgba(0, 0, 0, 0.06) 2px,
      rgba(0, 0, 0, 0.06) 4px
    );
  opacity: 0.55;
}

/* ─── CRT Flicker ─── */
.term-flicker {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 49;
  opacity: 0;
  background: rgba(185, 197, 207, 0.02);
  animation: term-flicker-anim 8s ease-in-out infinite;
}

@keyframes term-flicker-anim {
  0%, 100% { opacity: 0; }
  2% { opacity: 0.4; }
  2.5% { opacity: 0; }
  48% { opacity: 0; }
  48.5% { opacity: 0.25; }
  49% { opacity: 0; }
  78% { opacity: 0; }
  78.3% { opacity: 0.15; }
  78.6% { opacity: 0; }
}

/* ─── Content Area (Scrollable) ─── */
.term-content {
  flex: 1 1 0;
  overflow-y: auto;
  padding: 0.75rem 1rem;
  scrollbar-width: thin;
  scrollbar-color: rgba(156, 168, 180, 0.32) rgba(166, 178, 190, 0.06);
  display: flex;
  flex-direction: column;
}

.term-content::-webkit-scrollbar {
  width: 6px;
}

.term-content::-webkit-scrollbar-track {
  background: rgba(166, 178, 190, 0.06);
  border-radius: 2px;
}

.term-content::-webkit-scrollbar-thumb {
  background: linear-gradient(
    180deg,
    rgba(185, 197, 207, 0.38),
    rgba(161, 173, 183, 0.28) 35%,
    rgba(139, 125, 91, 0.24) 65%,
    rgba(185, 197, 207, 0.34)
  );
  border-radius: 2px;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.term-content::-webkit-scrollbar-thumb:hover {
  background: linear-gradient(
    180deg,
    rgba(182, 144, 91, 0.28),
    rgba(185, 197, 207, 0.38) 35%,
    rgba(161, 173, 183, 0.32) 65%,
    rgba(182, 144, 91, 0.24)
  );
}

/* ─── Line Styles ─── */
.term-line {
  white-space: pre-wrap;
  word-break: break-word;
  overflow-wrap: break-word;
}

.term-line-text {
  display: inline;
}

.term-line-spacer {
  display: inline;
  visibility: hidden;
}

/* ─── Color Classes ─── */
.term-line.term-prompt {
  color: var(--war-brass, #b6905b);
}

.term-line.term-steel {
  color: var(--war-steel, #b9c5cf);
}

.term-line.term-brass {
  color: var(--war-brass-light, #d4ba8e);
  text-shadow: 0 0 8px rgba(182, 144, 91, 0.25);
}

.term-line.term-muted {
  color: var(--war-muted, #8291a0);
}

.term-line.term-dim {
  color: var(--war-dim, #677482);
}

.term-line.term-ally {
  color: var(--war-ally, #6c8c83);
  text-shadow: 0 0 6px rgba(108, 140, 131, 0.2);
}

.term-line.term-enemy {
  color: var(--war-enemy, #9b6b66);
  text-shadow: 0 0 6px rgba(155, 107, 102, 0.2);
}

.term-line.term-text {
  color: var(--war-text, #d7e0e8);
}

/* ─── Input Row (Inline) ─── */
.term-input-row {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  min-height: 1.3em;
  white-space: pre-wrap;
  word-break: break-all;
  margin-top: 0.25rem;
}

.term-input-row .term-prompt {
  color: var(--war-brass, #b6905b);
  font-weight: 700;
  white-space: nowrap;
  user-select: none;
  flex-shrink: 0;
  padding-top: 0.15em;
}

.term-input {
  flex: 1 1 0;
  background: transparent;
  border: none;
  outline: none;
  resize: none;
  overflow: hidden;
  color: var(--war-text, #d7e0e8);
  font-family: inherit;
  font-size: inherit;
  line-height: inherit;
  caret-color: var(--war-brass, #b6905b);
  padding: 0;
  margin: 0;
  min-height: 1.3em;
}

.term-input::placeholder {
  color: var(--war-dim, #677482);
  opacity: 0.6;
}

.term-input--blocked {
  opacity: 0.35;
  filter: grayscale(0.5);
  pointer-events: none;
  cursor: not-allowed;
}

/* ─── Mobile ─── */
@media (max-width: 640px) {
  .term-window {
    font-size: 0.75rem;
    line-height: 1.5;
  }

  .term-content {
    padding: 0.5rem 0.65rem;
  }

  .term-input-row {
    gap: 0.4rem;
  }
}
</style>
