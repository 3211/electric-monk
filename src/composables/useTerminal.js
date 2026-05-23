import { ref, reactive } from 'vue'
import { buildCommandRegistry } from '@/terminal/index'

/**
 * Create a new terminal instance.
 *
 * Each terminal tab gets its own lines buffer, location, history, and
 * command registry. Tab-management commands (newtab, closethis, etc.)
 * receive callbacks injected via buildRegistry().
 *
 * @param {string} id — unique identifier (e.g. 'term-1')
 */
export function useTerminal(id = 'default') {
  // ── Reactive State ──
  const lines = reactive([])
  const location = ref('0.0.0.0')
  const history = reactive([])
  const historyIndex = ref(-1)
  const isTyping = ref(false)
  const processingCommand = ref(false)
  const busy = ref(false)
  const activeProgressBars = reactive({})

  /** Command registry built by buildRegistry(). Populated lazily. */
  let registry = null

  /** Context injected by buildRegistry(). Used by command handlers. */
  let context = null

  /** Active interactive session (readLine/readKey/readMenu promise resolvers) — MUST be reactive */
  const activeSession = ref(null)

  /** Event listeners registry */
  const eventListeners = reactive({})

  // ── Event Emitter ──

  function on(event, callback) {
    if (!eventListeners[event]) {
      eventListeners[event] = []
    }
    eventListeners[event].push(callback)
    return () => off(event, callback)
  }

  function off(event, callback) {
    if (!eventListeners[event]) return
    const idx = eventListeners[event].indexOf(callback)
    if (idx >= 0) eventListeners[event].splice(idx, 1)
  }

  function emit(event, payload) {
    if (!eventListeners[event]) return
    eventListeners[event].forEach(cb => cb(payload))
  }

  // ── Output Methods ──

  function write(input) {
    if (typeof input === 'string') {
      lines.push({ text: input, class: '', id: null })
    } else {
      lines.push({
        text: input.text || '',
        class: input.class || '',
        id: input.id || null,
      })
    }
    emit('lineAdded', lines[lines.length - 1])
  }

  function writeAll(inputArr) {
    for (const item of inputArr) {
      write(item)
    }
  }

  function clear() {
    // Tear down any active progress bar controllers so they don't ghost back
    for (const id of Object.keys(activeProgressBars)) {
      const bar = activeProgressBars[id]
      bar._destroy()
      delete activeProgressBars[id]
    }
    lines.length = 0
    emit('clear')
  }

  function getLine(lineId) {
    return lines.find(l => l.id === lineId) || null
  }

  function updateLine(lineId, content) {
    const existing = lines.findIndex(l => l.id === lineId)
    if (existing >= 0) {
      if (typeof content === 'string') {
        lines[existing].text = content
        lines[existing].segments = null
      } else {
        if (content.text !== undefined) lines[existing].text = content.text
        if (content.class !== undefined) lines[existing].class = content.class
        if (content.segments !== undefined) lines[existing].segments = content.segments
      }
    } else {
      if (typeof content === 'string') {
        lines.push({ text: content, class: '', id: lineId, segments: null })
      } else {
        lines.push({
          text: content.text || '',
          class: content.class || '',
          id: lineId,
          segments: content.segments || null
        })
      }
    }
    emit('lineUpdated', { id: lineId, line: lines[existing >= 0 ? existing : lines.length - 1] })
  }

  function highlightPattern(lineId, regex, className) {
    const line = getLine(lineId)
    if (!line || !line.text) return

    const matches = [...line.text.matchAll(regex)]
    if (matches.length === 0) return

    let segments = []
    let lastIndex = 0

    for (const match of matches) {
      if (match.index > lastIndex) {
        segments.push({ text: line.text.substring(lastIndex, match.index), class: '' })
      }
      segments.push({ text: match[0], class: className })
      lastIndex = match.index + match[0].length
    }

    if (lastIndex < line.text.length) {
      segments.push({ text: line.text.substring(lastIndex), class: '' })
    }

    updateLine(lineId, { text: line.text, class: line.class, segments })
  }

  function removeLine(lineId) {
    const idx = lines.findIndex(l => l.id === lineId)
    if (idx >= 0) {
      lines.splice(idx, 1)
      emit('lineRemoved', { id: lineId })
    }
  }

  function typewrite(text, options = {}) {
    const { speed = 28, class: cls = '', id: lineId = null } = options
    return new Promise((resolve) => {
      const lineIndex = lines.length
      lines.push({ text: '', class: cls, id: lineId, _typing: true })
      isTyping.value = true

      // This keeps emoji surrogate pairs intact!
      const chars = Array.from(text)
      let charIndex = 0
      const interval = setInterval(() => {
        if (charIndex < chars.length) {
          lines[lineIndex].text = chars.slice(0, charIndex + 1).join('')
          charIndex++
        } else {
          clearInterval(interval)
          lines[lineIndex]._typing = false
          isTyping.value = false
          resolve()
        }
      }, speed)
    })
  }

  async function typewriteSequence(entries) {
    for (const entry of entries) {
      if (typeof entry === 'string') {
        await typewrite(entry)
      } else {
        await typewrite(entry.text, entry)
      }
    }
  }

  // ── Progress Bars & Spinners ──

  /**
   * Build a progress bar string from a template.
   *
   * @param {number} percent — 0–100
   * @param {object} [options]
   * @param {number} [options.width=32]    — character width of the bar
   * @param {string} [options.label='']    — prefix label
   * @param {string} [options.format='{label} [{bar}] {percent}%'] — template with {label}, {bar}, {percent}
   * @param {object} [options.chars]       — { filled: '█', empty: '░' }
   * @returns {string}
   */
  function _buildProgressBar(percent, options = {}) {
    const {
      width = 32,
      label = '',
      format = '{label} [{bar}] {percent}%',
      chars = { filled: '█', empty: '░' },
    } = options

    const p = Math.min(100, Math.max(0, percent))
    const filledLen = Math.round((p / 100) * width)
    const bar = chars.filled.repeat(filledLen) + chars.empty.repeat(width - filledLen)

    return format
      .replace('{label}', label)
      .replace('{bar}', bar)
      .replace('{percent}', String(p).padStart(3, ' '))
  }

  /**
   * Quick-fire progress bar — update a single line by ID.
   * Backward-compatible with the old 3-arg signature.
   *
   * @param {string} progressId — unique line ID
   * @param {number} percent    — 0–100
   * @param {string} [label]   — prefix text (legacy arg)
   * @param {object} [options] — { class, width, format, chars, label }
   */
  function showProgress(progressId, percent, label, options = {}) {
    // Merge legacy `label` string into options when both exist
    const merged = { ...options }
    if (label && typeof label === 'string') merged.label = label
    const text = _buildProgressBar(percent, merged)
    updateLine(progressId, { text, class: merged.class || 'term-steel' })
  }

  /**
   * Remove a progress bar line by ID.
   * Also cleans up any tracked controller.
   */
  function removeProgress(progressId) {
    if (activeProgressBars[progressId]) {
      activeProgressBars[progressId]._destroy()
      delete activeProgressBars[progressId]
    }
    removeLine(progressId)
  }

  /**
   * Create a stateful progress bar controller.
   *
   * Returns an object that owns its terminal line and provides
   * update(), finish(), and remove() methods. The controller
   * is zombie-proof: if the line is cleared from the terminal
   * buffer, further updates become no-ops.
   *
   * @param {string} id — unique line ID
   * @param {object} [initialOptions]
   * @param {number} [initialOptions.width=32]
   * @param {string} [initialOptions.label='']
   * @param {string} [initialOptions.format='  [{bar}] {percent}%']
   * @param {object} [initialOptions.chars={ filled: '█', empty: '░' }]
   * @param {string} [initialOptions.class='term-steel']
   * @returns {{ update, finish, remove, id }}
   */
  function createProgressBar(id, initialOptions = {}) {
    const defaults = {
      width: 32,
      label: '',
      format: '  [{bar}] {percent}%',
      chars: { filled: '█', empty: '░' },
      class: 'term-steel',
    }

    let state = {
      percent: 0,
      options: { ...defaults, ...initialOptions },
    }

    let alive = true
    let born = false  // Tracks whether the line has been created at least once

    /** Internal: write current state to the terminal line. No-op if zombie. */
    const render = () => {
      if (!alive) return
      // Only check for zombie lines AFTER the first successful render.
      // On the first call the line doesn't exist yet — updateLine will create it.
      if (born && !getLine(id)) {
        // Line was cleared externally — mark as dead so we stop ghosting
        alive = false
        delete activeProgressBars[id]
        return
      }
      const text = _buildProgressBar(state.percent, state.options)
      updateLine(id, { text, class: state.options.class })
      born = true
    }

    const controller = {
      id,

      /**
       * Update the progress bar.
       *
       * @param {number|null} percent — 0–100, or null to keep current
       * @param {object} [newOptions] — override any option (class, label, format, width, chars)
       */
      update(percent, newOptions = {}) {
        if (!alive) return
        if (percent !== null && percent !== undefined) {
          state.percent = Math.min(100, Math.max(0, percent))
        }
        state.options = { ...state.options, ...newOptions }
        render()
      },

      /**
       * Jump to 100% and apply success styling.
       *
       * @param {object} [finalOptions] — override class etc. for the completed bar
       */
      finish(finalOptions = {}) {
        if (!alive) return
        state.percent = 100
        state.options = { ...state.options, class: 'term-ally', ...finalOptions }
        render()
      },

      /**
       * Remove the progress bar line from the terminal entirely.
       */
      remove() {
        if (!alive) return
        alive = false
        delete activeProgressBars[id]
        removeLine(id)
      },

      /** @private Internal cleanup — called by clear() or removeProgress(). */
      _destroy() {
        alive = false
      },
    }

    // Register so clear() can tear us down
    activeProgressBars[id] = controller

    // Render the initial empty bar
    render()

    return controller
  }

  const SPINNER_FRAMES = ['|', '/', '-', '\\']

  function startSpinner(spinnerId, label = '', options = {}) {
    const { speed = 80, class: cls = 'term-steel' } = options
    let frameIndex = 0

    const render = () => {
      const frame = SPINNER_FRAMES[frameIndex]
      const text = label ? `${label} ${frame}` : frame
      updateLine(spinnerId, { text, class: cls })
      frameIndex = (frameIndex + 1) % SPINNER_FRAMES.length
    }

    render()
    const intervalId = setInterval(render, speed)

    return () => {
      clearInterval(intervalId)
      removeLine(spinnerId)
    }
  }

  // ── Text Animation ──

  /**
   * Default glitching function. Randomly replaces characters with noise symbols.
   * Spaces are always preserved.
   *
   * @param {string} text — the pure text to corrupt
   * @param {number} [intensity=0.2] — probability each char gets glitched (0–1)
   * @returns {string} glitched text
   */
  function _glitchText(text, intensity = 0.2) {
    const glitchChars = '!@#$%^&*()░▒▓█▄▀╔╗╚╝║═╬┼┤├┴└┘┐┌─│'
    // This keeps emoji surrogate pairs intact!
    return Array.from(text).map(char => {
      if (char === ' ') return ' '
      if (Math.random() < intensity) {
        return glitchChars[Math.floor(Math.random() * glitchChars.length)]
      }
      return char
    }).join('')
  }

  /**
   * Animate a line from a glitched/corrupted state back to pure text.
   *
   * Displays the text as heavily corrupted, then progressively de-corrupts
   * it over multiple steps until it matches the original. Useful for
   * "data purification" or "decryption" visual effects.
   *
   * @param {string} lineId — unique line ID to animate
   * @param {string} pureText — the final, clean text to reveal
   * @param {object} [options]
   * @param {string} [options.glitchPrefix='']   — prefix shown during corruption (e.g. '  [ERR]  ')
   * @param {string} [options.purePrefix='']      — prefix shown once purified  (e.g. '  [OK]   ')
   * @param {string} [options.glitchClass='term-enemy'] — CSS class during corruption
   * @param {string} [options.pureClass='term-ally']    — CSS class once purified
   * @param {number} [options.intensity=0.75]    — initial corruption intensity (0–1)
   * @param {number} [options.steps=6]           — number of recovery steps
   * @param {number} [options.stepDelay=150]      — ms between recovery steps
   * @param {number} [options.fixChance=0.4]     — probability per corrupted char to fix per step
   * @param {Function} [options.glitchFn]        — custom glitch function (text, intensity) => string
   * @returns {Promise<void>} resolves when animation completes
   */
  async function purifyLine(lineId, pureText, options = {}) {
    const {
      glitchPrefix = '',
      purePrefix = '',
      glitchClass = 'term-enemy',
      pureClass = 'term-ally',
      intensity = 0.75,
      steps = 12,
      stepDelay = 60,
      fixChance = 0.35,
      glitchFn = _glitchText,
      highlightRegex = null,
      highlightClass = 'term-brass'
    } = options

    // Start fully corrupted
    let currentText = glitchFn(pureText, intensity)
    updateLine(lineId, { text: `${glitchPrefix}${currentText}`, class: glitchClass })

    // This keeps emoji surrogate pairs intact!
    const pureChars = Array.from(pureText)

    // Progressive recovery
    for (let step = 0; step < steps; step++) {
      await new Promise(r => setTimeout(r, stepDelay))
      const currentChars = Array.from(currentText)
      let nextText = ''
      for (let c = 0; c < pureChars.length; c++) {
        if (currentChars[c] !== pureChars[c] && (Math.random() < fixChance || step === steps - 1)) {
          nextText += pureChars[c]
        } else if (currentChars[c] !== pureChars[c] && Math.random() < 0.3) {
          nextText += glitchFn(pureChars[c], 1) // scramble glitch chars mid-flight
        } else {
          nextText += currentChars[c] || ''
        }
      }
      currentText = nextText
      updateLine(lineId, { text: `${glitchPrefix}${currentText}`, class: glitchClass })
    }

    // Final pure state
    updateLine(lineId, { text: `${purePrefix}${pureText}`, class: pureClass })
    
    if (highlightRegex) {
      highlightPattern(lineId, highlightRegex, highlightClass)
    }
  }

  // ── Interactive Input (readLine / readKey / readMenu) ──

  function readLine(promptText = '') {
    return new Promise((resolve) => {
      emit('focusRequest')
      activeSession.value = {
        type: 'readLine',
        prompt: promptText,
        resolve,
      }
      if (promptText) {
        write({ text: promptText, class: 'term-prompt' })
      }
      emit('sessionStart', { type: 'readLine' })
    })
  }

  function readKey(message = '') {
    return new Promise((resolve) => {
      emit('focusRequest')
      activeSession.value = {
        type: 'readKey',
        message,
        resolve,
      }
      if (message) {
        write({ text: message, class: 'term-dim' })
      }
      emit('sessionStart', { type: 'readKey' })
    })
  }

  /**
   * Triggers an interactive blocking menu block.
   * @param {string} promptText - The title above the menu
   * @param {Array<string|object>} options - Array of strings or { label, value } objects
   * @returns {Promise<string|any>}
   */
  function readMenu(promptText = '', options = []) {
    return new Promise((resolve) => {
      emit('focusRequest')
      if (promptText) {
        write({ text: promptText, class: 'term-prompt' })
      }

      // Generate stable line IDs for each menu option
      const lineIds = options.map((_, i) => `menu-opt-${Date.now()}-${i}`)

      activeSession.value = {
        type: 'readMenu',
        options,
        selectedIndex: 0,
        lineIds,
        resolve,
      }

      _renderMenu()
      emit('sessionStart', { type: 'readMenu' })
    })
  }

  /** Internally rewrites the menu lines based on selectedIndex */
  function _renderMenu() {
    const session = activeSession.value
    if (!session || session.type !== 'readMenu') return

    session.options.forEach((opt, idx) => {
      const isSelected = idx === session.selectedIndex
      const label = typeof opt === 'string' ? opt : opt.label
      
      const prefix = isSelected ? '  > ' : '    '
      const cls = isSelected ? 'term-ally' : 'term-dim'

      updateLine(session.lineIds[idx], {
        text: `${prefix}${label}`,
        class: cls
      })
    })
  }

  /**
   * Catches intercepted menu key presses from the UI window
   */
  function handleInteractiveKey(key) {
    if (!activeSession.value) return false

    if (activeSession.value.type === 'readMenu') {
      const session = activeSession.value
      
      const upKeys = ['ArrowUp', 'w', 'a', 'i', 'j', '8', '4', ',', '<', '+']
      const downKeys = ['ArrowDown', 's', 'd', 'k', 'l', '2', '6', '.', '>', '-']
      
      if (upKeys.includes(key)) {
        session.selectedIndex = (session.selectedIndex - 1 + session.options.length) % session.options.length
        _renderMenu()
        return true
      }
      else if (downKeys.includes(key)) {
        session.selectedIndex = (session.selectedIndex + 1) % session.options.length
        _renderMenu()
        return true
      }
      else if (key === 'Enter') {
        const selected = session.options[session.selectedIndex]
        const result = typeof selected === 'string' ? selected : selected.value
        
        // Clean up the interactive menu block to save vertical space
        session.lineIds.forEach(id => removeLine(id))
        
        // Output the final selection statically so it remains in history
        const label = typeof selected === 'string' ? selected : (selected.label || selected.value)
        write({ text: `  > Selected: ${label}`, class: 'term-ally' })

        session.resolve(result)
        activeSession.value = null
        emit('sessionEnd', { type: 'readMenu' })
        return true
      }
    }
    return false
  }

  function hasActiveSession() {
    return activeSession.value !== null
  }

  async function getInput(prompt) {
    return (await readLine(prompt)).trim()
  }

  function endSession() {
    if (activeSession.value) {
      emit('sessionEnd', { type: activeSession.value.type })
      activeSession.value = null
    }
  }

  function getPrompt() {
    return `/${location.value}>`
  }

  function setLocation(newLocation) {
    location.value = newLocation
  }

  // ── Command Processing ──

  function buildRegistry(ctx = {}) {
    context = {
      terminal: instance,
      tab: ctx.tab || null,
    }
    registry = buildCommandRegistry(context)
    return registry
  }

  function startup() {
    writeAll([
      { text: '  Welcome to Holy War Online. Type /help for help.', class: 'term-brass' },
      { text: '', class: '' },
    ])
  }

  function handleInput(input) {
    if (activeSession.value) {
      const session = activeSession.value
      activeSession.value = null

      if (session.type === 'readLine') {
        if (session.prompt) {
          write({ text: input, class: 'term-text' })
        }
        session.resolve(input)
        emit('sessionEnd', { type: 'readLine' })
      } else if (session.type === 'readKey') {
        const key = input.charAt(0) || ''
        session.resolve(key)
        emit('sessionEnd', { type: 'readKey' })
      }
      return true
    }
    return false
  }

  async function processCommand(raw) {
    const trimmed = (raw || '').trim()

    if (processingCommand.value && !activeSession.value) return
    if (activeSession.value) {
      handleInput(trimmed)
      return
    }

    if (!trimmed) return

    processingCommand.value = true
    write({ text: `${getPrompt()} ${trimmed}`, class: 'term-prompt' })
    history.push(trimmed)
    historyIndex.value = history.length
    emit('command', { command: trimmed })

    if (!trimmed.startsWith('/')) {
      write({
        text: `  ${trimmed} not recognized, type /help for help.`,
        class: 'term-enemy',
      })
      processingCommand.value = false
      return
    }

    const parts = trimmed.slice(1).split(/\s+/)
    const cmd = parts[0].toLowerCase()
    const args = parts.slice(1)

    if (!registry) buildRegistry()
    const handler = registry[cmd]
    
    if (handler && !handler.hidden) {
      try {
        const result = await handler.handler(args, context)
        if (result && result.length) {
          writeAll(result)
        }
      } catch (err) {
        write({ text: `  Error: ${err.message}`, class: 'term-enemy' })
      }
    } else {
      write({
        text: `  /${cmd} not recognized, type /help for help.`,
        class: 'term-enemy',
      })
    }

    processingCommand.value = false
  }

  function navigateHistory(direction) {
    if (direction === 'up') {
      if (historyIndex.value > 0) {
        historyIndex.value--
        return history[historyIndex.value]
      }
    } else {
      if (historyIndex.value < history.length - 1) {
        historyIndex.value++
        return history[historyIndex.value]
      } else {
        historyIndex.value = history.length
        return ''
      }
    }
    return null
  }

  function unsubscribe() {}

  // ── Public API ──

  const instance = {
    id,
    lines,
    location,
    history,
    historyIndex,
    isTyping,
    processingCommand,
    busy,
    activeProgressBars,
    activeSession, // Exposed for Vue template reactivity 

    // Output
    write,
    writeAll,
    clear,
    typewrite,
    typewriteSequence,

    // Line manipulation
    getLine,
    updateLine,
    removeLine,

    // Progress & Spinners
    showProgress,
    removeProgress,
    createProgressBar,
    startSpinner,
    purifyLine,
    highlightPattern,

    // Interactive
    readLine,
    readKey,
    readMenu,
    handleInteractiveKey,
    getInput,
    hasActiveSession,
    handleInput,

    // Prompt
    getPrompt,
    setLocation,

    // Commands
    buildRegistry,
    startup,
    processCommand,

    // History
    navigateHistory,

    // Events
    on,
    off,
    emit,

    // Lifecycle
    unsubscribe,
  }

  return instance
}