# Exodus Overhaul — Implementation Plan (v2)

**Migration file:** `supabase/migrations/exodus_1.sql`
**Date:** 2026-05-18
**Status:** PLANNING — Phase 0-5 (SQL) first, then 6-8 (Frontend)

---

## Corrections from v1 (User Feedback)

| # | Correction |
|---|---|
| 1 | **Holy War target:** Manual text input (exact name match), NOT a scrollable list |
| 2 | **Direct PvP:** NO faction block in UI. Attack button always active. API detects betrayal → applies ban + karma penalty |
| 3 | **Economy Rebalance:** Speed up from daily to per-minute feel. Multiply production 10x. Increase shop prices 5x-10x. REMOVE resource caps entirely. Back-end handles max (which = buying more generators = higher cap) |

---

## Phase 0b: Economy Rebalance

### Current State (the problem)
- Production values are `_per_day` divided by 1440 (minutes/day) → ~1/tick minimums
- `LEAST(mana, mana_cap)` caps resources to `daily_rate * 10`
- Gold and food use `GREATEST(0, ...)` — no cap on backend, but frontend shows `/cap`
- Shop items cost e.g. 100 gold for a Cardinal → trivial when uncapped

### Rebalance Strategy

**Step 1: Multiply production values in `game_config` by ~10x:**
```sql
UPDATE game_config SET value = value * 10
WHERE key LIKE 'building.%.mana_per_day'
   OR key LIKE 'building.%.gold_per_day'
   OR key LIKE 'building.%.food_per_day'
   OR key LIKE 'building.%.heresy_per_day'
   OR key LIKE 'building.%.dogma_per_day';
```

**Step 2: Multiply shop costs by ~5x-8x:**
```sql
UPDATE shop_items SET
  gold_cost = gold_cost * 6,
  karma_cost = karma_cost * 6,
  heresy_cost = heresy_cost * 6
WHERE gold_cost > 0 OR karma_cost > 0 OR heresy_cost > 0;
```

**Step 3: Remove resource caps in heartbeat:**
- Replace `LEAST(mana + ..., mana_cap)` with `mana + ...` (unbounded)
- Same for `heresy`, `dogma`
- Delete cap division logic (`/1440` stays as-is since production is still "per day" → per-tick)

**Step 4: Scale per-tick generation:**
- Instead of `/1440` (minutes per day), use production value directly as per-minute rate
- Config keys renamed semantically: still `_per_day` but now treated as per-minute generation
- Gold upkeep and food consumption scaled proportionally

**Step 5: Frontend:**
- Remove `manaCap`, `goldCap`, `foodCap` computed values from `useEconomy.js`
- Remove `/{{ cap }}` display from AltarView.vue and any other views
- Add `worker_count` and `building_count` to get_player_economy for new "cap = more buildings" model

---

## Phase 0: Database Schema (`exodus_1.sql`)

### ALTER synods
```sql
ALTER TABLE synods ADD COLUMN IF NOT EXISTS privacy TEXT DEFAULT 'public'
  CHECK (privacy IN ('public', 'private'));
ALTER TABLE synods ADD COLUMN IF NOT EXISTS custom_message TEXT;
ALTER TABLE synods ADD COLUMN IF NOT EXISTS sect_key TEXT;
-- sect_key set at creation from founder's faction, immutable after
```

### New Tables

**`synod_applicants`** — Petition queue for joining synods
**`combat_sessions`** — Single table for PvP + Holy War tick-based combat
**`subjugation_timers`** — 168-hour vassalage countdown per attacker/target pair
**`betrayal_punishments`** — Tracks bans/karma penalties for faction betrayal

### Game Config Keys (centralized tuning)
```
combat.pvp_initiation_gold      = 50
combat.pvp_gold_per_tick        = 10
combat.pvp_max_ticks            = 30
combat.pvp_leech_pct            = 0.02
combat.pvp_attrition_pct        = 0.10
combat.pvp_exertion_pct         = 0.05
combat.holy_war_initiation_gold = 200
combat.holy_war_gold_per_tick   = 100
combat.holy_war_max_ticks       = 60
combat.holy_war_leech_pct       = 0.01
combat.holy_war_victory_pct     = 0.20
combat.betrayal_ally_ban_min    = 15
combat.betrayal_own_ban_min     = 30
combat.betrayal_ally_karma      = -5
combat.betrayal_own_karma       = -10
combat.kill_neutral_karma       = 1
combat.kill_enemy_karma         = 5
vassalage.subjugation_hours     = 168
vassalage.tribute_gold_cost     = 1000
vassalage.rebellion_idle_days   = 3
vassalage.tithe_pct             = 0.10
vassalage.liege_karma_per_day   = 5
```

---

## Phase 1: Synod RPCs

| RPC | Behavior |
|---|---|
| `create_synod(name, privacy, custom_message)` | Sets `sect_key` = founder's faction. Privacy default 'public'. |
| `petition_synod(synod_id)` | Checks faction (own or ally via `faction_relationships`). Inserts into `synod_applicants`. Rejects with "Your sect forbids association with heretics." |
| `get_public_synods()` | Returns public synods matching player's faction or ally faction, with member count, leader name, faction icon |
| `approve_applicant(user_id)` | Leader/steward only. Moves from applicants → member |
| `reject_applicant(user_id)` | Removes from applicants |
| `update_synod_privacy(privacy)` | Leader only |
| `update_synod_message(message)` | Leader only |
| `get_available_factions()` | Returns ONLY factions with the lowest member count. Ties = all tied options returned. |

---

## Phase 2: Holy War RPCs

**Key change:** Target is selected via `find_synod_by_name(exact_name)` — text input, not list.

| RPC | Behavior |
|---|---|
| `find_synod_by_name(name)` | Exact case-insensitive match. Returns synod_id + faction info. |
| `initiate_holy_war(target_synod_id)` | Validates faction (enemy/neutral only). Auto-sums ALL members' mana + workers. Creates `combat_sessions`. Deducts 200g initiation. |
| `get_active_holy_wars()` | All active wars for player's synod. Live stats per tick. |
| `process_holy_war_tick(session_id)` | Called by heartbeat. Damage = attacker workers. Defender mana -= damage. 10% attrition. 5% exertion. 1% leech. 100g/tick cost. Victory/retreat/stalemate. |

---

## Phase 3: Direct PvP RPCs

**Key change:** NO faction block in UI. Attack button works for everyone.

| RPC | Behavior |
|---|---|
| `initiate_combat(target_id)` | Loads both factions. If enemy → allowed (+5 karma on kill). If neutral → allowed (+1 karma on kill). If ally → processes combat BUT applies 15-min ban + -5 karma. If own faction → processes combat BUT applies 30-min ban + -10 karma. Uses existing `profiles.ban_until` pattern. |
| `get_active_combats()` | All PvP combats for player |
| `get_combat_state(session_id)` | Live tick display data |

---

## Phase 4: Vassalage RPCs

| RPC | Behavior |
|---|---|
| `start_subjugation(target_id)` | Creates `subjugation_timers` row |
| `resist_subjugation(liege_id)` | 1000 gold → -24 hours from timer |
| `attempt_rebellion()` | If 3+ days no attacks from liege → clear suzerain |
| `get_vassalage_info()` (updated) | Now includes subjugation timer data |

---

## Phase 5: Heartbeat Update

### Remove Resource Caps
- Replace all `LEAST(resource + gain, cap)` with unbounded `resource + gain`
- Delete cap computation CTEs (mana_cap, gold_cap, food_cap, heresy_cap, dogma_cap)
- Scale per-tick generation to 10x via dividing by 144 (was 1440)

### Add 3 New Phases

**Phase 6: Process Combat Ticks**
```
FOR each active combat_session:
  process_holy_war_tick() or process_pvp_tick()
  Handle victory/defeat/stalemate
  Log to akashic_logs
```

**Phase 7: Advance Subjugation Timers**
```
FOR each subjugation_timer with active combat:
  accumulated_hours += 1/60
  IF accumulated_hours >= 168: set suzerain_id
```

**Phase 8: Vassal Tithes + Liege Karma**
```
FOR each vassal relationship (once per day):
  Transfer 10% gold income to liege
  Award 5 karma to liege
```

---

## Phase 6-7: Frontend (for reference, not in SQL pass)

- `useEconomy.js`: Remove `manaCap`/`goldCap`/`foodCap` computed values
- `useSynod.js`: petition, browser, privacy toggle, custom message, applicant queue
- `useCombat.js` (new): PvP tick combat, NO faction filter on attack button
- `useHolyWar.js` (new): Text input for target synod name
- `AltarView.vue`: Remove `/{{ cap }}` display
- `SynodHallView.vue`: Tab swap (Synod/Synod Browser), custom message, stewards, applicants
- `SectSelectionModal.vue`: Filter to lowest-member factions only

---

## Implementation Order (SQL Pass: Phase 0-5)

1. Economy rebalance (UPDATE game_config, UPDATE shop_items)
2. Schema changes (ALTER synods, CREATE 4 tables, RLS)
3. Synod RPCs (create, petition, browser, applicants, stewards, faction balance)
4. Holy War RPCs (find by name, initiate, tick processing)
5. PvP RPCs (initiate with betrayal, tick processing)
6. Vassalage RPCs (subjugation, resistance, rebellion)
7. Heartbeat update (remove caps + 3 new phases)
8. GRANT EXECUTE on everything