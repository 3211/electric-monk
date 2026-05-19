# Combat System Audit — Full Report

**Date:** 2026-05-18  
**Scope:** All Exodus-series migrations, Genesis combat RPCs, and Vue frontend  
**Trigger:** "Combat takes too long" + Vatican UI text suspect

---

## 1. Executive Summary

**Two completely different 1v1 combat systems coexist in the codebase.** They have different mechanics, different costs, different win conditions, and are triggered from different UI paths. Neither knows about the other.

| | System A: Tick-Based Siege | System B: Instant-Resolve |
|---|---|---|
| **SQL RPC** | [`initiate_combat()`](supabase/migrations/exodus_2.sql:174) | [`launch_crusade()`](supabase/migrations/genesis_9.sql:728) |
| **Table** | [`combat_sessions`](supabase/migrations/exodus_1.sql:57) | None (stateless) |
| **Initiation Cost** | 50 **Gold** + 10 Gold/tick | 50 **Mana** |
| **Attack Stat** | Worker count (novice/monk/cleric/bishop/cardinal/cultist) = DPS per tick | Mana + (Clerics × 10) = single attack roll |
| **Defense Stat** | Mana pool as HP; also defender workers deal counter-damage | Churches × 15 + Cathedrals × 40 = defense roll |
| **Resolution** | Per-minute ticks; winner when HP ≤ 0 or ticks exhausted | Instant dice roll (0.7–1.3 random multiplier) |
| **Max Duration** | 30 ticks = 30 minutes (config `combat.pvp_max_ticks`) | Instant |
| **Win Reward** | Vassaldom + karma + gold leeched | Vassaldom + acre theft + LIFO building ruin |
| **UI Path** | [PurgatoryView "Direct Combat"](src/views/PurgatoryView.vue:79) | [VaticanView "Launch Crusade"](src/views/VaticanView.vue:134) |
| **Composable** | [`useCombat.js`](src/composables/useCombat.js:25) | [`useVassalage.js`](src/composables/useVassalage.js:211) |
| **One-at-a-time?** | Yes (`active_combat_target_id` column) | No |

---

## 2. System A: Exodus Tick-Based Siege (`initiate_combat`)

### 2.1 SQL Backend — Fully Implemented

| Component | Location | Status |
|---|---|---|
| `combat_sessions` table | [`exodus_1.sql:57`](supabase/migrations/exodus_1.sql:57) | ✅ |
| `initiate_combat(p_target_id)` | [`exodus_2.sql:174`](supabase/migrations/exodus_2.sql:174) (overrides exodus_1 version) | ✅ |
| `get_active_combats()` | [`exodus_1.sql:1231`](supabase/migrations/exodus_1.sql:1231) | ✅ |
| Heartbeat tick loop (Phase 6) | [`exodus_4.sql:316`](supabase/migrations/exodus_4.sql:316) (same as exodus_2:916) | ✅ |
| `active_combat_target_id` column | [`exodus_2.sql:33`](supabase/migrations/exodus_2.sql:33) | ✅ |
| Subjugation timer advance (Phase 7) | [`exodus_4.sql:453`](supabase/migrations/exodus_4.sql:453) | ✅ |
| Vassal tithes (Phase 8) | [`exodus_4.sql:486`](supabase/migrations/exodus_4.sql:486) | ✅ |

**How the tick loop works** (every minute via `calculate_automated_karma()`):

1. Read live `mana`, `gold`, and `worker_count` from both profiles each tick
2. Attacker workers = damage to defender's mana pool: `defender.mana -= attacker_workers`
3. Defender workers = counter-damage to attacker: `attacker.mana -= defender_workers`
4. Gold leech: 2% of defender's gold stolen per tick
5. Gold cost: 10 gold/tick deducted from attacker
6. Victory conditions (checked in order):
   - `defender_win`: defender mana ≤ 0
   - `attacker_win`: attacker mana ≤ 0 OR attacker can't pay gold tick cost
   - `stalemate`: ticks_remaining ≤ 0
7. On attacker win: sets `suzerain_id`, awards karma (5 for enemy faction, 1 for neutral)
8. Clears `active_combat_target_id` on resolution

### 2.2 Frontend — Partially Surfaced

| Component | Location | Status |
|---|---|---|
| `useCombat.js` composable | [`src/composables/useCombat.js`](src/composables/useCombat.js) | ✅ |
| PurgatoryView "Direct Combat" | [`src/views/PurgatoryView.vue:79-160`](src/views/PurgatoryView.vue:79) | ✅ |
| Active combat cards (mana bars, workers, ticks, gold) | [`src/views/PurgatoryView.vue:131-156`](src/views/PurgatoryView.vue:131) | ✅ |
| Betrayal notice display | [`src/views/PurgatoryView.vue:125-128`](src/views/PurgatoryView.vue:125) | ✅ |
| 5-second polling | [`src/composables/useCombat.js:83`](src/composables/useCombat.js:83) | ✅ |

**Note:** The only place the new tick-based combat is surfaced is **PurgatoryView** — the ban/punishment screen. This is an odd home for the primary PvP mechanic.

---

## 3. System B: Genesis Instant-Resolve (`launch_crusade`)

### 3.1 SQL Backend — Still Active

| Component | Location | Status |
|---|---|---|
| `launch_crusade(p_target_id)` | [`genesis_9.sql:728`](supabase/migrations/genesis_9.sql:728) (latest of 3 rewrites) | ✅ |
| `cast_plague(p_target_id)` | [`genesis_9.sql:980`](supabase/migrations/genesis_9.sql:980) | ✅ |
| `declare_schism()` | [`genesis_2.sql:1028`](supabase/migrations/genesis_2.sql:1028) | ✅ |
| `get_vassalage_info()` | [`exodus_1.sql:1402`](supabase/migrations/exodus_1.sql:1402) (includes subjugation timers) | ✅ |
| `lookup_player(p_search)` | (genesis-era) | ✅ |
| `get_akashic_logs(p_limit, p_offset)` | (genesis-era) | ✅ |

**How `launch_crusade` works:**

1. Costs 50 **Mana** (deducted regardless of outcome)
2. Attack power = `max(1, attacker_mana) + (cleric_count × 10)`
3. Defense power = `(church_count × 15) + (cathedral_count × 40)`
4. Both sides roll: `power × random(0.7, 1.3)`
5. If attack_roll > defense_roll → win: sets suzerain, steals 3 acres, LIFO building ruin
6. Includes Holy War bonus (+20%), relic bonuses, research bonuses, sect defense bonuses
7. Checks: Divine Shield, Papal Bull, circular vassalage, already-your-vassal

### 3.2 Frontend — Primary Combat UI

| Component | Location | Status |
|---|---|---|
| `useVassalage.js` composable | [`src/composables/useVassalage.js`](src/composables/useVassalage.js) | ✅ |
| VaticanView "Launch Crusade" | [`src/views/VaticanView.vue:134-205`](src/views/VaticanView.vue:134) | ✅ calls `launch_crusade` |
| VaticanView "Cast Curse" | [`src/views/VaticanView.vue:358-421`](src/views/VaticanView.vue:358) | ✅ calls `cast_plague` |
| VaticanView "Declare Schism" | [`src/views/VaticanView.vue:423-457`](src/views/VaticanView.vue:423) | ✅ calls `declare_schism` |
| VaticanView "Your Liege Lord" | [`src/views/VaticanView.vue:60-92`](src/views/VaticanView.vue:60) | ✅ |
| VaticanView "Your Vassals" | [`src/views/VaticanView.vue:94-132`](src/views/VaticanView.vue:94) | ✅ |
| Crusade confirmation modal | [`src/views/VaticanView.vue:483-511`](src/views/VaticanView.vue:483) | ✅ |

---

## 4. The UI Text Problem (Your Observation)

### The offending code

In [`VaticanView.vue:141-143`](src/views/VaticanView.vue:141):

```html
<p class="text-xs text-theme-text-muted">
  Spend Mana to attack another player. If victorious, they become your Vassal and pay 10% tithe.
  Your attack power: <span class="font-semibold text-blue-500">{{ vassalage.crusadeAttackPower }}</span> (Mana + Clerics)
</p>
```

### What `crusadeAttackPower` computes

From [`useVassalage.js:74-79`](src/composables/useVassalage.js:74):

```js
const crusadeAttackPower = computed(() => {
  const mana = economy.mana || 0
  const clericCount = economy.buildingCounts?.cleric || 0
  const ratingPerCleric = 10
  return Math.max(1, mana) + (clericCount * ratingPerCleric)
})
```

### The mismatch

This formula (`mana + clerics×10`) matches the **old** [`launch_crusade`](supabase/migrations/genesis_2.sql:893) SQL exactly:

```sql
v_attack_rating := GREATEST(1, v_attacker_mana) + (v_attacker_clerics * v_attack_rating);
```

But the **new** Exodus system uses **worker count = DPS per tick** and **mana = HP pool**. There is no "attack power" number in the new system — combat is attritional.

### The confirmation modal also lies

[`VaticanView.vue:491`](src/views/VaticanView.vue:491):
```html
This will cost <span class="font-semibold text-blue-500">50 Mana</span> regardless of outcome.
```

This is accurate for `launch_crusade` (which costs 50 Mana). The new `initiate_combat` costs **50 Gold** initiation + **10 Gold/tick**.

### Verdict

The VaticanView "Launch Crusade" UI text **accurately describes the old system it's connected to**. The text is not "left behind" — the entire UI path is still wired to the old RPC. The overhaul happened in `initiate_combat` / `combat_sessions` / `useCombat.js` / PurgatoryView, but VaticanView was never updated.

---

## 5. Complete Cross-Reference Table

### SQL RPC → Vue Call Mapping

| SQL RPC | Defined In | Called By Composable | Rendered In Vue | Status |
|---|---|---|---|---|
| `initiate_combat(UUID)` | exodus_2.sql:174 | `useCombat.initiateCombat()` | PurgatoryView:79-160 | ✅ Wired |
| `get_active_combats()` | exodus_1.sql:1231 | `useCombat.fetchActiveCombats()` | PurgatoryView:131-156 | ✅ Wired |
| `launch_crusade(UUID)` | genesis_9.sql:728 | `useVassalage.launchCrusade()` | VaticanView:489-497 | ✅ Wired |
| `cast_plague(UUID)` | genesis_9.sql:980 | `useVassalage.castPlague()` | VaticanView:526-531 | ✅ Wired |
| `declare_schism()` | genesis_2.sql:1028 | `useVassalage.declareSchism()` | VaticanView:553-558 | ✅ Wired |
| `get_vassalage_info()` | exodus_1.sql:1402 | `useVassalage.fetchVassalageInfo()` | VaticanView:60-132 | ✅ Wired |
| `get_akashic_logs(INT,INT)` | genesis-era | `useVassalage.fetchAkashicLogs()` | VaticanView:208-264 | ✅ Wired |
| `lookup_player(TEXT)` | genesis-era | `useVassalage.lookupPlayer()` | VaticanView:618, PurgatoryView:271 | ✅ Wired |
| `start_subjugation(UUID)` | exodus_1.sql:1272 | `useVassalage.startSubjugation()` | **NOWHERE** | ❌ No UI |
| `resist_subjugation(UUID)` | exodus_1.sql:1325 | `useVassalage.resistSubjugation()` | **NOWHERE** | ❌ No UI |
| `attempt_rebellion()` | exodus_1.sql:1365 | `useVassalage.attemptRebellion()` | **NOWHERE** | ❌ No UI |
| `initiate_holy_war(UUID)` | exodus_2.sql:341 | `useHolyWar.initiateHolyWar()` | HolyWarView:68-76 | ✅ Wired |
| `get_active_holy_wars()` | exodus-era | `useHolyWar.fetchActiveWars()` | HolyWarView:94-161 | ✅ Wired |
| `find_synod_by_name(TEXT)` | exodus-era | `useHolyWar.findTarget()` | HolyWarView:43-56 | ✅ Wired |
| `process_holy_war_tick(UUID)` | exodus_1.sql:940 | Heartbeat only | N/A | ✅ Internal |

---

## 6. Backend Without Vue UI (Orphaned SQL)

### 6.1 Subjugation System — Fully Built, Zero UI

The [`subjugation_timers`](supabase/migrations/exodus_1.sql:85) table tracks a 168-hour countdown. Three RPCs exist and are wired in [`useVassalage.js`](src/composables/useVassalage.js):

| RPC | Composable Method | What It Does |
|---|---|---|
| `start_subjugation(target_id)` | `startSubjugation()` | Creates/advances a 168-hour timer. Once full, target becomes vassal. |
| `resist_subjugation(liege_id)` | `resistSubjugation()` | Pay 1000 Gold → subtract 24 hours from timer |
| `attempt_rebellion()` | `attemptRebellion()` | If liege hasn't attacked in 3+ days → break free |

The heartbeat Phase 7 ([`exodus_4.sql:453`](supabase/migrations/exodus_4.sql:453)) advances subjugation timers by 1/60th of an hour per minute for active combats, and auto-vassalizes when 168 hours accumulate.

**No Vue component calls any of these three methods.** The subjugation data (`subjugation_as_liege`, `subjugation_as_vassal`) is fetched by `get_vassalage_info()` but never displayed.

### 6.2 `useVassalage` reactive state — Fetched but Unrendered

From [`useVassalage.js:119-120`](src/composables/useVassalage.js:119):

```js
subjugationAsLiege.value = data.subjugation_as_liege || []
subjugationAsVassal.value = data.subjugation_as_vassal || []
```

Plus computed properties `isBeingSubjugated` and `isSubjugatingSomeone` (lines 99-100) — all unused in any template.

---

## 7. Vue Referencing Wrong/Old Backend

### 7.1 VaticanView "Launch Crusade" → `launch_crusade` (should be `initiate_combat`)

The entire [`VaticanView.vue:134-205`](src/views/VaticanView.vue:134) "Launch Crusade" section and its confirmation modal use the old instant-resolve system. If the intent (per [`exodus-overhaul.md`](plans/exodus-overhaul.md)) was to replace 1v1 combat with tick-based sieges, this entire section needs to call `useCombat.initiateCombat()` instead of `useVassalage.launchCrusade()`.

### 7.2 PurgatoryView "Direct Combat" already uses the new system

[`PurgatoryView.vue:79-160`](src/views/PurgatoryView.vue:79) is correctly wired to `useCombat.initiateCombat()` and displays tick-based combat state. However, it's in the punishment screen — not where players would naturally go to attack.

---

## 8. Bugs and Discrepancies Found

### 8.1 `GREATER` vs `GREATEST` typo (fixed in exodus_2)

[`exodus_1.sql:1216`](supabase/migrations/exodus_1.sql:1216):
```sql
GREATER(1, v_user_workers)  -- PostgreSQL has no GREATER function
```

Fixed in [`exodus_2.sql:321`](supabase/migrations/exodus_2.sql:321) to `GREATEST(1, v_user_workers)`. Since exodus_2 runs after exodus_1, the live version is correct.

### 8.2 Tick divisor mismatch between exodus_2 and exodus_4

| File | `v_tick_divisor` | Effect |
|---|---|---|
| [`exodus_2.sql`](supabase/migrations/exodus_2.sql) heartbeat | `144` (10x speed) | Resources generate faster |
| [`exodus_4.sql:47`](supabase/migrations/exodus_4.sql:47) heartbeat | `1440` (normal speed) | Resources generate slower |

Since exodus_4 is the live version, resource generation runs at normal (1/1440 per minute) speed. This may be intentional (undoing the 10x experiment), but differs from what the plan specified.

### 8.3 `combat.pvp_max_ticks` fallback value

[`exodus_2.sql:240`](supabase/migrations/exodus_2.sql:240):
```sql
IF v_max_ticks IS NULL THEN v_max_ticks := 10080; END IF;  -- 7 days!
```

The game_config value is `30` (set in exodus_1), so this fallback is never hit. But if the config key were ever deleted, combat would become 7-day sieges. The fallback should probably be 30 to match intent.

### 8.4 `tithe.percentage` key name inconsistency

[`exodus_4.sql:53`](supabase/migrations/exodus_4.sql:53):
```sql
SELECT COALESCE(value, 0.10) INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
```

But [`exodus_1.sql:217`](supabase/migrations/exodus_1.sql:217) inserts it as:
```sql
('vassalage.tithe_pct', 0.10, ...)
```

And [`exodus_1.sql:1416`](supabase/migrations/exodus_1.sql:1416) reads:
```sql
SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
```

The key was inserted as `vassalage.tithe_pct` but read as `tithe.percentage`. This means the fallback (0.10) is always used. This affects both the heartbeat tithe calculation AND `get_vassalage_info()`.

### 8.5 `launch_crusade` sect reference to `doomsday_preppers`

[`genesis_2.sql:922`](supabase/migrations/genesis_2.sql:922) (and genesis_9.sql):
```sql
IF v_target_sect = 'doomsday_preppers' THEN
```

This sect was renamed to `final_watch` in [`genesis_6.sql:334`](supabase/migrations/genesis_6.sql:334). The `launch_crusade` in genesis_9.sql was NOT updated for this rename — the defense bonus for Final Watch members will never trigger.

### 8.6 `combat.pvp_initiation_gold` key mismatch

[`exodus_2.sql:233`](supabase/migrations/exodus_2.sql:233):
```sql
SELECT value INTO v_initiation_cost FROM game_config WHERE key = 'combat.pvp_initiation_gold';
```

The key exists (inserted in exodus_1.sql:217). Correct.

But the VaticanView confirmation modal says "50 Mana" — because it calls `launch_crusade` which uses `crusade.mana_cost` (50 mana), not `combat.pvp_initiation_gold` (50 gold).

---

## 9. What the Plan Said vs What Was Built

From [`plans/exodus-overhaul.md`](plans/exodus-overhaul.md):

| Plan Item | Built? | Notes |
|---|---|---|
| Tick-based PvP via `initiate_combat` | ✅ | Fully functional in SQL + useCombat.js + PurgatoryView |
| "NO faction block in UI" | ✅ | Both systems allow attacking anyone; betrayal detected server-side |
| Subjugation timers (168h) | ✅ | SQL + composable complete, but **no Vue UI** |
| Resist subjugation (1000g → -24h) | ✅ | SQL + composable complete, but **no Vue UI** |
| Rebellion (3 idle days → break free) | ✅ | SQL + composable complete, but **no Vue UI** |
| Remove old `launch_crusade` | ❌ | Still active, still the primary VaticanView combat path |
| One-at-a-time combat limit | ✅ | `active_combat_target_id` column enforces this |

---

## 10. Recommendations

### Immediate (Bug Fixes)

1. **Fix `tithe.percentage` key mismatch**: Change all reads from `'tithe.percentage'` to `'vassalage.tithe_pct'` (or vice versa, but be consistent). Affects [`exodus_4.sql:53`](supabase/migrations/exodus_4.sql:53), [`exodus_1.sql:1416`](supabase/migrations/exodus_1.sql:1416), and heartbeat Phase 8.

2. **Fix `doomsday_preppers` → `final_watch`** in [`genesis_9.sql` `launch_crusade`](supabase/migrations/genesis_9.sql) (line ~922 in the genesis_9 version).

3. **Fix `combat.pvp_max_ticks` fallback** from 10080 to 30 in [`exodus_2.sql:240`](supabase/migrations/exodus_2.sql:240).

### Architecture (Unify Combat)

4. **Decide which system wins.** The old `launch_crusade` has richer features (acre theft, LIFO ruin, relic/sect/war bonuses) but is instant. The new `initiate_combat` is tick-based siege but lacks those features. You need to either:
   - **A)** Port the rich features from `launch_crusade` into the tick-based system, then deprecate `launch_crusade`, OR
   - **B)** Keep both but clearly differentiate them (e.g., "Quick Raid" = old system, "Siege" = new system)

5. **Move the primary PvP UI** from PurgatoryView to VaticanView (or a dedicated CombatView). Purgatory is a punishment screen.

6. **Update VaticanView "Launch Crusade"** to use `useCombat.initiateCombat()` instead of `useVassalage.launchCrusade()`, and update all UI text to reflect tick-based mechanics (Gold cost, workers = DPS, mana = HP).

### Missing UI

7. **Build subjugation UI** — Show active subjugation timers, "Resist (1000g)" and "Rebel" buttons in VaticanView. The data is already fetched by `useVassalage`.

8. **Show active tick-based combats** in VaticanView, not just PurgatoryView. Players shouldn't need to be banned to see their active sieges.