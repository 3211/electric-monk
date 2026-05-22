<template>
  <div class="app-shell h-screen flex flex-col overflow-hidden">
    <!-- Fixed atmospheric background layers -->
    <div aria-hidden="true" class="war-layer war-layer--mist"></div>
    <div aria-hidden="true" class="war-layer war-layer--veil"></div>
    <div aria-hidden="true" class="war-layer war-layer--glow"></div>

    <!-- Main content -->
    <main class="app-content flex-1 relative z-10">
      <LoginView v-if="!auth.isAuthenticated" />
      <HomeScreen v-else />
    </main>

    <!-- Global copyright footer -->
    <footer class="global-footer relative z-10">
      <div class="app-frame py-1.5 text-center text-[0.65rem] tracking-wide" style="color: var(--war-muted);">
        <p>Copyright {{ currentYear }} Lake Boiler Labs. All rights reserved. <a :href="'mailto:' + devEmail" class="footer-link">{{ devEmail }}</a></p>
      </div>
    </footer>
  </div>
</template>

<script setup>
import { useAuth } from './composables/useAuth'
import LoginView from './views/LoginView.vue'
import HomeScreen from './views/HomeScreen.vue'

const auth = useAuth()
const currentYear = new Date().getFullYear()
const devEmail = import.meta.env.VITE_DEV_EMAIL || 'contact@example.com'
</script>

<style scoped>
.app-shell {
  --war-bg-0: #090c10;
  --war-bg-1: #0f1318;
  --war-bg-2: #141a20;
  --war-bg-3: #1a2128;
  --war-panel: rgba(24, 31, 39, 0.9);
  --war-panel-strong: rgba(18, 24, 31, 0.94);
  --war-panel-soft: rgba(32, 40, 49, 0.78);
  --war-edge: rgba(164, 176, 189, 0.16);
  --war-edge-strong: rgba(188, 198, 208, 0.22);
  --war-text: #d7e0e8;
  --war-text-soft: #b4c0cc;
  --war-muted: #8291a0;
  --war-dim: #677482;
  --war-steel: #b9c5cf;
  --war-steel-soft: rgba(185, 197, 207, 0.18);
  --war-brass: #b6905b;
  --war-brass-light: #d4ba8e;
  --war-ally: #6c8c83;
  --war-enemy: #9b6b66;
  --war-neutral: #8b856d;

  position: relative;
  isolation: isolate;
  color: var(--war-text);
  background:
    linear-gradient(180deg, rgba(7, 9, 12, 0.94), rgba(11, 15, 19, 0.98)),
    linear-gradient(135deg, rgba(15, 19, 24, 0.92), rgba(10, 13, 17, 0.96));
}

/* Crosshatch texture overlay */
.app-shell::before {
  content: "";
  position: absolute;
  inset: 0;
  background:
    linear-gradient(150deg, rgba(255, 255, 255, 0.02) 12%, transparent 12.5%, transparent 87%, rgba(255, 255, 255, 0.02) 87.5%, rgba(255, 255, 255, 0.02)),
    linear-gradient(30deg, rgba(255, 255, 255, 0.012) 12%, transparent 12.5%, transparent 87%, rgba(255, 255, 255, 0.012) 87.5%, rgba(255, 255, 255, 0.012)),
    linear-gradient(90deg, rgba(255, 255, 255, 0.008) 2%, transparent 2%, transparent 98%, rgba(255, 255, 255, 0.008) 98%),
    linear-gradient(180deg, rgba(255, 255, 255, 0.012), rgba(0, 0, 0, 0.18));
  background-size: 48px 84px, 48px 84px, 48px 84px, 100% 100%;
  background-position: 0 0, 24px 42px, 0 0, 0 0;
  opacity: 0.74;
  pointer-events: none;
  z-index: 0;
}

/* Atmospheric radial glow overlay */
.app-shell::after {
  content: "";
  position: absolute;
  inset: 0;
  background:
    radial-gradient(circle at 18% 0%, rgba(190, 202, 214, 0.08), transparent 28%),
    radial-gradient(circle at 82% 18%, rgba(255, 255, 255, 0.03), transparent 24%),
    linear-gradient(115deg, transparent 18%, rgba(255, 255, 255, 0.03) 31%, transparent 44%),
    linear-gradient(295deg, transparent 56%, rgba(255, 255, 255, 0.016) 67%, transparent 76%);
  mix-blend-mode: screen;
  opacity: 0.7;
  pointer-events: none;
  z-index: 0;
}

.app-content {
  position: relative;
  z-index: 1;
  overflow-y: auto;
  overflow-x: hidden;
  min-height: 0;
}

.global-footer {
  position: relative;
  z-index: 1;
  border-top: 1px solid rgba(164, 176, 189, 0.16);
  background: linear-gradient(180deg, rgba(14, 18, 23, 0.92), rgba(18, 23, 29, 0.88));
  backdrop-filter: blur(18px);
}

.footer-link {
  color: var(--war-steel);
  transition: color 220ms ease;
}

.footer-link:hover {
  color: var(--war-brass-light);
}
</style>