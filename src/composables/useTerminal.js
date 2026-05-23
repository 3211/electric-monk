import { ref, reactive } from 'vue'
import { buildCommandRegistry } from '@/terminal/index'

/**
 * Parses markdown inline formats (**bold**, *italic*, `code`, and ### headers)
 * into a structured segment array for rendering. Returns null if no markdown exists.
 */
function parseMarkdownToSegments(rawText) {
  if (typeof rawText !== 'string') return null

  const headerMatch = rawText.match(/^(#{1,6})\s+(.*)$/)
  let baseText = rawText
  let isHeader = false
  if (headerMatch) {
    baseText = headerMatch[2]
    isHeader = true
  }

  const tokenRegex = /(\*\*.*?\*\*|\*.*?\*|`.*?`)/g
  const parts = baseText.split(tokenRegex)

  if (parts.length === 1 && !isHeader) {
    return null
  }

  const segments = []
  const headerClass = isHeader ? 'term-brass' : ''

  for (const part of parts) {
    if (!part) continue

    if (part.startsWith('**') && part.endsWith('**')) {
      segments.push({
        text: part.slice(2, -2),
        class: [headerClass, 'term-brass', 'term-bold'].filter(Boolean).join(' ')
      })
    } else if (part.startsWith('*') && part.endsWith('*')) {
      segments.push({
        text: part.slice(1, -1),
        class: [headerClass, 'term-dim', 'term-italic'].filter(Boolean).join(' ')
      })
    } else if (part.startsWith('`') && part.endsWith('`')) {
      segments.push({
        text: part.slice(1, -1),
        class: [headerClass, 'term-steel', 'term-code'].filter(Boolean).join(' ')
      })
    } else {
      segments.push({
        text: part,
        class: headerClass || ''
      })
    }
  }

  return segments
}

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
    let lineObj = { text: '', class: '', id: null, segments: null }

    if (typeof input === 'string') {
      lineObj.text = input
      lineObj.segments = parseMarkdownToSegments(input)
    } else {
      lineObj.text = input.text || ''
      lineObj.class = input.class || ''
      lineObj.id = input.id || null
      if (input.segments) {
        lineObj.segments = input.segments
      } else if (input.text) {
        lineObj.segments = parseMarkdownToSegments(input.text)
      }
    }

    lines.push(lineObj)
    emit('lineAdded', lines[lines.length - 1])
  }

  function writeAll(inputArr) {
    for (const item of inputArr) {
      write(item)
    }
  }

  function clear() {
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
        lines[existing].segments = parseMarkdownToSegments(content)
      } else {
        if (content.text !== undefined) {
          lines[existing].text = content.text
          if (content.segments === undefined) {
            lines[existing].segments = parseMarkdownToSegments(content.text)
          }
        }
        if (content.class !== undefined) lines[existing].class = content.class
        if (content.segments !== undefined) lines[existing].segments = content.segments
      }
    } else {
      if (typeof content === 'string') {
        lines.push({
          text: content,
          class: '',
          id: lineId,
          segments: parseMarkdownToSegments(content)
        })
      } else {
        let segments = content.segments || null
        if (!segments && content.text) {
          segments = parseMarkdownToSegments(content.text)
        }
        lines.push({
          text: content.text || '',
          class: content.class || '',
          id: lineId,
          segments
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
      lines.push({ text: '', class: cls, id: lineId, _typing: true, segments: null })
      isTyping.value = true

      const chars = Array.from(text)
      let charIndex = 0
      const interval = setInterval(() => {
        if (charIndex < chars.length) {
          const currentSlice = chars.slice(0, charIndex + 1).join('')
          lines[lineIndex].text = currentSlice
          lines[lineIndex].segments = parseMarkdownToSegments(currentSlice)
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

  function showProgress(progressId, percent, label, options = {}) {
    const merged = { ...options }
    if (label && typeof label === 'string') merged.label = label
    const text = _buildProgressBar(percent, merged)
    updateLine(progressId, { text, class: merged.class || 'term-steel' })
  }

  function removeProgress(progressId) {
    if (activeProgressBars[progressId]) {
      activeProgressBars[progressId]._destroy()
      delete activeProgressBars[progressId]
    }
    removeLine(progressId)
  }

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
    let born = false

    const render = () => {
      if (!alive) return
      if (born && !getLine(id)) {
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
      update(percent, newOptions = {}) {
        if (!alive) return
        if (percent !== null && percent !== undefined) {
          state.percent = Math.min(100, Math.max(0, percent))
        }
        state.options = { ...state.options, ...newOptions }
        render()
      },
      finish(finalOptions = {}) {
        if (!alive) return
        state.percent = 100
        state.options = { ...state.options, class: 'term-ally', ...finalOptions }
        render()
      },
      remove() {
        if (!alive) return
        alive = false
        delete activeProgressBars[id]
        removeLine(id)
      },
      _destroy() {
        alive = false
      },
    }

    activeProgressBars[id] = controller
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

  function _glitchText(text, intensity = 0.2) {
    const glitchChars = '!@#$%^&*()░▒▓█▄▀╔╗╚╝║═╬┼┤├┴└┘┐┌─│'
    return Array.from(text).map(char => {
      if (char === ' ') return ' '
      if (Math.random() < intensity) {
        return glitchChars[Math.floor(Math.random() * glitchChars.length)]
      }
      return char
    }).join('')
  }

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

    let currentText = glitchFn(pureText, intensity)
    updateLine(lineId, { text: `${glitchPrefix}${currentText}`, class: glitchClass })

    const pureChars = Array.from(pureText)

    for (let step = 0; step < steps; step++) {
      await new Promise(r => setTimeout(r, stepDelay))
      const currentChars = Array.from(currentText)
      let nextText = ''
      for (let c = 0; c < pureChars.length; c++) {
        if (currentChars[c] !== pureChars[c] && (Math.random() < fixChance || step === steps - 1)) {
          nextText += pureChars[c]
        } else if (currentChars[c] !== pureChars[c] && Math.random() < 0.3) {
          nextText += glitchFn(pureChars[c], 1)
        } else {
          nextText += currentChars[c] || ''
        }
      }
      currentText = nextText
      updateLine(lineId, { text: `${glitchPrefix}${currentText}`, class: glitchClass })
    }

    updateLine(lineId, { text: `${purePrefix}${pureText}`, class: pureClass })
    
    if (highlightRegex) {
      highlightPattern(lineId, highlightRegex, highlightClass)
    }
  }

  // ── Interactive Input ──

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

  function readMenu(promptText = '', options = []) {
    return new Promise((resolve) => {
      emit('focusRequest')
      if (promptText) {
        write({ text: promptText, class: 'term-prompt' })
      }

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
        
        session.lineIds.forEach(id => removeLine(id))
        
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
    activeSession,

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