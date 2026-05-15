/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        ui: ['Inter', '"Segoe UI"', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', '"Cascadia Code"', 'monospace'],
      },
      colors: {
        theme: {
          bg: "var(--theme-bg)",
          panel: "var(--theme-panel)",
          "panel-2": "var(--theme-panel-2)",
          text: "var(--theme-text)",
          "text-dim": "var(--theme-text-dim)",
          "text-muted": "var(--theme-text-muted)",
          accent: "var(--theme-accent)",
          "accent-2": "var(--theme-accent-2)",
          "accent-light": "var(--theme-accent-light)",
          "accent-dark": "var(--theme-accent-dark)",
          purgatory: "var(--theme-purgatory)",
          "purgatory-dark": "var(--theme-purgatory-dark)",
          "purgatory-light": "var(--theme-purgatory-light)",
          border: "var(--theme-border)",
          "border-strong": "var(--theme-border-strong)",
        },
      },
      backgroundImage: {
        'theme-wash': "var(--theme-bg-wash)",
        'theme-shine': "var(--theme-shine)",
      },
      boxShadow: {
        'inner-top': 'inset 0 1px 0 rgba(255, 255, 255, 0.6)',
        'glow-gold': '0 18px 30px rgba(213, 154, 23, 0.28)',
        'glow-purgatory': '0 18px 30px rgba(168, 93, 50, 0.35)',
      },
      borderRadius: {
        'panel': '26px',
        'btn': '14px',
      },
      backdropBlur: {
        'glass': '20px',
      },
    },
  },
  plugins: [],
}
