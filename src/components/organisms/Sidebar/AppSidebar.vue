<template>
  <aside
    class="app-sidebar"
    :class="{ 'app-sidebar--collapsed': isCollapsed }"
    @mouseenter="isHovered = true"
    @mouseleave="isHovered = false"
  >
    <!-- Thin icon strip (always visible) -->
    <div class="app-sidebar-strip">
      <!-- Toggle button -->
      <button
        class="app-sidebar-icon-btn app-sidebar-toggle"
        @click="isCollapsed = !isCollapsed"
        :title="isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'"
        aria-label="Toggle sidebar"
      >
        <svg class="app-sidebar-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
          <line x1="3" y1="4" x2="13" y2="4" />
          <line x1="3" y1="8" x2="13" y2="8" />
          <line x1="3" y1="12" x2="13" y2="12" />
        </svg>
      </button>

      <!-- Navigation icons -->
      <div class="app-sidebar-nav-icons">
        <button
          v-for="nav in navItems"
          :key="nav.id"
          class="app-sidebar-icon-btn"
          :class="{ 'app-sidebar-icon-btn--active': activeNav === nav.id }"
          :title="nav.label"
          @click="handleNav(nav.id)"
        >
          <span class="app-sidebar-icon-emoji">{{ nav.icon }}</span>
        </button>
      </div>

      <!-- Spacer -->
      <div class="app-sidebar-spacer"></div>

      <!-- Bottom actions -->
      <div class="app-sidebar-bottom">
        <button
          class="app-sidebar-icon-btn app-sidebar-icon-btn--danger"
          title="Logout"
          @click="handleLogout"
        >
          <svg class="app-sidebar-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M6 2H3a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3" />
            <polyline points="9 6 12 3 9 0" transform="translate(0,5)" />
            <line x1="12" y1="8" x2="5" y2="8" />
            <path d="M9 2h4a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Expanded panel (slides out) -->
    <transition name="sidebar-slide">
      <div v-if="!isCollapsed || isHovered" class="app-sidebar-panel">
        <div class="app-sidebar-panel-header">
          <span class="app-sidebar-panel-title">HOLY WAR</span>
          <span class="app-sidebar-panel-subtitle">Digital Crusade</span>
        </div>

        <nav class="app-sidebar-nav">
          <button
            v-for="nav in navItems"
            :key="nav.id"
            class="app-sidebar-nav-item"
            :class="{ 'app-sidebar-nav-item--active': activeNav === nav.id }"
            @click="handleNav(nav.id)"
          >
            <span class="app-sidebar-nav-icon">{{ nav.icon }}</span>
            <span class="app-sidebar-nav-label">{{ nav.label }}</span>
            <span v-if="nav.badge" class="app-sidebar-nav-badge">{{ nav.badge }}</span>
          </button>
        </nav>

        <div class="app-sidebar-divider"></div>

        <div class="app-sidebar-section">
          <button class="app-sidebar-logout-btn" @click="handleLogout">
            <svg class="app-sidebar-logout-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <path d="M6 2H3a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3" />
              <polyline points="9 6 12 3 9 0" transform="translate(0,5)" />
              <line x1="12" y1="8" x2="5" y2="8" />
              <path d="M9 2h4a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9" />
            </svg>
            <span>Logout</span>
          </button>
        </div>
      </div>
    </transition>
  </aside>
</template>

<script setup>
import { ref } from 'vue'
import { useAuth } from '@/composables/useAuth'

const auth = useAuth()
const isCollapsed = ref(true)
const isHovered = ref(false)
const activeNav = ref('home')

const navItems = [
  { id: 'home', icon: '⌁', label: 'Home', badge: null }
]

function handleNav(id) {
  activeNav.value = id
}

async function handleLogout() {
  try {
    await auth.signOut()
  } catch (e) {
    console.error('Logout failed:', e)
  }
}
</script>

<style scoped>
/* ─── Sidebar Container ─── */
.app-sidebar {
  position: relative;
  display: flex;
  height: 100%;
  z-index: 30;
  flex-shrink: 0;
  font-family: "JetBrains Mono", monospace;
}

.app-sidebar--collapsed {
  width: 2.5rem;
}

/* ─── Icon Strip ─── */
.app-sidebar-strip {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 2.5rem;
  min-width: 2.5rem;
  height: 100%;
  padding: 0.4rem 0;
  gap: 0.15rem;
  border-right: 1px solid rgba(164, 176, 189, 0.12);
  background:
    linear-gradient(180deg, rgba(15, 19, 24, 0.98), rgba(9, 12, 16, 0.99));
}

.app-sidebar-nav-icons {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.15rem;
  margin-top: 0.35rem;
}

.app-sidebar-spacer {
  flex: 1 1 0;
}

.app-sidebar-bottom {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.15rem;
  margin-bottom: 0.25rem;
}

/* ─── Icon Button ─── */
.app-sidebar-icon-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  padding: 0;
  border: 1px solid transparent;
  border-radius: 2px;
  background: transparent;
  color: var(--war-muted, #8291a0);
  cursor: pointer;
  transition:
    background 140ms ease,
    color 140ms ease,
    border-color 140ms ease;
}

.app-sidebar-icon-btn:hover {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(164, 176, 189, 0.14);
  color: var(--war-steel, #b9c5cf);
}

.app-sidebar-icon-btn--active {
  background: rgba(182, 144, 91, 0.12);
  border-color: rgba(182, 144, 91, 0.2);
  color: var(--war-brass-light, #d4ba8e);
}

.app-sidebar-icon-btn--danger:hover {
  background: rgba(155, 107, 102, 0.14);
  border-color: rgba(155, 107, 102, 0.2);
  color: var(--war-enemy, #9b6b66);
}

.app-sidebar-icon {
  width: 0.9rem;
  height: 0.9rem;
}

.app-sidebar-icon-emoji {
  font-size: 0.85rem;
  line-height: 1;
}

.app-sidebar-toggle {
  margin-bottom: 0.15rem;
}

/* ─── Expanded Panel ─── */
.app-sidebar-panel {
  display: flex;
  flex-direction: column;
  width: 13rem;
  min-width: 13rem;
  height: 100%;
  border-right: 1px solid rgba(164, 176, 189, 0.12);
  background:
    linear-gradient(180deg, rgba(15, 19, 24, 0.98), rgba(9, 12, 16, 0.99));
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: rgba(156, 168, 180, 0.32) rgba(166, 178, 190, 0.06);
}

.app-sidebar-panel-header {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  padding: 0.75rem 0.85rem 0.5rem;
  border-bottom: 1px solid rgba(164, 176, 189, 0.1);
}

.app-sidebar-panel-title {
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--war-brass, #b6905b);
}

.app-sidebar-panel-subtitle {
  font-size: 0.6rem;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--war-dim, #677482);
}

/* ─── Navigation ─── */
.app-sidebar-nav {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  padding: 0.4rem 0.4rem;
}

.app-sidebar-nav-item {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  width: 100%;
  padding: 0.45rem 0.6rem;
  border: 1px solid transparent;
  border-radius: 2px;
  background: transparent;
  color: var(--war-muted, #8291a0);
  font-family: "JetBrains Mono", monospace;
  font-size: 0.72rem;
  font-weight: 600;
  text-align: left;
  cursor: pointer;
  transition:
    background 140ms ease,
    color 140ms ease,
    border-color 140ms ease;
}

.app-sidebar-nav-item:hover {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(164, 176, 189, 0.12);
  color: var(--war-text-soft, #b4c0cc);
}

.app-sidebar-nav-item--active {
  background: rgba(182, 144, 91, 0.1);
  border-color: rgba(182, 144, 91, 0.18);
  color: var(--war-brass-light, #d4ba8e);
}

.app-sidebar-nav-icon {
  font-size: 0.85rem;
  line-height: 1;
  width: 1.1rem;
  text-align: center;
  flex-shrink: 0;
}

.app-sidebar-nav-label {
  flex: 1 1 0;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-sidebar-nav-badge {
  font-size: 0.6rem;
  padding: 0.05rem 0.3rem;
  border-radius: 2px;
  background: rgba(182, 144, 91, 0.16);
  color: var(--war-brass-light, #d4ba8e);
  font-weight: 700;
}

/* ─── Divider ─── */
.app-sidebar-divider {
  height: 1px;
  margin: 0.35rem 0.6rem;
  background: rgba(164, 176, 189, 0.1);
}

/* ─── Logout Button ─── */
.app-sidebar-logout-btn {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: calc(100% - 0.8rem);
  margin: 0.25rem 0.4rem;
  padding: 0.45rem 0.6rem;
  border: 1px solid transparent;
  border-radius: 2px;
  background: transparent;
  color: var(--war-dim, #677482);
  font-family: "JetBrains Mono", monospace;
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  cursor: pointer;
  transition:
    background 140ms ease,
    color 140ms ease,
    border-color 140ms ease;
}

.app-sidebar-logout-btn:hover {
  background: rgba(155, 107, 102, 0.1);
  border-color: rgba(155, 107, 102, 0.18);
  color: var(--war-enemy, #9b6b66);
}

.app-sidebar-logout-icon {
  width: 0.85rem;
  height: 0.85rem;
  flex-shrink: 0;
}

/* ─── Slide Transition ─── */
.sidebar-slide-enter-active,
.sidebar-slide-leave-active {
  transition: transform 220ms cubic-bezier(0.22, 1, 0.36, 1), opacity 180ms ease;
}

.sidebar-slide-enter-from,
.sidebar-slide-leave-to {
  transform: translateX(-100%);
  opacity: 0;
}

/* ─── Mobile ─── */
@media (max-width: 640px) {
  .app-sidebar-strip {
    width: 2rem;
    min-width: 2rem;
  }

  .app-sidebar-icon-btn {
    width: 1.7rem;
    height: 1.7rem;
  }

  .app-sidebar-icon {
    width: 0.75rem;
    height: 0.75rem;
  }

  .app-sidebar-icon-emoji {
    font-size: 0.72rem;
  }

  .app-sidebar-panel {
    width: 10rem;
    min-width: 10rem;
  }
}
</style>