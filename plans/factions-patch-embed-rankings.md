# Patch: Embed Rankings inside FactionsView

## Problem
Adding Factions as an 8th nav tab causes the main nav bar to wrap to a second row.

## Solution
Remove the standalone **Rankings** tab from the main nav and embed it as a sub-tab inside **FactionsView**, using the same dual-tab pattern from [`VaticanView.vue`](src/views/VaticanView.vue:42-56):

```
┌──────────────────────────────────────────────┐
│  🏛️ Overview  │  🏆 Rankings                  │  ← segmented-shell sub-tab bar
├──────────────────────────────────────────────┤
│  [diamond layout or leaderboard table]       │
└──────────────────────────────────────────────┘
```

## Changes

### 1. [`src/App.vue`](src/App.vue) — Remove standalone Rankings

- **Remove** `import LeaderboardView` (line 16)
- **Remove** `import KarmaShopView` (no — keep it, just remove Rankings)
- **Remove** the Rankings `<button>` from nav (lines 142-147)
- **Remove** `<LeaderboardView v-else-if="currentView === 'rankings'" />` (line 201)
- Nav order becomes: `altar → records → factions → vatican → synod → scriptorium → shop`
- Remove `'rankings'` from any sets or watchers if it's referenced (check `toggleableViews`)

### 2. [`src/views/FactionsView.vue`](src/views/FactionsView.vue) — Add sub-tab bar + Rankings tab

Add sub-tab bar immediately after `<main>` opens, styled exactly like VaticanView:

```html
<div class="mb-8 flex justify-center">
  <div class="segmented-shell">
    <button
      @click="activeTab = 'overview'"
      :class="activeTab === 'overview' ? 'nav-tab-active' : 'nav-tab-inactive'"
    >🏛️ Overview</button>
    <button
      @click="activeTab = 'rankings'"
      :class="activeTab === 'rankings' ? 'nav-tab-active' : 'nav-tab-inactive'"
    >🏆 Rankings</button>
  </div>
</div>
```

`activeTab` ref defaults to `'overview'`.

Wrap the existing diamond layout and detail panel in `v-if="activeTab === 'overview'"`.

Add Rankings tab content — embed the leaderboard directly (not a child component, to keep self-contained). Copy the template structure from `LeaderboardView.vue`:

```
<div v-if="activeTab === 'rankings'" class="overflow-x-auto">
  <table class="w-full">
    <thead>...Rank, Name, Faith, Karma, Mana, Gold, Food...</thead>
    <tbody v-for="player in leaderboard.rankings">...</tbody>
  </table>
</div>
```

**Script additions:**
- Import `useLeaderboard` and `useAuth`
- Add `activeTab = ref('overview')`
- Add `const leaderboard = useLeaderboard()` and `const auth = useAuth()`
- On mounted, fetch leaderboard: `leaderboard.fetchLeaderboard()`
- Same `formatNumber`, `isCurrentUser` helpers as LeaderboardView
- Same loading/error/empty states as LeaderboardView

**CSS additions:**
- Copy the `.nav-tab-active`, `.nav-tab-inactive` scoped styles from VaticanView (lines 747-760)
- Copy responsive overrides for mobile (lines 802-808)

### Summary

| File | Change |
|---|---|
| `src/App.vue` | Remove LeaderboardView import, nav button, and render |
| `src/views/FactionsView.vue` | Add sub-tab bar (Overview/Rankings), embed leaderboard in Rankings tab |