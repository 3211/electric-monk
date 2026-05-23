<template>
  <div class="term-dock">
    <!-- Mobile: single terminal only -->
    <div v-if="isMobile" class="term-dock-mobile">
      <div class="term-dock-mobile-header">
        <span class="term-dock-mobile-title">⌁ Terminal</span>
      </div>
      <div class="term-dock-mobile-body">
        <TerminalWindow :terminal="getActiveTerminal()" />
      </div>
    </div>

    <!-- Desktop: full docking layout -->
    <div v-else class="term-dock-desktop" @contextmenu.prevent>
      <DockNode
        :node="layout"
        :terminals="terminals"
        :active-ids="activeIds"
        :onboarding-complete="onboardingComplete"
        @split="handleSplit"
        @close-tab="handleCloseTab"
        @activate-tab="handleActivateTab"
        @new-tab="handleNewTab"
      />
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, onBeforeUnmount, watch } from 'vue'
import { useTerminal } from '@/composables/useTerminal'
import { useAuth } from '@/composables/useAuth'
import { usePlayerState } from '@/composables/usePlayerState'
import { supabase } from '@/lib/supabase'
import { runBootSequence, checkOnboardingStatus } from '@/terminal/boot'
import { runOnboarding } from '@/terminal/onboarding'
import TerminalWindow from './TerminalWindow.vue'
import DockNode from './DockNode.vue'

// ─── Mobile Detection ───
const isMobile = ref(false)

function checkMobile() {
  isMobile.value = window.innerWidth < 768
}

// ─── Auth State ───
const auth = useAuth()
let bootSequenceRun = false
const onboardingComplete = ref(false) // hidden tab bar until onboarding done

onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  
  // Watch for authentication state changes and trigger boot/onboarding
  watch(
    () => auth.isAuthenticated,
    async (isAuthenticated) => {
      if (isAuthenticated && !bootSequenceRun) {
        bootSequenceRun = true

        // Flush any stale player state from a previous session
        const playerState = usePlayerState()
        playerState.flush()
        
        // Small delay to ensure terminal is ready
        await new Promise(resolve => setTimeout(resolve, 500))
        
        // Get the active terminal
        const terminal = getActiveTerminal()
        if (!terminal) return
        
        // Run the boot sequence
        terminal.clear()
        await runBootSequence(terminal, 3500)
        
        // Check onboarding status
        const { needsOnboarding, player, error } = await checkOnboardingStatus(supabase)
        
        // Hydrate global player state from DB
        if (player) {
          playerState.hydrate(player)
        }
        
        if (needsOnboarding && player) {
          // Run interactive onboarding flow
          await runOnboarding(terminal, player)
          onboardingComplete.value = true
        } else {
          // Already onboarded — show standard greeting
          onboardingComplete.value = true
          terminal.writeAll([
            { text: '', class: '' },
            { text: '  Welcome to Holy War Online. Type /help for help.', class: 'term-brass' },
            { text: '', class: '' },
          ])
        }
      }
    },
    { immediate: true }
  )
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', checkMobile)
})

// ─── Counters ───
let terminalCounter = 0
let paneCounter = 0
let tabCounter = 0

function newPaneId() { return `pane-${++paneCounter}` }
function newTabId() { return `tab-${++tabCounter}` }
function newTermId() { return `term-${++terminalCounter}` }

// ─── Terminal Instances ───
const terminals = reactive(new Map())
const activeTerminalId = ref('')

function createTerminal() {
  const id = newTermId()
  const term = useTerminal(id)
  terminals.set(id, term)
  return { id, term }
}

/**
 * Wire a terminal instance into the docking layout so it can respond
 * to tab-management commands (/newtab, /closethis, /closeothers, /closeall).
 */
function _injectTabContext(term, paneId, tabId) {
  term.buildRegistry({
    tab: {
      paneId,
      tabId,
      newTab: (initialCommand) => handleNewTab({ paneId, initialCommand }),
      closeThis: () => handleCloseTab({ paneId, tabId }),
      closeOthers: () => {
        const pane = findPane(layout, paneId)
        if (!pane) return
        const toClose = pane.tabs.filter((t) => t.id !== tabId)
        for (const t of toClose) {
          handleCloseTab({ paneId, tabId: t.id })
        }
      },
      closeAll: () => {
        // Collect all panes and close every tab
        const allPanes = []
        ;(function collect(node) {
          if (node.type === 'pane') allPanes.push(node)
          else if (node.children) node.children.forEach(collect)
        })(layout)
        for (const p of allPanes) {
          const tabs = [...p.tabs]
          for (const t of tabs) {
            handleCloseTab({ paneId: p.id, tabId: t.id })
          }
        }
      },
    },
  })
  term.startup()
}

function getActiveTerminal() {
  return terminals.get(activeTerminalId.value) || terminals.values().next().value
}

// ─── Layout Tree ───
const firstTerm = createTerminal()
const firstTabId = newTabId()
const firstPaneId = newPaneId()

activeTerminalId.value = firstTerm.id

// Wire the initial terminal so tab commands work
_injectTabContext(firstTerm.term, firstPaneId, firstTabId)

const layout = reactive({
  type: 'pane',
  id: firstPaneId,
  tabs: [
    { id: firstTabId, title: 'Terminal 1', terminalId: firstTerm.id },
  ],
  direction: null,
  children: null,
  size: 100,
})

// Track active tab per pane
const activeIds = reactive(new Map())
activeIds.set(firstPaneId, firstTabId)

// ─── Handlers ───

function handleActivateTab({ paneId, tabId }) {
  activeIds.set(paneId, tabId)
  const pane = findPane(layout, paneId)
  if (pane) {
    const tab = pane.tabs.find(t => t.id === tabId)
    if (tab) activeTerminalId.value = tab.terminalId
  }
}

function handleNewTab({ paneId }) {
  const pane = findPane(layout, paneId)
  if (!pane) return

  const { id: termId, term } = createTerminal()
  const tabId = newTabId()
  const tabNum = pane.tabs.length + 1
  pane.tabs.push({ id: tabId, title: `Terminal ${tabNum}`, terminalId: termId })
  activeIds.set(paneId, tabId)
  activeTerminalId.value = termId
  _injectTabContext(term, paneId, tabId)
  if (initialCommand) {
    // A tiny timeout ensures the DOM has rendered the new tab first
    setTimeout(() => {
      term.processCommand(initialCommand)
    }, 50)
  }
}

function handleCloseTab({ paneId, tabId }) {
  const pane = findPane(layout, paneId)
  if (!pane) return

  const idx = pane.tabs.findIndex(t => t.id === tabId)
  if (idx < 0) return

  const tab = pane.tabs[idx]
  const term = terminals.get(tab.terminalId)
  if (term) {
    term.unsubscribe()
    terminals.delete(tab.terminalId)
  }
  pane.tabs.splice(idx, 1)

  if (pane.tabs.length === 0) {
    removeEmptyPane(layout, paneId)
  } else {
    const newIdx = Math.min(idx, pane.tabs.length - 1)
    activeIds.set(paneId, pane.tabs[newIdx].id)
    activeTerminalId.value = pane.tabs[newIdx].terminalId
  }
}

function handleSplit({ paneId, direction }) {
  const pane = findPane(layout, paneId)
  if (!pane) return

  const { id: termId, term } = createTerminal()
  const newTabId_ = newTabId()
  const newPaneId_ = newPaneId()

  const newPane = {
    type: 'pane',
    id: newPaneId_,
    tabs: [{ id: newTabId_, title: 'Terminal', terminalId: termId }],
    direction: null,
    children: null,
    size: 50,
  }

  _injectTabContext(term, newPaneId_, newTabId_)
  activeIds.set(newPaneId_, newTabId_)
  activeTerminalId.value = termId

  const parent = findParentOfPane(layout, paneId)

  if (parent && parent.type === 'split' && parent.direction === direction) {
    // Same direction — add sibling
    const currentIdx = parent.children.findIndex(c => findPaneDeep(c, paneId))
    pane.size = 50
    newPane.size = 50
    parent.children.splice(currentIdx + 1, 0, newPane)
  } else {
    // New split direction — wrap current pane
    const splitNode = {
      type: 'split',
      id: `split-${Date.now()}`,
      direction,
      children: [
        { ...pane, size: 50 },
        { ...newPane, size: 50 },
      ],
    }

    if (parent) {
      const idx = parent.children.findIndex(c => findPaneDeep(c, paneId))
      if (idx >= 0) {
        parent.children[idx] = splitNode
      }
    } else {
      // Root-level replacement
      Object.assign(layout, splitNode)
    }
  }
}

// ─── Tree Traversal ───

function findPane(node, paneId) {
  if (node.type === 'pane' && node.id === paneId) return node
  if (node.type === 'split' && node.children) {
    for (const child of node.children) {
      const found = findPane(child, paneId)
      if (found) return found
    }
  }
  return null
}

function findPaneDeep(node, paneId) {
  return !!findPane(node, paneId)
}

function findParentOfPane(node, paneId) {
  if (node.type === 'split' && node.children) {
    for (const child of node.children) {
      if (child.type === 'pane' && child.id === paneId) return node
      const found = findParentOfPane(child, paneId)
      if (found) return found
    }
  }
  return null
}

function removeEmptyPane(node, paneId) {
  if (node.type === 'split' && node.children) {
    node.children = node.children.filter(child => {
      if (child.type === 'pane' && child.id === paneId) return false
      return true
    })

    for (const child of node.children) {
      removeEmptyPane(child, paneId)
    }

    // Flatten if only one child remains
    if (node.children.length === 1) {
      const remaining = node.children[0]
      Object.assign(node, remaining)
    }
  }
}
</script>

<style scoped>
/* ─── Dock Container ─── */
.term-dock {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.term-dock-desktop {
  width: 100%;
  height: 100%;
  overflow: hidden;
}

/* ─── Mobile View ─── */
.term-dock-mobile {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  overflow: hidden;
}

.term-dock-mobile-header {
  display: flex;
  align-items: center;
  padding: 0.4rem 0.75rem;
  border-bottom: 1px solid rgba(164, 176, 189, 0.12);
  background: linear-gradient(180deg, rgba(15, 19, 24, 0.95), rgba(11, 15, 19, 0.98));
}

.term-dock-mobile-title {
  font-family: "JetBrains Mono", monospace;
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--war-brass, #b6905b);
}

.term-dock-mobile-body {
  flex: 1 1 0;
  overflow: hidden;
}
</style>