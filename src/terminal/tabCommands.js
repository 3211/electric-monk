/**
 * Tab management commands — operate on the terminal docking layout.
 *
 * These commands require tab context to be injected by TerminalDock.vue.
 * If context is missing (e.g. standalone terminal), they return an error message.
 *
 * ctx.tab shape:
 *   { paneId, tabId, newTab(), closeThis(), closeOthers(), closeAll() }
 */
export function buildTabCommands() {
  return {
    newtab: {
      help: 'Open a new terminal tab in the current pane.',
      handler(_args, ctx) {
        if (!ctx.tab || typeof ctx.tab.newTab !== 'function') {
          return [
            {
              text: '  /newtab: unavailable — no docking context.',
              class: 'term-enemy',
            },
          ]
        }
        ctx.tab.newTab()
        return null
      },
    },

    closethis: {
      help: 'Close the current terminal tab.',
      handler(_args, ctx) {
        if (!ctx.tab || typeof ctx.tab.closeThis !== 'function') {
          return [
            {
              text: '  /closethis: unavailable — no docking context.',
              class: 'term-enemy',
            },
          ]
        }
        ctx.tab.closeThis()
        return null
      },
    },

    closeothers: {
      help: 'Close every other tab in the current pane, keeping only this one.',
      handler(_args, ctx) {
        if (!ctx.tab || typeof ctx.tab.closeOthers !== 'function') {
          return [
            {
              text: '  /closeothers: unavailable — no docking context.',
              class: 'term-enemy',
            },
          ]
        }
        ctx.tab.closeOthers()
        return null
      },
    },

    closeall: {
      help: 'Close every terminal tab across all panes. A single fresh console will remain.',
      handler(_args, ctx) {
        if (!ctx.tab || typeof ctx.tab.closeAll !== 'function') {
          return [
            {
              text: '  /closeall: unavailable — no docking context.',
              class: 'term-enemy',
            },
          ]
        }
        ctx.tab.closeAll()
        return null
      },
    },
  }
}