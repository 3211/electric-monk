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
      } else {
        if (content.text !== undefined) lines[existing].text = content.text
        if (content.class !== undefined) lines[existing].class = content.class
      }
    } else {
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
      
      if (key === 'ArrowUp') {
        session.selectedIndex = (session.selectedIndex - 1 + session.options.length) % session.options.length
        _renderMenu()
        return true
      } 
      else if (key === 'ArrowDown') {
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
    return `${location.value} >`
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
    startSpinner,

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