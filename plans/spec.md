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

## Database Schema (Supabase)

### Table: `profiles`
- `id`: uuid (references auth.users)
- `device_id`: text (unique)
- `ban_until`: timestamp with time zone (null if not banned)
- `prayer_count_daily`: int (reset daily)
- `last_prayer_at`: timestamp with time zone
- `created_at`: timestamp with time zone

### Table: `prayers`
- `id`: uuid
- `user_id`: uuid (references profiles.id)
- `content`: text
- `is_rejected`: boolean
- `rejection_reason`: text
- `created_at`: timestamp with time zone

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
│   ├── composables/     # Isolated business logic (useAuth, usePrayers, useVenice)
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
1. **Database Setup:** Create SQL migrations for `profiles` and `prayers` tables.
2. **Anonymous Auth:** Implement `useAuth.js` using Supabase's anonymous sign-in or custom device-ID tracking.
3. **Ban Logic:** Implement `useBanTimer.js` composable to handle the 2-hour lockouts and "Indulgence" (ad) logic.
4. **Prayer Interface:** Build the frontend for submitting prayers and viewing rejections.
5. **Venice AI Processing:** Connect prayer submissions to Venice AI for validation/rejection logic.
