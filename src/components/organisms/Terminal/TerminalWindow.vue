<template>
  <div class="term-window" ref="windowRef" @mouseup="handleMouseUp" @dblclick="handleDblClick">
    <!-- Immersive CRT screen wrapper that subjects both screen and scanlines to the ripple warp -->
    <div class="term-screen">
      <!-- Scanline overlay -->
      <div class="term-scanlines" aria-hidden="true"></div>
      <!-- Subtle CRT flicker -->
      <div class="term-flicker" aria-hidden="true"></div>

      <!-- Terminal content area (scrollable, includes input) -->
      <div class="term-content" ref="contentRef" @scroll="handleScroll">
        <!-- Output lines -->
        <div
          v-for="(line, i) in displayedLines"
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

        <!-- Input line (inline with content) -->
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

    <!-- Invisible SVG filter definition for CRT diagonal wave ripple -->
    <svg class="term-ripple-svg" aria-hidden="true" width="0" height="0" style="position: absolute; pointer-events: none;">
      <defs>
        <filter id="crt-ripple" x="-10%" y="-10%" width="120%" height="120%">
          <!-- Generate a soft, organic wave noise layout -->
          <feTurbulence 
            type="turbulence" 
            baseFrequency="0.008 0.006" 
            numOctaves="1" 
            result="noise" 
          />
          <!-- Offset noise diagonally to simulate waves sweeping from bottom-left to top-right -->
          <feOffset result="diagonalWarp">
            <animate 
              attributeName="dx" 
              from="0" 
              to="-500" 
              dur="25s" 
              repeatCount="indefinite" 
            />
            <animate 
              attributeName="dy" 
              from="0" 
              to="500" 
              dur="25s" 
              repeatCount="indefinite" 
            />
          </feOffset>
          <!-- Dynamic Scroll-Induced Motion Smear -->
          <feGaussianBlur 
            in="SourceGraphic" 
            :stdDeviation="`${scrollBlur} 0`" 
            result="blurred" 
          />
          <!-- Apply soft, subtle deflection based on our animated diagonal coordinate shifts -->
          <feDisplacementMap 
            in="blurred" 
            in2="diagonalWarp" 
            :scale="crtScale" 
            xChannelSelector="R" 
            yChannelSelector="G" 
          />
        </filter>
      </defs>
    </svg>
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

const windowRef = ref(null)
const contentRef = ref(null)
const inputRowRef = ref(null)
const inputRef = ref(null)
const inputValue = ref('')
const isFocused = ref(false)

const instance = getCurrentInstance()

// ── Advanced Multi-Layer Glitch Engine (Pure Mask) ──
const activeGlitches = ref([])
const glitchTick = ref(0)
let engineTimerId = null

const GLITCH_CHARS = '!@#$%^&*()░▒▓█▄▀╔╗╚╝║═╬┼┤├┴└┘┐┌─│'

const crtScale = ref(3)
let crtDecayIntervalId = null

// ── Motion Blur & Scroll Smear Tracking ──
const scrollBlur = ref(0)
let lastScrollTop = 0
let scrollTimeoutId = null
let scrollDecayIntervalId = null

let resizeObserver = null
let isInitialized = false
let lastWidth = 0
let lastHeight = 0
let lastPixelRatio = typeof window !== 'undefined' ? window.devicePixelRatio : 1

function spawnGlitch(options = {}) {
  const now = Date.now()
  activeGlitches.value.push({
    id: Math.random().toString(36).substring(2, 9),
    lineIndex: options.lineIndex,
    startIndex: options.startIndex || 0,
    span: options.span || 10,
    intensity: options.intensity || 0.5,
    speed: options.speed || 60, 
    expiresAt: now + (options.duration || 500),
    lastTick: now,
    maskOffset: Math.floor(Math.random() * 1000)
  })
  glitchTick.value++
}

function triggerHardcoreScreenGlitch() {
  if (crtDecayIntervalId) clearInterval(crtDecayIntervalId)

  crtScale.value = 25 + Math.random() * 15

  const startTime = Date.now()
  const duration = 500

  crtDecayIntervalId = setInterval(() => {
    const elapsed = Date.now() - startTime
    if (elapsed >= duration) {
      crtScale.value = 3
      clearInterval(crtDecayIntervalId)
      crtDecayIntervalId = null
    } else {
      const progress = elapsed / duration
      crtScale.value = 3 + (crtScale.value - 3) * Math.pow(1 - progress, 2)
    }
  }, 16)

  const linesCount = props.terminal.lines.length
  if (linesCount === 0) return

  const startIdx = Math.max(0, linesCount - 40)
  for (let idx = startIdx; idx < linesCount; idx++) {
    const line = props.terminal.lines[idx]
    if (!line || line._typing || (!line.text && !line.segments)) continue

    const len = line.text ? line.text.length : line.segments.reduce((acc, s) => acc + s.text.length, 0)
    if (len === 0) continue

    const glitchLayers = Math.random() < 0.4 ? 2 : 1
    for (let layer = 0; layer < glitchLayers; layer++) {
      const span = Math.max(4, Math.floor(Math.random() * Math.min(len, 35)))
      const startIndex = Math.floor(Math.random() * Math.max(1, len - span))

      spawnGlitch({
        lineIndex: idx,
        startIndex: startIndex,
        span: span,
        intensity: 0.65 + Math.random() * 0.35,
        speed: 16 + Math.random() * 24,
        duration: 150 + Math.random() * 450
      })
    }
  }
}

function handleScroll() {
  if (!contentRef.value) return
  const currentScrollTop = contentRef.value.scrollTop
  const delta = Math.abs(currentScrollTop - lastScrollTop)

  if (scrollDecayIntervalId) {
    clearInterval(scrollDecayIntervalId)
    scrollDecayIntervalId = null
  }

  // Calculate motion deviation dynamically. Max bound of 8 avoids severe illegibility.
  scrollBlur.value = Math.min(delta * 0.18, 8)
  lastScrollTop = currentScrollTop

  if (scrollTimeoutId) clearTimeout(scrollTimeoutId)
  scrollTimeoutId = setTimeout(() => {
    decayScrollBlur()
  }, 30)
}

function decayScrollBlur() {
  const start = Date.now()
  const duration = 140
  const initialBlur = scrollBlur.value

  scrollDecayIntervalId = setInterval(() => {
    const elapsed = Date.now() - start
    if (elapsed >= duration) {
      scrollBlur.value = 0
      clearInterval(scrollDecayIntervalId)
      scrollDecayIntervalId = null
    } else {
      const progress = elapsed / duration
      scrollBlur.value = initialBlur * Math.pow(1 - progress, 2)
    }
  }, 16)
}

const displayedLines = computed(() => {
  const baseLines = props.terminal.lines
  const _tick = glitchTick.value
  const currentGlitches = activeGlitches.value

  if (currentGlitches.length === 0) return baseLines

  return baseLines.map((line, idx) => {
    const lineGlitches = currentGlitches.filter(g => g.lineIndex === idx)
    if (lineGlitches.length === 0 || line._typing) return line

    const applyMaskToChar = (char, absoluteIdx) => {
      if (char === ' ' || char === '\n' || char === '\r') return { char, isGlitched: false }
      
      let outputChar = char
      let isGlitched = false

      for (const g of lineGlitches) {
        if (absoluteIdx >= g.startIndex && absoluteIdx < g.startIndex + g.span) {
          const seed = absoluteIdx + g.maskOffset
          const rand1 = Math.abs(Math.sin(seed))
          const rand2 = Math.abs(Math.cos(seed))
          
          if (rand1 < g.intensity) {
            outputChar = GLITCH_CHARS[Math.floor(rand2 * GLITCH_CHARS.length)]
            isGlitched = true
            break
          }
        }
      }
      return { char: outputChar, isGlitched }
    }

    if (!line.segments && line.text) {
      let newText = ''
      let hasGlitch = false
      for (let i = 0; i < line.text.length; i++) {
        const res = applyMaskToChar(line.text[i], i)
        newText += res.char
        if (res.isGlitched) hasGlitch = true
      }
      if (!hasGlitch) return line
      return {
        ...line,
        text: newText,
        class: line.class ? `${line.class} term-enemy` : 'term-enemy'
      }
    }

    if (line.segments) {
      let currentOffset = 0
      let lineHasGlitch = false
      const alteredSegments = line.segments.map(seg => {
        let newText = ''
        let segHasGlitch = false
        for (let i = 0; i < seg.text.length; i++) {
          const res = applyMaskToChar(seg.text[i], currentOffset + i)
          newText += res.char
          if (res.isGlitched) segHasGlitch = true
        }
        currentOffset += seg.text.length
        if (segHasGlitch) lineHasGlitch = true
        
        return {
          ...seg,
          text: newText,
          class: segHasGlitch ? (seg.class ? `${seg.class} term-enemy` : 'term-enemy') : seg.class
        }
      })
      
      if (!lineHasGlitch) return line
      return {
        ...line,
        segments: alteredSegments
      }
    }

    return line
  })
})

function checkDpiZoom() {
  if (typeof window === 'undefined') return
  if (window.devicePixelRatio !== lastPixelRatio) {
    lastPixelRatio = window.devicePixelRatio
    triggerHardcoreScreenGlitch()
  }
}

function startInterferenceEngine() {
  let nextSpawnTime = Date.now() + 1500 + Math.random() * 4500

  engineTimerId = setInterval(() => {
    const now = Date.now()
    let changed = false
    
    const living = activeGlitches.value.filter(g => g.expiresAt > now)
    if (living.length !== activeGlitches.value.length) {
      activeGlitches.value = living
      changed = true
    }

    activeGlitches.value.forEach(g => {
      if (now - g.lastTick >= g.speed) {
        g.lastTick = now
        g.maskOffset = Math.floor(Math.random() * 1000)
        changed = true
      }
    })

    if (changed) {
      glitchTick.value++
    }

    if (now >= nextSpawnTime && props.terminal.lines.length > 0 && !props.terminal.busy) {
      const targetIdx = Math.floor(Math.random() * props.terminal.lines.length)
      const line = props.terminal.lines[targetIdx]
      
      if (line && !line._typing && (line.text || line.segments)) {
        const len = line.text ? line.text.length : line.segments.reduce((acc, s) => acc + s.text.length, 0)
        
        if (len > 0) {
          const span = 1 + Math.floor(Math.random() * Math.min(len, 40))
          const startIndex = Math.floor(Math.random() * (len - span + 1))
          
          spawnGlitch({
            lineIndex: targetIdx,
            startIndex: startIndex,
            span: span,
            intensity: 0.15 + Math.random() * 0.7,
            speed: 20 + Math.random() * 100,
            duration: 150 + Math.random() * 1200
          })
        }
      }
      nextSpawnTime = now + 1500 + Math.random() * 4500
    }
  }, 16)
}

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
  startInterferenceEngine()

  if (typeof window !== 'undefined') {
    window.addEventListener('resize', checkDpiZoom)
  }

  resizeObserver = new ResizeObserver((entries) => {
    for (const entry of entries) {
      const { width, height } = entry.contentRect
      if (!isInitialized) {
        lastWidth = width
        lastHeight = height
        isInitialized = true
        continue
      }
      if (Math.abs(width - lastWidth) > 3 || Math.abs(height - lastHeight) > 3) {
        lastWidth = width
        lastHeight = height
        triggerHardcoreScreenGlitch()
      }
    }
  })

  if (windowRef.value) {
    resizeObserver.observe(windowRef.value)
  }

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
  if (engineTimerId) clearInterval(engineTimerId)
  if (crtDecayIntervalId) clearInterval(crtDecayIntervalId)
  if (scrollDecayIntervalId) clearInterval(scrollDecayIntervalId)
  if (scrollTimeoutId) clearTimeout(scrollTimeoutId)
  if (resizeObserver) {
    resizeObserver.disconnect()
  }
  if (typeof window !== 'undefined') {
    window.removeEventListener('resize', checkDpiZoom)
  }
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
  font-size: 0.7875rem;
  line-height: 1.2698;
  color: var(--war-text, #d7e0e8);
}

.term-window::selection,
.term-window *::selection {
  background: rgba(182, 144, 91, 0.3);
  color: var(--war-brass-light, #d4ba8e);
  text-shadow: 0 0 8px rgba(212, 163, 89, 0.6);
}

/* ─── Screen Wrapper with Raster Distortion ─── */
.term-screen {
  position: relative;
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  overflow: hidden;
  filter: url('#crt-ripple');
  will-change: filter;
  transform: translateZ(0); /* Force GPU rasterization for smooth animation performance */
}

/* ─── Scanline Overlay ─── */
.term-scanlines {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 50;
  background: linear-gradient(rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.25) 50%), linear-gradient(90deg, rgba(255, 0, 0, 0.06), rgba(0, 255, 0, 0.02), rgba(0, 255, 0, 0.06));
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
  word-break: normal;
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
.term-line .term-word {
  display: inline-block;
  max-width: 100%;
  white-space: pre-wrap;
  vertical-align: top; 
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