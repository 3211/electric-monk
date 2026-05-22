<template>
  <!-- Split container -->
  <div v-if="node.type === 'split'" class="term-dock-split" :class="'term-dock-split--' + node.direction">
    <div
      v-for="(child, i) in node.children"
      :key="child.id"
      class="term-dock-split-child"
      :style="node.direction === 'horizontal'
        ? { width: (child.size || 50) + '%' }
        : { height: (child.size || 50) + '%' }"
    >
      <DockNode
        :node="child"
        :terminals="terminals"
        :active-ids="activeIds"
        :onboarding-complete="onboardingComplete"
        @split="(...args) => $emit('split', ...args)"
        @close-tab="(...args) => $emit('close-tab', ...args)"
        @activate-tab="(...args) => $emit('activate-tab', ...args)"
        @new-tab="(...args) => $emit('new-tab', ...args)"
      />
    </div>
    <!-- Resize handles between children -->
    <template v-for="(child, i) in node.children" :key="'h-' + child.id">
      <div
        v-if="i < node.children.length - 1"
        class="term-dock-resize-handle"
        :class="node.direction === 'horizontal' ? 'term-dock-resize-h' : 'term-dock-resize-v'"
        @mousedown="startResize($event, node.direction, i)"
      >
        <div class="term-dock-resize-line"></div>
      </div>
    </template>
  </div>

  <!-- Pane (leaf node with tabs) -->
  <div v-else class="term-dock-pane">
    <!-- Tab bar (hidden until onboarding complete) -->
    <div v-if="onboardingComplete" class="term-dock-tab-bar">
      <div class="term-dock-tabs">
        <div
          v-for="tab in node.tabs"
          :key="tab.id"
          class="term-dock-tab"
          :class="{ 'term-dock-tab--active': activeIds.get(node.id) === tab.id }"
          @click="$emit('activate-tab', { paneId: node.id, tabId: tab.id })"
        >
          <span class="term-dock-tab-icon">⌁</span>
          <span class="term-dock-tab-title">{{ tab.title }}</span>
          <button
            class="term-dock-tab-close"
            @click.stop="$emit('close-tab', { paneId: node.id, tabId: tab.id })"
            title="Close terminal"
          >×</button>
        </div>
      </div>
      <div class="term-dock-tab-actions">
        <button
          class="term-dock-tab-btn"
          @click="$emit('new-tab', { paneId: node.id })"
          title="New terminal"
        >+</button>
        <button
          class="term-dock-tab-btn"
          @click="$emit('split', { paneId: node.id, direction: 'horizontal' })"
          title="Split right"
        >⧫</button>
        <button
          class="term-dock-tab-btn"
          @click="$emit('split', { paneId: node.id, direction: 'vertical' })"
          title="Split down"
        >⧩</button>
      </div>
    </div>
    <!-- Terminal content -->
    <div class="term-dock-pane-body">
      <TerminalWindow
        v-if="getActivePaneTerminal(node)"
        :terminal="getActivePaneTerminal(node)"
        :title="getActivePaneTitle(node)"
      />
    </div>
  </div>
</template>

<script setup>
import TerminalWindow from './TerminalWindow.vue'

const props = defineProps({
  node: { type: Object, required: true },
  terminals: { type: Map, required: true },
  activeIds: { type: Map, required: true },
  onboardingComplete: { type: Boolean, default: false },
})

const emit = defineEmits(['split', 'close-tab', 'activate-tab', 'new-tab'])

/**
 * Resolve the active terminal for a pane.
 * activeIds maps paneId → tabId; the tab stores terminalId.
 * The terminals Map is keyed by terminalId.
 */
function getActivePaneTerminal(pane) {
  const activeTabId = props.activeIds.get(pane.id)
  if (!activeTabId) return null
  const activeTab = pane.tabs.find((t) => t.id === activeTabId)
  if (!activeTab) return null
  return props.terminals.get(activeTab.terminalId)
}

function getActivePaneTitle(pane) {
  const activeTabId = props.activeIds.get(pane.id)
  if (!activeTabId) return 'Terminal'
  const activeTab = pane.tabs.find((t) => t.id === activeTabId)
  return activeTab ? activeTab.title : 'Terminal'
}

function startResize(e, direction, index) {
  e.preventDefault()
  // Future: implement drag-to-resize
}
</script>

<style scoped>
/* ─── Split Container ─── */
.term-dock-split {
  display: flex;
  width: 100%;
  height: 100%;
  position: relative;
}

.term-dock-split--horizontal {
  flex-direction: row;
}

.term-dock-split--vertical {
  flex-direction: column;
}

.term-dock-split-child {
  position: relative;
  overflow: hidden;
  min-width: 120px;
  min-height: 80px;
}

/* ─── Resize Handle ─── */
.term-dock-resize-handle {
  position: absolute;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 180ms ease;
}

.term-dock-resize-h {
  width: 6px;
  cursor: col-resize;
  top: 0;
  bottom: 0;
}

.term-dock-resize-v {
  height: 6px;
  cursor: row-resize;
  left: 0;
  right: 0;
}

.term-dock-resize-handle:hover {
  background: rgba(182, 144, 91, 0.12);
}

.term-dock-resize-handle:hover .term-dock-resize-line {
  opacity: 0.6;
}

.term-dock-resize-line {
  border-radius: 1px;
  opacity: 0.25;
  transition: opacity 180ms ease;
}

.term-dock-resize-h .term-dock-resize-line {
  width: 1px;
  height: 24px;
  background: var(--war-brass, #b6905b);
}

.term-dock-resize-v .term-dock-resize-line {
  height: 1px;
  width: 24px;
  background: var(--war-brass, #b6905b);
}

/* ─── Pane ─── */
.term-dock-pane {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-width: 0;
  border: 1px solid rgba(164, 176, 189, 0.12);
  background: rgba(9, 12, 16, 0.98);
  overflow: hidden;
}

/* ─── Tab Bar ─── */
.term-dock-tab-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.25rem;
  padding: 0 0.25rem;
  height: 2.15rem;
  min-height: 2.15rem;
  border-bottom: 1px solid rgba(164, 176, 189, 0.12);
  background:
    linear-gradient(180deg, rgba(18, 22, 28, 0.96), rgba(12, 15, 19, 0.98));
  user-select: none;
}

.term-dock-tabs {
  display: flex;
  align-items: center;
  gap: 0;
  flex: 1 1 0;
  min-width: 0;
  overflow-x: auto;
  overflow-y: hidden;
  scrollbar-width: none;
}

.term-dock-tabs::-webkit-scrollbar {
  display: none;
}

/* ─── Individual Tab ─── */
.term-dock-tab {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.3rem 0.65rem;
  max-width: 12rem;
  min-width: 0;
  border-radius: 2px 2px 0 0;
  border: 1px solid transparent;
  border-bottom: none;
  font-family: "JetBrains Mono", monospace;
  font-size: 0.7rem;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--war-muted, #8291a0);
  background: transparent;
  cursor: pointer;
  transition:
    background 140ms ease,
    color 140ms ease,
    border-color 140ms ease;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.term-dock-tab:hover {
  color: var(--war-text-soft, #b4c0cc);
  background: rgba(255, 255, 255, 0.04);
}

.term-dock-tab--active {
  color: var(--war-text, #d7e0e8);
  background:
    linear-gradient(180deg, rgba(28, 35, 43, 0.94), rgba(18, 23, 29, 0.96));
  border-color: rgba(164, 176, 189, 0.16);
  border-bottom-color: transparent;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.05);
}

.term-dock-tab-icon {
  font-size: 0.65rem;
  opacity: 0.7;
  flex-shrink: 0;
}

.term-dock-tab-title {
  overflow: hidden;
  text-overflow: ellipsis;
}

.term-dock-tab-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1rem;
  height: 1rem;
  padding: 0;
  border: none;
  border-radius: 1px;
  background: transparent;
  color: var(--war-dim, #677482);
  font-size: 0.85rem;
  line-height: 1;
  cursor: pointer;
  flex-shrink: 0;
  transition:
    background 120ms ease,
    color 120ms ease;
}

.term-dock-tab-close:hover {
  background: rgba(155, 107, 102, 0.2);
  color: var(--war-enemy, #9b6b66);
}

/* ─── Tab Action Buttons ─── */
.term-dock-tab-actions {
  display: flex;
  align-items: center;
  gap: 0.15rem;
  flex-shrink: 0;
  margin-left: 0.25rem;
}

.term-dock-tab-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.5rem;
  padding: 0;
  border: 1px solid transparent;
  border-radius: 2px;
  background: transparent;
  color: var(--war-dim, #677482);
  font-family: "JetBrains Mono", monospace;
  font-size: 0.75rem;
  font-weight: 700;
  cursor: pointer;
  transition:
    background 140ms ease,
    color 140ms ease,
    border-color 140ms ease;
}

.term-dock-tab-btn:hover {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(164, 176, 189, 0.16);
  color: var(--war-steel, #b9c5cf);
}

.term-dock-tab-btn:active {
  background: rgba(255, 255, 255, 0.03);
}

/* ─── Pane Body ─── */
.term-dock-pane-body {
  flex: 1 1 0;
  overflow: hidden;
  position: relative;
}

/* ─── Mobile ─── */
@media (max-width: 640px) {
  .term-dock-tab-bar {
    height: 1.8rem;
    min-height: 1.8rem;
  }

  .term-dock-tab {
    font-size: 0.62rem;
    padding: 0.2rem 0.45rem;
  }

  .term-dock-tab-btn {
    width: 1.3rem;
    height: 1.3rem;
    font-size: 0.65rem;
  }
}
</style>