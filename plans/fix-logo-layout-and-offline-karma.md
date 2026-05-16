# Fix: Logo Layout, Altar Layout & Offline Karma

## Issue 1: Login Page — Logo beside sign-in box instead of under it

**Root Cause:** The outer container in [`LoginView.vue`](src/views/LoginView.vue:2) uses `flex` which defaults to `flex-row`, making the logo div a sibling that sits to the RIGHT of the login card instead of below it.

**Current structure:**
- Outer div: `flex items-center justify-center` → row layout
- Login card div and icon div are siblings → icon appears beside card
- Logo is only `w-[75px] h-[75px]`
- Title "Electric Monk" and tagline are INSIDE the card as a header block

**Fix:**
1. Change outer div to `flex flex-col items-center justify-center` so children stack vertically
2. Move the logo ABOVE the login card, increase to `w-[200px] h-[200px]` (~3x larger)
3. Remove the `<h1>` and `<p>` header block from inside the card
4. Add the tagline "Automated Prayers As A Service" BELOW the login card as a subtle text element

**Target layout:**
```
┌─────────────────────┐
│     [LOGO 200x200]  │
│                     │
│  ┌───────────────┐  │
│  │  Email input   │  │
│  │  Password input│  │
│  │  Sign In btn   │  │
│  │  Google btn    │  │
│  │  Toggle/Reset  │  │
│  └───────────────┘  │
│                     │
│  Automated Prayers  │
│  As A Service       │
└─────────────────────┘
```

---

## Issue 2: Altar Page — Logo too small, Active Prayer below Submit

**Root Cause:** In [`AltarView.vue`](src/views/AltarView.vue:58), the "Submit Your Prayer" section comes before the "Active Prayer" section in the DOM, and the logo is only `w-[50px] h-[50px]`.

**Current order:**
1. Submit Your Prayer (with tiny 50px logo)
2. Active Prayer
3. Inactive Prayers
4. Archived Prayers

**Fix:**
1. Move the entire "Active Prayer" section (lines 129-221) ABOVE the "Submit Your Prayer" section (lines 59-127)
2. Increase the logo in Submit Your Prayer from `w-[50px] h-[50px]` to `w-[200px] h-[200px]` (4x larger)

**Target layout:**
```
┌─────────────────────────┐
│  Active Prayer          │
│  [prayer card with       │
│   counter + progress]    │
└─────────────────────────┘

┌─────────────────────────┐
│     [LOGO 200x200]      │
│  Submit Your Prayer     │
│  [textarea + button]    │
└─────────────────────────┘

┌─────────────────────────┐
│  Inactive Prayers       │
└─────────────────────────┘
```

---

## Issue 3: Offline Karma Gains Not Syncing

**Root Cause:** In [`usePrayerCounter.js`](src/composables/usePrayerCounter.js:98), the `initializeCount()` function calculates `elapsedCycles` (cycles that occurred while offline) and adds them to the displayed count, but then sets `lastLocalCount = 0`. This means those offline cycles are **displayed** but **never synced** to the server. The `syncToBackend()` function only sends `lastLocalCount`, so karma milestones earned during offline periods are lost.

**Current code (line 112):**
```javascript
lastLocalCount = 0 // Reset local delta since we just recalibrated
```

**Fix:**
Change line 112 to:
```javascript
lastLocalCount = elapsedCycles // Queue offline cycles for sync
```

This ensures that when the next periodic sync fires (every 10 seconds), the offline cycles are pushed to the server via `sync_prayer_count`, which:
1. Adds them to `prayer_count` in the database
2. Checks for 10-pray karma milestones
3. Awards karma via `update_karma()`
4. Returns `karma_change` so the client can show a toast

The `syncToBackend()` method already recalibrates `displayedCount` from the server response and resets `lastLocalCount = 0` after a successful sync, so this is safe — it won't double-count.

---

## Files to Modify

| File | Changes |
|------|---------|
| [`src/views/LoginView.vue`](src/views/LoginView.vue) | Restructure template: flex-col layout, logo above card, tagline below, remove h1/p header |
| [`src/views/AltarView.vue`](src/views/AltarView.vue) | Move Active Prayer above Submit Prayer, increase logo to 200px |
| [`src/composables/usePrayerCounter.js`](src/composables/usePrayerCounter.js) | Change `lastLocalCount = 0` to `lastLocalCount = elapsedCycles` in `initializeCount()` |