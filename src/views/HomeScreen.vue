<template>
  <div class="home-view">
    <!-- Atmospheric background layers (inherited from App.vue war theme) -->
    <div aria-hidden="true" class="home-bg-mist"></div>
    <div aria-hidden="true" class="home-bg-veil"></div>

    <!-- Main layout: Sidebar + Terminal area -->
    <div class="home-layout">
      <!-- Collapsible sidebar (disabled: set showSidebar = true to re-enable) -->
      <AppSidebar v-if="showSidebar" />

      <!-- Terminal dock area -->
      <div class="home-terminal-area">
        <!-- Status bar -->
        <div class="home-status-bar">
          <div class="home-status-left">
            <span class="home-status-indicator home-status-indicator--online"></span>
            <span class="home-status-text">CONNECTED</span>
          </div>
          <div class="home-status-center">
            <span class="home-status-title">HOLY WAR ONLINE</span>
          </div>
          <div class="home-status-right">
            <span class="home-status-text home-status-text--dim">{{ currentTime }}</span>
          </div>
        </div>

        <!-- Terminal dock -->
        <div class="home-dock-wrapper">
          <TerminalDock />
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'
import AppSidebar from '@/components/organisms/Sidebar/AppSidebar.vue'
import TerminalDock from '@/components/organisms/Terminal/TerminalDock.vue'

const showSidebar = ref(false) // ← flip to true to re-enable sidebar
const currentTime = ref('')
let timeInterval = null

function updateTime() {
  const now = new Date()
  const h = String(now.getHours()).padStart(2, '0')
  const m = String(now.getMinutes()).padStart(2, '0')
  const s = String(now.getSeconds()).padStart(2, '0')
  currentTime.value = `${h}:${m}:${s}`
}

onMounted(() => {
  updateTime()
  timeInterval = setInterval(updateTime, 1000)
})

onBeforeUnmount(() => {
  if (timeInterval) clearInterval(timeInterval)
})
</script>

<style scoped>
/* ─── Home View Container ─── */
.home-view {
  position: relative;
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  overflow: hidden;
  color: var(--war-text, #d7e0e8);
  background:
    linear-gradient(180deg, rgba(7, 9, 12, 0.96), rgba(11, 15, 19, 0.98)),
    linear-gradient(135deg, rgba(15, 19, 24, 0.94), rgba(10, 13, 17, 0.97));
}

/* ─── Atmospheric Background ─── */
.home-bg-mist {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  background:
    radial-gradient(circle at 50% 4%, rgba(185, 197, 207, 0.1), transparent 28%),
    radial-gradient(circle at 18% 24%, rgba(182, 144, 91, 0.06), transparent 22%),
    radial-gradient(circle at 82% 18%, rgba(108, 140, 131, 0.06), transparent 18%);
  filter: blur(34px);
  opacity: 0.84;
  animation: home-drift 28s ease-in-out infinite alternate;
}

.home-bg-veil {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.02), transparent 12%, transparent 84%, rgba(255, 255, 255, 0.018)),
    radial-gradient(circle at 50% 108%, rgba(182, 144, 91, 0.06), transparent 28%);
  opacity: 0.74;
}

@keyframes home-drift {
  0% { transform: translate3d(-1.2%, -0.8%, 0) scale(1.02); }
  50% { transform: translate3d(1%, 1.2%, 0) scale(1.06); }
  100% { transform: translate3d(1.8%, 1.6%, 0) scale(1.08); }
}

/* ─── Main Layout ─── */
.home-layout {
  position: relative;
  z-index: 1;
  display: flex;
  width: 100%;
  height: 100%;
  overflow: hidden;
}

/* ─── Terminal Area ─── */
.home-terminal-area {
  display: flex;
  flex-direction: column;
  flex: 1 1 0;
  min-width: 0;
  overflow: hidden;
}

/* ─── Status Bar ─── */
.home-status-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  height: 1.65rem;
  min-height: 1.65rem;
  padding: 0 0.65rem;
  border-bottom: 1px solid rgba(164, 176, 189, 0.12);
  background:
    linear-gradient(180deg, rgba(18, 22, 28, 0.96), rgba(12, 15, 19, 0.98));
  font-family: "JetBrains Mono", monospace;
  font-size: 0.6rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  user-select: none;
  flex-shrink: 0;
}

.home-status-left,
.home-status-right {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  min-width: 0;
}

.home-status-center {
  display: flex;
  align-items: center;
  justify-content: center;
  flex: 1 1 0;
  min-width: 0;
}

.home-status-text {
  color: var(--war-muted, #8291a0);
}

.home-status-text--dim {
  color: var(--war-dim, #677482);
}

.home-status-title {
  color: var(--war-brass, #b6905b);
  font-weight: 700;
  letter-spacing: 0.14em;
}

.home-status-indicator {
  display: inline-block;
  width: 0.4rem;
  height: 0.4rem;
  border-radius: 1px;
  background: var(--war-ally, #6c8c83);
  box-shadow: 0 0 4px rgba(108, 140, 131, 0.4);
  animation: home-pulse-dot 3s ease-in-out infinite;
}

.home-status-indicator--online {
  background: var(--war-ally, #6c8c83);
}

@keyframes home-pulse-dot {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

/* ─── Dock Wrapper ─── */
.home-dock-wrapper {
  flex: 1 1 0;
  overflow: hidden;
  position: relative;
}

/* ─── Mobile ─── */
@media (max-width: 640px) {
  .home-status-bar {
    height: 1.4rem;
    min-height: 1.4rem;
    padding: 0 0.4rem;
    font-size: 0.55rem;
  }

  .home-status-title {
    letter-spacing: 0.08em;
  }
}
</style>