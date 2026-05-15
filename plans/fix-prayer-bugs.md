# Fix Plan: Prayer System Bugs

## ROOT CAUSE: Missing Database Columns

**Critical finding:** The `prayers` table definition in [`supabase-schema.sql`](src/lib/supabase-schema.sql:42) is missing two columns that [`docs/schema.md`](docs/schema.md:47) includes:

- `response_content TEXT` — where the monk's generated prayer/admonishment is stored
- `status TEXT DEFAULT 'pending'` — prayer processing status

When the Edge Function in [`index.ts`](supabase/functions/process-prayer/index.ts:271) runs:
```sql
UPDATE prayers SET response_content = ..., status = 'completed', is_rejected = ..., ...
```
PostgreSQL rejects the **entire** UPDATE statement because those columns don't exist. This means **nothing** gets written — not `is_rejected`, not `rejection_reason`, not `is_praying`, not `activated_at`. The prayer stays in its initial state forever.

This single schema bug is the root cause of multiple downstream failures:
- Monk's response never saved → not restored on re-login
- `is_rejected` never set → purgatory mode never triggers
- `is_praying` never updated → prayer counter logic breaks

---

## Fix 1: Add Missing Columns to Database Schema

**Files:** [`src/lib/supabase-schema.sql`](src/lib/supabase-schema.sql:42), [`docs/schema.md`](docs/schema.md:39)

Add `response_content TEXT` and `status TEXT DEFAULT 'pending'` to the `prayers` table definition. Also add ALTER TABLE migration commands for existing databases:

```sql
-- Migration: Add missing columns
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS response_content TEXT;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';
```

**Why this matters:** Without these columns, the Edge Function's entire UPDATE fails, which is why `is_rejected`, `rejection_reason`, and `response_content` are all NULL in the database.

---

## Fix 2: Harden Edge Function JSON Parsing

**File:** [`supabase/functions/process-prayer/index.ts`](supabase/functions/process-prayer/index.ts:99)

The `cleanJsonResponse` function only strips markdown code blocks. Add safety nets for `<thinking>` tags and leading/trailing whitespace:

```typescript
function cleanJsonResponse(content: string): string {
  return content
    .replace(/```(?:json)?\n?/g, '')   // Strip markdown code blocks
    .replace(/<thinking>[\s\S]*?<\/thinking>/g, '')  // Strip thinking tags
    .trim();
}
```

Also add better error logging when the DB update fails so issues like missing columns are immediately visible in Edge Function logs.

---

## Fix 3: Hide User's Original Text Entirely

**File:** [`src/views/AltarView.vue`](src/views/AltarView.vue:165)

Currently the user's original text (`prayer.content`) is shown in multiple places. Remove all displays of `prayer.content`:

1. **Active prayer card** (line ~168-173): Remove the `<p>` showing `prayers.currentActivePrayer.content`. Only show `response_content`.
2. **Inactive prayer cards** (line ~223-228): Remove `prayer.content` display. Only show `response_content`.
3. **Archived prayers** (line ~271): Remove `prayer.content` display. Only show `response_content`.

If `response_content` is null (shouldn't happen after Fix 1, but defensive), show a placeholder like *"The monk's words echo in silence..."*

---

## Fix 4: Base Prayer Cycle on `response_content` + Golden Progress Bar

### 4a: Change cycle time calculation to use `response_content`

**Files:** [`src/composables/usePrayerCounter.js`](src/composables/usePrayerCounter.js:30), [`src/lib/supabase-schema.sql`](src/lib/supabase-schema.sql:325), [`docs/schema.md`](docs/schema.md:155)

Currently `calculateCycleTimeMs()` uses `prayer.content` (user's text) for cycle calculation. Change to use `prayer.response_content` (monk's generated response) with fallback to `content`:

```javascript
function calculateCycleTimeMs(content) {
  if (!content) return 60000 // 1 minute default if no content
  return Math.max(10000, content.length * TIME_PER_CHAR_MS)
}
```

Also update the `activate_prayer` SQL function which calculates cycle time server-side — change it to use `response_content` with `COALESCE(response_content, content)` fallback.

### 4b: Replace cycle time text with golden progress bar

**File:** [`src/views/AltarView.vue`](src/views/AltarView.vue:154)

Replace the current counter section:

```html
<p class="text-xs text-theme-accent/70">~{{ cycleTimeDisplay }} cycle</p>
```

With a thin golden progress bar that fills up over the cycle duration. The bar resets each time the counter increments. This means:
- The bar fills from 0% to 100% over one cycle period
- When it hits 100%, the counter increments and the bar resets to 0%
- The bar should be a thin line with a golden glow effect

Implementation: Track `cycleStartTime` in `usePrayerCounter`, expose a `cycleProgress` computed (0 to 1), and render a `<div>` with `width` bound to `cycleProgress * 100%`.

---

## Fix 5: Adjust Prayer Cycle Timing (~1 min average)

**File:** [`src/composables/usePrayerCounter.js`](src/composables/usePrayerCounter.js:8)

Current formula: `ceil(len/5) * 150ms` — for a 200-char prayer this gives ~6 seconds, way too fast.

New formula using a configurable `TIME_PER_CHAR_MS` constant:

```javascript
// Configurable: milliseconds per character of the monk's response
// ~200 chars (short prayer) ≈ 40s, ~300 chars (average) ≈ 60s, ~500 chars (long) ≈ 100s
const TIME_PER_CHAR_MS = 200 

function calculateCycleTimeMs(responseContent) {
  if (!responseContent) return 60000 // 1 minute default
  const cycleTime = responseContent.length * TIME_PER_CHAR_MS
  return Math.max(15000, Math.min(cycleTime, 180000)) // Clamp: 15s min, 3min max
}
```

Also update the server-side `activate_prayer` function to use the same formula with `response_content`.

---

## Fix 6: Sync Prayer Count on Pause and Reactivate

**File:** [`src/composables/usePrayerCounter.js`](src/composables/usePrayerCounter.js:16)

Add `beforeunload` and `visibilitychange` handlers that sync the count before the user leaves or tabs away:

```javascript
// In usePrayerCounter, add:
function handleBeforeUnload() {
  if (prayer.value?.is_praying && lastLocalCount > 0) {
    // Use sendBeacon for reliable unload sync, or synchronous RPC
    const payload = JSON.stringify({ p_prayer_id: prayer.value.id, p_elapsed_counts: lastLocalCount })
    navigator.sendBeacon('/.netlify/functions/sync-prayer', payload) // or use supabase directly
  }
}

function handleVisibilityChange() {
  if (document.hidden && prayer.value?.is_praying) {
    // Fire-and-forget sync when tab becomes hidden
    syncToBackend()
  }
}
```

For the `deactivate` (pause) flow: The existing `finalSync()` already calls `deactivate_prayer` RPC. Verify this is always called on pause by checking `handleDeactivate` in `AltarView.vue`.

For `reactivate`: The `activate_prayer` RPC already calculates elapsed cycles server-side. But we should ensure the client-side counter properly recalibrates after reactivation by calling `initializeCount()` after `activatePrayer()`.

---

## Fix 7: Typewriter Effect for Prayer Generation in Aether Modal

**File:** [`src/views/AltarView.vue`](src/views/AltarView.vue:334)

Add a client-side typewriter effect for the `response_content` in the Aether modal result state. When `aetherResult` is set, animate the text appearing character by character:

```javascript
const displayedResponse = ref('')
const typewriterInterval = ref(null)

watch(() => prayers.aetherResult, (result) => {
  if (result?.response) {
    displayedResponse.value = ''
    let i = 0
    clearInterval(typewriterInterval.value)
    typewriterInterval.value = setInterval(() => {
      if (i < result.response.length) {
        displayedResponse.value += result.response[i]
        i++
      } else {
        clearInterval(typewriterInterval.value)
      }
    }, 30) // ~30ms per character
  }
})
```

Then in the template, replace `{{ prayers.aetherResult.response }}` with `{{ displayedResponse }}`.

---

## Implementation Order

1. **Fix 1** (DB columns) — This unblocks everything else. Must be done first.
2. **Fix 2** (Edge Function hardening) — Ensures data flows correctly.
3. **Fix 3** (Hide user text) — Simple UI change.
4. **Fix 5** (Cycle timing) — Change the formula before building the progress bar.
5. **Fix 4** (Golden progress bar) — Visual replacement for cycle time display.
6. **Fix 6** (Count sync on pause/reactivate) — Reliability fix.
7. **Fix 7** (Typewriter effect) — Polish.

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/lib/supabase-schema.sql` | Add `response_content` and `status` columns to `prayers` table + ALTER TABLE migration |
| `docs/schema.md` | Ensure schema docs match |
| `supabase/functions/process-prayer/index.ts` | Harden `cleanJsonResponse`, add DB update error logging |
| `src/composables/usePrayerCounter.js` | New cycle formula based on `response_content`, add `cycleProgress` computed, add `beforeunload`/`visibilitychange` handlers |
| `src/composables/usePrayers.js` | Ensure `response_content` is properly set on local state after Edge Function |
| `src/views/AltarView.vue` | Remove all `prayer.content` displays, add golden progress bar, add typewriter effect for Aether modal |
| `src/lib/supabase-schema.sql` (activate_prayer function) | Change cycle time calc to use `response_content` |