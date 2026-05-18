# Electric Monk — Setup Guide

## Prerequisites
- Node.js 18+
- Supabase project
- Venice AI API key

## 1. Environment Variables

Create `.env`:

```bash
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key-here
VITE_VENICE_API_KEY=your-venice-api-key-here
```

## 2. Database Setup

Run all SQL migration files in **lexicographic order** from the Supabase SQL Editor:

```
genesis_1.sql   →  genesis_2.sql   →  genesis_3.sql   →  genesis_4.sql
genesis_5.sql   →  genesis_6.sql   →  genesis_7.sql   →  genesis_8.sql
genesis_9.sql   →  genesis_9_hotfix.sql   →  genesis_10.sql
exodus_0.sql
```

All files are idempotent (safe to re-run). This creates the full database: 18 tables, 40+ RPCs, RLS policies, seed data, triggers, cron job.

## 3. Supabase Auth

Enable **Google OAuth** in Authentication → Providers:
- Google Cloud Console → OAuth 2.0 credentials
- Redirect URIs: `https://your-project.supabase.co/auth/v1/callback` and `http://localhost:5173/auth/v1/callback`

## 4. Deploy Edge Functions

```bash
cd supabase/functions
supabase functions deploy process-prayer
supabase functions deploy pray-for-sinner
supabase functions deploy generate-onboarding-content
```

## 5. Install & Run

```bash
npm install
npm run dev
```

App at `http://localhost:5173`.

---

## Project Structure

```
src/
├── composables/           # State management + Supabase queries
│   ├── useAuth.js         # Auth (Google + email/password)
│   ├── usePrayers.js      # Prayer submit/sync/activate
│   ├── usePrayerCounter.js # Client-side prayer counting
│   ├── useAkashicRecords.js # Public feed + sinners
│   ├── useEconomy.js      # 4-resource economy + buildings
│   ├── useShop.js         # Karma Shop purchases
│   ├── useKarmaShop.js    # Blessing purchases
│   ├── useBlessings.js    # Blessing aggregates
│   ├── useFactions.js     # Faction overview
│   ├── useSects.js        # Sect selection + info
│   ├── useSynod.js        # Guild management
│   ├── useVassalage.js    # Vassalage + crusade/schism/plague
│   ├── useCatacombs.js    # Heresy economy
│   ├── useInquisition.js  # Inquisition launch
│   ├── useResearch.js     # Tech tree
│   ├── useRelics.js       # Global relics
│   ├── useIndulgences.js  # Premium indulgences
│   ├── useLeaderboard.js  # Rankings
│   ├── useOnboarding.js   # New user flow
│   └── useBanTimer.js     # Purgatory + indulgences
├── views/                 # Page-level components
│   ├── LoginView.vue
│   ├── AltarView.vue      # Main prayer interface
│   ├── AkashicRecordsView.vue
│   ├── FactionsView.vue
│   ├── VaticanView.vue    # Vassalage + combat
│   ├── SynodHallView.vue
│   ├── ScriptoriumView.vue # Tech tree
│   ├── KarmaShopView.vue
│   ├── ReliquaryView.vue
│   ├── LeaderboardView.vue
│   ├── CatacombsView.vue
│   └── PurgatoryView.vue
├── components/
│   ├── molecules/         # Small reusable UI
│   │   ├── BlessingBadgeBar.vue
│   │   ├── KarmaToast.vue
│   │   ├── MiracleBuffBar.vue
│   │   └── ShieldTimer.vue
│   └── organisms/         # Complex feature components
│       ├── OnboardingWizard.vue
│       ├── SectSelectionModal.vue
│       ├── AkashicPrayerCard.vue
│       ├── SinnerCard.vue
│       ├── BlessingPicker.vue
│       ├── BlessingDetailModal.vue
│       ├── PrayerHistoryModal.vue
│       └── UsernameChangeModal.vue
├── config/
│   └── blessings.json     # Blessing definitions (duplicated from DB for display)
└── lib/
    ├── supabase.js        # Supabase client init
    └── supabase-schema.sql # Legacy schema (migrations are authoritative)
```

```
supabase/
├── migrations/            # Authoritative SQL (run in order)
│   ├── genesis_1.sql      # Tables, indexes, RLS, seed data, core functions
│   ├── genesis_2.sql      # All game RPCs (except heartbeat)
│   ├── genesis_3.sql      # calculate_automated_karma() heartbeat
│   ├── genesis_4.sql      # Triggers, GRANTs, cron schedule
│   ├── genesis_5.sql      # Permission + RLS fix patch
│   ├── genesis_6.sql      # Sect rename, PFP, username change
│   ├── genesis_7.sql      # Blessing shield buff system
│   ├── genesis_8.sql      # Player lookup, shield fixes, newbie protection
│   ├── genesis_9.sql      # Synod roles, relic buffs, member management
│   ├── genesis_9_hotfix.sql # Resilient get_player_economy()
│   ├── genesis_10.sql     # Faith-filtered leaderboard RPCs
│   ├── exodus_0.sql       # Faction relationships + get_factions_overview()
│   └── genesis.CLOSED.md  # Genesis series boundary marker
└── functions/
    ├── process-prayer/    # Venice AI prayer validation + response
    ├── pray-for-sinner/   # AI intercessory prayer generator
    └── generate-onboarding-content/ # AI welcome + faction intro