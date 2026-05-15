# Electric Monk - Technical Specification

## Overview
Electric Monk is a dynamic web application designed to run as a standalone GitHub Page using Supabase as a backend-as-a-service.

## Tech Stack
- **Frontend:** Vue.js 3 (Composition API)
- **Styling:** Tailwind CSS
- **Build Tool:** Vite
- **Backend:** Supabase (Auth, Database, Storage)
- **AI Integration:** Venice AI API
- **Deployment:** GitHub Pages via GitHub Actions

## AI-Agent Optimized Architecture
To minimize context usage and API costs for AI agents:
- **Hyper-Modularity:** Every component should have a single responsibility.
- **Atomic Components:** Keep UI elements small and reusable.
- **Composables:** Extract business logic into Vue Composables (`src/composables`) for easy testing and reuse without UI overhead.
- **Strict Typing/Prop Definitions:** Clear interfaces for agent-to-agent handover.

## Project Structure
```text
/
├── .github/workflows/   # CI/CD for GitHub Pages
├── src/
│   ├── assets/          # Sprites, images, and visual assets
│   ├── components/      # Hyper-modular UI components
│   │   ├── atoms/       # Smallest units (buttons, inputs)
│   │   ├── molecules/   # Groups of atoms
│   │   └── organisms/   # Complex UI sections
│   ├── composables/     # Isolated business logic (Supabase hooks, etc.)
│   ├── views/           # Page-level containers
│   ├── lib/             # Third-party initializations (supabase.js)
│   ├── App.vue          # Root component
│   └── main.js          # Entry point
├── public/              # Public static assets
├── index.html           # HTML entry
├── vite.config.js       # Vite configuration
├── tailwind.config.js   # Tailwind configuration
└── package.json         # Dependencies and scripts
```

## Implementation Plan
1. **Initialize Project:** Scaffold Vue + Vite + Tailwind CSS.
2. **Modular Setup:** Create the directory hierarchy for assets, components (atoms/molecules/organisms), and composables.
3. **Supabase Integration:** Install `@supabase/supabase-js` and create a modular client in `src/lib/supabase.js`.
4. **GitHub Pages Config:** Configure `vite.config.js` and GitHub Actions.
5. **Connection Test:** Build a modular 'SupabaseTest' component to verify credentials.
