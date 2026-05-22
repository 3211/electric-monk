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
  const location = ref('/.')
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

  /** Active interactive session (readLine/readKey promise resolvers) — MUST be reactive */
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

  /**
   * Write a line to the terminal buffer.
   * @param {string|object} input — plain string or { text, class, id }
   */
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

  /**
   * Write multiple lines at once.
   */
  function writeAll(inputArr) {
    for (const item of inputArr) {
      write(item)
    }
  }

  /**
   * Clear the terminal buffer.
   */
  function clear() {
    lines.length = 0
    emit('clear')
  }

  /**
   * Get a line by its ID.
   * @param {string} lineId
   * @returns {object|null}
   */
  function getLine(lineId) {
    return lines.find(l => l.id === lineId) || null
  }

  /**
   * Update a line by its ID. Creates the line if it doesn't exist.
   * @param {string} lineId
   * @param {string|object} content — plain string or { text, class }
   */
  function updateLine(lineId, content) {
    const existing = lines.findIndex(l => l.id === lineId)
    if (existing >= 0) {
      if (typeof content === 'string') {
        lines[existing].text = content
      } else {
        if (content.text !== undefined) lines[existing].text = content.text
        if (content.class !== undefined) lines[existing].class = content.class
      }
    } else {
      // Create new line with this ID
      if (typeof content === 'string') {
        lines.push({ text: content, class: '', id: lineId })
      } else {
        lines.push({
          text: content.text || '',
          class: content.class || '',
          id: lineId,
        })
      }
    }
    emit('lineUpdated', { id: lineId, line: lines[existing >= 0 ? existing : lines.length - 1] })
  }

  /**
   * Remove a line by its ID.
   * @param {string} lineId
   */
  function removeLine(lineId) {
    const idx = lines.findIndex(l => l.id === lineId)
    if (idx >= 0) {
      lines.splice(idx, 1)
      emit('lineRemoved', { id: lineId })
    }
  }

  /**
   * Typewriter effect — queues characters one by one.
   * @param {string} text — text to animate
   * @param {object} options — { speed: ms per char, class: css class, id }
   * @returns {Promise<void>}
   */
  function typewrite(text, options = {}) {
    const { speed = 28, class: cls = '', id: lineId = null } = options
    return new Promise((resolve) => {
      const lineIndex = lines.length
      lines.push({ text: '', class: cls, id: lineId, _typing: true })
      isTyping.value = true

      let charIndex = 0
      const interval = setInterval(() => {
        if (charIndex < text.length) {
          lines[lineIndex].text = text.slice(0, charIndex + 1)
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

  /**
   * Queue multiple typewriter sequences sequentially.
   * @param {(string|object)[]} entries
   */
  async function typewriteSequence(entries) {
    for (const entry of entries) {
      if (typeof entry === 'string') {
        await typewrite(entry)
      } else {
        await typewrite(entry.text, entry)
      }
    }
  }

  // ── Progress Bars ──

  function showProgress(progressId, percent, label, options = {}) {
    const bar = _buildProgressBar(percent, label)
    updateLine(progressId, { text: bar, class: options.class || 'term-steel' })
  }

  function removeProgress(progressId) {
    removeLine(progressId)
  }

  function _buildProgressBar(percent, label = '') {
    const width = 32
    const filled = Math.round((Math.min(100, Math.max(0, percent)) / 100) * width)
    const empty = width - filled
    const bar = '█'.repeat(filled) + '░'.repeat(empty)
    const pctStr = String(percent).padStart(3, ' ')
    return label ? `${label} [${bar}] ${pctStr}%` : `[${bar}] ${pctStr}%`
  }

  // ── Classic Windows-style Spinner ──

  const SPINNER_FRAMES = ['|', '/', '-', '\\']

  /**
   * Start a spinning animation on a line.
   * @param {string} spinnerId
   * @param {string} label — optional text before spinner
   * @param {object} options — { speed: ms per frame, class }
   * @returns {function} — call to stop the spinner
   */
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

  // ── Interactive Input (readLine / readKey) ──

  /**
   * Wait for the user to type a line and press Enter.
   * @param {string} promptText — optional prompt to display
   * @returns {Promise<string>}
   */
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

  /**
   * Wait for the user to press any key.
   * @param {string} message — optional message to display
   * @returns {Promise<string>} — the key pressed
   */
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
   * Check if an interactive session is active.
   */
  function hasActiveSession() {
    return activeSession.value !== null
  }

  /**
   * Canonical "get user input" entry point.
   * Emits focusRequest so the UI layer can scroll-to-bottom and
   * focus the textarea if this terminal was the last focused window.
   * Delegates to readLine for the actual prompt.
   *
   * @param {string} prompt - Prompt text to display
   * @returns {Promise<string>} - User input (trimmed)
   */
  async function getInput(prompt) {
    return (await readLine(prompt)).trim()
  }

  /**
   * End the current interactive session.
   */
  function endSession() {
    if (activeSession.value) {
      emit('sessionEnd', { type: activeSession.value.type })
      activeSession.value = null
    }
  }

  // ── Prompt ──

  /**
   * Generate the prompt string for the current location.
   * Format:  /root >
   */
  function getPrompt() {
    return `${location.value} >`
  }

  // ── Command Processing ──

  /**
   * Build the command registry for this terminal instance.
   * Must be called after creation but before the first user input.
   */
  function buildRegistry(ctx = {}) {
    context = {
      terminal: instance,
      tab: ctx.tab || null,
    }
    registry = buildCommandRegistry(context)
    return registry
  }

  /**
   * Print the welcome banner. Call after buildRegistry().
   */
  function startup() {
    writeAll([
      { text: '  Welcome to Holy War Online. Type /help for help.', class: 'term-brass' },
      { text: '', class: '' },
    ])
  }

  /**
   * Handle raw input from the user (called on Enter or keypress).
   * @param {string} input
   * @returns {boolean} — true if input was handled by a session, false if processed as command
   */
  function handleInput(input) {
    if (activeSession.value) {
      const session = activeSession.value
      activeSession.value = null

      if (session.type === 'readLine') {
        // Echo the input if there was a prompt
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

  /**
   * Process a raw command string from the input line.
   */
  async function processCommand(raw) {
    const trimmed = (raw || '').trim()

    // RE-ENTRY GUARD: if already processing a command (and not in an interactive
    // session), silently ignore. This prevents command queuing / double-execution.
    if (processingCommand.value && !activeSession.value) return

    // Check if an interactive session is active
    if (activeSession.value) {
      handleInput(trimmed)
      return
    }

    if (!trimmed) return

    // Block input while this command resolves
    processingCommand.value = true

    // Echo the command with prompt
    write({ text: `${getPrompt()} ${trimmed}`, class: 'term-prompt' })

    // Add to history
    history.push(trimmed)
    historyIndex.value = history.length

    emit('command', { command: trimmed })

    // Commands must start with /
    if (!trimmed.startsWith('/')) {
      write({
        text: `  ${trimmed} not recognized, type /help for help.`,
        class: 'term-enemy',
      })
      processingCommand.value = false
      return
    }

    // Parse: drop the leading /, split on whitespace
    const parts = trimmed.slice(1).split(/\s+/)
    const cmd = parts[0].toLowerCase()
    const args = parts.slice(1)

    // Lazy-fallback: build a default registry if none was injected
    if (!registry) {
      buildRegistry()
    }

    const handler = registry[cmd]
    
    // If the command exists BUT is flagged as hidden, treat it as non-existent
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

  // ── History Navigation ──

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

  // ── Lifecycle ──

  function unsubscribe() {
    // TODO: wire up Supabase channel unsubscriptions here
  }

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

    // Progress
    showProgress,
    removeProgress,
    startSpinner,

    // Interactive
    readLine,
    readKey,
    getInput,
    hasActiveSession,
    handleInput,

    // Prompt
    getPrompt,

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
