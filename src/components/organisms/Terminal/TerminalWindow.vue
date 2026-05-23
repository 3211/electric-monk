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
          line.segments ? '' : (line.class || ''),
          { 'term-line--typing': line._typing }
        ]"
      >
        <template v-if="line.segments">
          <span
            v-for="(segment, idx) in line.segments"
            :key="idx"
            class="term-line-text"
            :class="segment.class || line.class || ''"
          >
            <template v-for="(token, tIdx) in tokenize(segment.text)" :key="tIdx">
              <span v-if="token.isSpace" class="term-space">{{ token.text }}</span>
              <span v-else class="term-word">
                <span
                  v-for="(char, cIdx) in graphemeChars(token.text)"
                  :key="cIdx"
                  class="char"
                >{{ char }}</span>
              </span>
            </template>
          </span>
        </template>
        <template v-else-if="line.text">
          <span class="term-line-text">
            <template v-for="(token, tIdx) in tokenize(line.text)" :key="tIdx">
              <span v-if="token.isSpace" class="term-space">{{ token.text }}</span>
              <span v-else class="term-word">
                <span
                  v-for="(char, cIdx) in graphemeChars(token.text)"
                  :key="cIdx"
                  class="char"
                >{{ char }}</span>
              </span>
            </template>
          </span>
        </template>
        <span v-else class="term-line-spacer">&nbsp;</span>
      </div>

      <!-- Input line (inline with content). Drops opacity to 0 during menus to hide cursor seamlessly -->
      <div 
        class="term-input-row" 
        ref="inputRowRef" 
        :style="{ opacity: terminal.activeSession?.type === 'readMenu' ? 0 : 1 }"
      >
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
          :inputmode="terminal.activeSession?.type === 'readMenu' ? 'numeric' : 'text'"
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

let _segmenter = null
function getSegmenter() {
  if (!_segmenter) {
    _segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' })
  }
  return _segmenter
}

function graphemeChars(text) {
  if (typeof text !== 'string') return []
  return Array.from(getSegmenter().segment(text)).map(s => s.segment)
}

function tokenize(text) {
  if (typeof text !== 'string') return []
  const parts = text.split(/(\s+)/)
  const tokens = []
  for (const part of parts) {
    if (!part) continue
    tokens.push({
      text: part,
      isSpace: /^\s+$/.test(part)
    })
  }
  return tokens
}

const props = defineProps({
  terminal: { type: Object, required: true },
  title: { type: String, default: 'Terminal' },
})

const contentRef = ref(null)
const inputRowRef = ref(null)
const inputRef = ref(null)
const inputValue = ref('')
const isFocused = ref(false)

const instance = getCurrentInstance()

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
  if (hasSelection()) return
  if (e.target.closest('a, button, [role="button"]')) return
  focusInput()
}

function handleDblClick() {
  if (hasSelection()) return
  focusInput()
}

function autoResize() {
  const el = inputRef.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = el.scrollHeight + 'px'
}

function handleKeydown(e) {
  if (props.terminal.activeSession?.type === 'readMenu') {
    e.preventDefault()
    const interactiveKeys = ['ArrowUp', 'ArrowDown', 'Enter', 'w', 'a', 's', 'd', 'i', 'j', 'k', 'l', '8', '2', '4', '6', ',', '.', '<', '>', '+', '-']
    if (interactiveKeys.includes(e.key)) {
      props.terminal.handleInteractiveKey(e.key)
    }
    return
  }

  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    if (isBlocked.value) return
    const cmd = inputValue.value
    inputValue.value = ''
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

watch(
  () => [props.terminal.lines.length, inputValue.value],
  () => { nextTick(() => scrollToBottom()) },
  { deep: true }
)

watch(
  () => inputRowRef.value?.offsetHeight,
  () => { nextTick(() => scrollToBottom()) }
)

watch(
  () => {
    const lastLine = props.terminal.lines[props.terminal.lines.length - 1]
    return lastLine?.text?.length ?? 0
  },
  () => { nextTick(() => scrollToBottom()) }
)

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

function isThisTerminalFocused() {
  const el = document.activeElement
  if (!el || el === document.body) return true 
  if (instance && instance.vnode && instance.vnode.el) {
    return instance.vnode.el.contains(el)
  }
  return true
}

function safeFocusInput() {
  if (!isThisTerminalFocused()) return
  focusInput()
}

const cleanupFns = []

onMounted(() => {
  focusInput()

  cleanupFns.push(
    props.terminal.on('focusRequest', () => {
      nextTick(() => {
        scrollToBottom()
        safeFocusInput()
      })
    })
  )

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
  font-family: "JetBrains Mono", "Cascadia Code", "Fira Code", monospace, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";
  font-size: 0.8125rem;
  line-height: 1.55;
  color: var(--war-text, #d7e0e8);
}

.term-window::selection,
.term-window *::selection {
  background: rgba(182, 144, 91, 0.3);
  color: var(--war-brass-light, #d4ba8e);
  text-shadow: 0 0 8px rgba(212, 163, 89, 0.6);
}

/* ─── Scanline Overlay ─── */
.term-scanlines {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 50;
  background: linear-gradient(rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.25) 50%), linear-gradient(90deg, rgba(255, 0, 0, 0.06), rgba(0, 255, 0, 0.02), rgba(0, 0, 255, 0.06));
  background-size: 100% 4px, 6px 100%;
}

/* ─── CRT Flicker ─── */
.term-flicker {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 49;
  background: rgba(185, 197, 207, 0.02);
  animation: term-flicker-anim 0.15s infinite;
}

@keyframes term-flicker-anim {
  0% { opacity: 0.985; }
  50% { opacity: 0.995; }
  100% { opacity: 0.985; }
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
  word-break: break-word;     /* Allows normal words to wrap at space boundaries */
  overflow-wrap: break-word;  /* Breaks unbreakable strings if they hit the edge */
}

.term-line-text {
  display: inline;
}

.term-line-spacer {
  display: inline;
  visibility: hidden;
}

/* Hard-Square Liquid Spacing */
.term-line .char {
  display: inline-block;
  width: 1ch;
  text-align: center;
}

/* Unbreakable word block to force native browser wrapping at word boundaries */
/* FIX: Changed from inline-block to inline so the layout grid can split */
.term-line .term-word {
  display: inline;
  white-space: pre-wrap;
}

/* Standard breakable space to maintain monospace grid consistency */
.term-line .term-space {
  display: inline;
  white-space: pre-wrap;
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
  transition: opacity 100ms ease;
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