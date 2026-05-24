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
import { runOnboardingTwo } from '@/terminal/onboarding_two'
import TerminalWindow from './TerminalWindow.vue'
import DockNode from './DockNode.vue'

const isMobile = ref(false)

function checkMobile() {
  isMobile.value = window.innerWidth < 768
}

const auth = useAuth()
let bootSequenceRun = false
const onboardingComplete = ref(false)

onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  
  watch(
    () => auth.isAuthenticated,
    async (isAuthenticated) => {
      if (isAuthenticated && !bootSequenceRun) {
        bootSequenceRun = true

        const playerState = usePlayerState()
        playerState.flush()
        
        await new Promise(resolve => setTimeout(resolve, 500))
        
        const terminal = getActiveTerminal()
        if (!terminal) return
        
        terminal.clear()
        await runBootSequence(terminal, 3500)
        
        const { needsOnboarding, player, error } = await checkOnboardingStatus(supabase)
        
        if (player) {
          playerState.hydrate(player)
        }
        
        // ── Phase 1: Basic Onboarding (username + sect) ──
        if (needsOnboarding && player) {
          await runOnboarding(terminal, player)
          // Re-hydrate after onboarding to get updated state
          const { data: refreshed } = await supabase.rpc('get_player_status')
          if (refreshed) playerState.hydrate(refreshed)
        }
        
        // ── Phase 2: Virtual Computer Assignment ──
        // runOnboardingTwo returns:
        //   'created' — newly provisioned, faction welcome already shown
        //   'exists'  — VM already existed, need standard final welcome
        //   false     — error
        const hasBasicOnboarding = playerState.get('username') && playerState.get('sect_id')
        let phase2Result = 'exists'
        
        if (hasBasicOnboarding) {
          phase2Result = await runOnboardingTwo(terminal, player)
          if (phase2Result === false) {
            terminal.busy = false
            return
          }
        }
        
        // ── Final: Normal terminal setup (only if no full welcome was shown) ──
        if (hasBasicOnboarding && playerState.get('has_virtual_computer') && phase2Result === 'exists') {
          if (playerState.get('virtual_machine_ip')) {
            terminal.setLocation(playerState.get('virtual_machine_ip'))
          } else if (playerState.ipAddress.value) {
            terminal.setLocation(playerState.ipAddress.value)
          }
          terminal.writeAll([
            { text: '', class: '' },
            { text: '  Welcome to Holy War Online. Type /help for help.', class: 'term-brass' },
            { text: '', class: '' },
          ])
        }
        
        onboardingComplete.value = true
      }
    },
    { immediate: true }
  )
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', checkMobile)
})

let terminalCounter = 0
let paneCounter = 0
let tabCounter = 0

function newPaneId() { return `pane-${++paneCounter}` }
function newTabId() { return `tab-${++tabCounter}` }
function newTermId() { return `term-${++terminalCounter}` }

const terminals = reactive(new Map())
const activeTerminalId = ref('')

function createTerminal() {
  const id = newTermId()
  const term = useTerminal(id)
  terminals.set(id, term)
  return { id, term }
}

function _injectTabContext(term, paneId, tabId) {
  const tabContext = {
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
    setTitle: (title) => {
      const pane = findPane(layout, paneId)
      if (!pane) return
      const tab = pane.tabs.find(t => t.id === tabId)
      if (tab) {
        tab.title = title
      }
    },
  }

  term.buildRegistry({ tab: tabContext })
  
  // Expose directly on the instance to guarantee easy access from external JS systems
  term.tab = tabContext

  const ps = usePlayerState()
  if (ps.ipAddress.value) {
    term.setLocation(ps.ipAddress.value)
  }

  term.startup()
}

function getActiveTerminal() {
  return terminals.get(activeTerminalId.value) || terminals.values().next().value
}

const firstTerm = createTerminal()
const firstTabId = newTabId()
const firstPaneId = newPaneId()

activeTerminalId.value = firstTerm.id

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

const activeIds = reactive(new Map())
activeIds.set(firstPaneId, firstTabId)

function handleActivateTab({ paneId, tabId }) {
  activeIds.set(paneId, tabId)
  const pane = findPane(layout, paneId)
  if (pane) {
    const tab = pane.tabs.find(t => t.id === tabId)
    if (tab) activeTerminalId.value = tab.terminalId
  }
}

function handleNewTab({ paneId, initialCommand }) {
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
    setTimeout(() => {
      term.processCommand(initialCommand)
    }, 50)
  }
}

function handleCloseTab({ paneId, tabId }) {
  const pane = findPane(layout, paneId)
  if (!pane) return

  const totalTabs = getTotalTabCount()
  if (totalTabs <= 1) {
    handleNewTab({ paneId })
  }

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
    const currentIdx = parent.children.findIndex(c => findPaneDeep(c, paneId))
    pane.size = 50
    newPane.size = 50
    parent.children.splice(currentIdx + 1, 0, newPane)
  } else {
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
      Object.assign(layout, splitNode)
    }
  }
}

function getTotalTabCount() {
  let count = 0
  function collect(node) {
    if (node.type === 'pane') {
      count += node.tabs.length
    } else if (node.type === 'split' && node.children) {
      node.children.forEach(collect)
    }
  }
  collect(layout)
  return count
}

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