import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue()],
  // Base path for GitHub Pages deployment
  // Change 'electric-monk' to your repository name if different
  base: '/electric-monk/',
})
