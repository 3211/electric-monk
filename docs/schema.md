# Electric Monk — Database Schema

**Authority source:** Migration files in [`supabase/migrations/`](supabase/migrations/) (idempotent, run in lexicographic order to rebuild).
**Last updated:** 2026-05-19

---

## Migration History

| Series | Files | Status |
|--------|-------|--------|
| Genesis | `genesis_1` through `genesis_10` + `genesis_9_hotfix` | **CLOSED** (foundation) |
| Exodus | `exodus_0` through `exodus_7` + hotfixes `exodus_5_hotfix`, `exodus_6_hotfix` through `exodus_6_hotfix_7` | **ACTIVE** |

Run all `.sql` files in lexicographic order to rebuild the full database from scratch.

---

## Tables (25)

### `game_config`
Central balance values. Key-value store read by all RPCs and the cron heartbeat.

| Column | Type | Notes |
|--------|------|-------|
| `key` | TEXT PK | Dot-notation: `building.temple.mana_per_day` |
| `value` | NUMERIC | |
| `description` | TEXT | |
| `category` | TEXT DEFAULT 'production' | |
| `updated_at` | TIMESTAMPTZ | |

RLS: SELECT public.

---

### `profiles`
Player data. One row per auth user. Created by `create_profile_on_signup()` trigger on `auth.users` INSERT.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK → auth.users | |
| `email` | TEXT | |
| `username` | TEXT UNIQUE | Set via `change_username()` or onboarding |
| `faith` | TEXT | Free-text faith label |
| `ban_until` | TIMESTAMPTZ | Purgatory expiry (NULL = not banned) |
| `tokens_spent_today` | INT DEFAULT 0 | Devotion consumed today |
| `daily_token_limit` | INT DEFAULT 100 | Max devotion per day |
| `last_prayer_date` | DATE | |
| `karma` | INT DEFAULT 0 | Premium currency |
| `max_prayer_slots` | INT DEFAULT 1 | Concurrent prayer slots |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |
| `mana` | INT DEFAULT 0 | Resource: buildings generate |
| `gold` | INT DEFAULT 0 | Resource: workers generate |
| `food` | INT DEFAULT 0 | Resource: food estates generate |
| `suzerain_id` | UUID → profiles.id | Vassalage hierarchy |
| `heresy` | INT DEFAULT 0 | Dark research/combat currency |
| `schism_count` | INT DEFAULT 0 | Times declared schism |
| `divine_shield_until` | TIMESTAMPTZ | Schism protection expiry |
| `sect_type` | TEXT CHECK | `gilded_path`, `holy_way`, `final_watch`, `black_tribunal` |
| `sacred_acres` | INT DEFAULT 25 CHECK >= 0 | Land for buildings |
| `dogma` | INT DEFAULT 0 CHECK >= 0 | Light research currency |
| `indulgences` | INT DEFAULT 0 CHECK >= 0 | Premium currency (Stripe) |
| `synod_id` | UUID → synods.id | Alliance membership |
| `synod_role` | TEXT CHECK | `leader`, `officer`, `member`, NULL |
| `papal_bull_until` | TIMESTAMPTZ | 12h immunity |
| `title` | TEXT | Custom leaderboard title |
| `avatar_url` | TEXT | Custom avatar URL |
| `onboarding_complete` | BOOLEAN DEFAULT false | |
| `pfp_index` | INT DEFAULT 0 | Profile picture index |

RLS: SELECT own + purgatory users. INSERT own. UPDATE own.

---

### `shop_items`
Server-authoritative catalog. Seed data defines all purchasable items.

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | e.g. `altar`, `prayer-slot-2` |
| `category` | TEXT | `mana`, `food`, `workforce`, `infrastructure`, `catacombs`, `research` |
| `name` | TEXT | |
| `description` | TEXT | |
| `emoji_icon` | TEXT | |
| `karma_cost` | INT DEFAULT 0 | |
| `gold_cost` | INT DEFAULT 0 | |
| `heresy_cost` | INT DEFAULT 0 | |
| `effect_type` | TEXT | `add_building`, `add_prayer_slot` |
| `effect_data` | JSONB | e.g. `{"building_type": "altar"}` |
| `purchase_limit` | INT | NULL = unlimited |
| `requires_building` | TEXT | Prerequisite building type |
| `sort_order` | INT | |
| `is_active` | BOOLEAN DEFAULT true | |
| `cost_scaling` | BOOLEAN DEFAULT false | 1.15^owned exponential scaling |
| `acre_cost` | INT DEFAULT 0 CHECK >= 0 | Sacred acres consumed |
| `sect_restriction` | TEXT CHECK | Only this sect can buy |
| `sect_exclusion` | TEXT CHECK | This sect cannot buy |
| `created_at` | TIMESTAMPTZ | |

RLS: SELECT public.

---

### `prayers`
Prayer requests, altruistic prayers, and intercessory prayers.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `content` | TEXT | Original prayer text |
| `response_content` | TEXT | Monk's AI response |
| `is_rejected` | BOOLEAN DEFAULT false | |
| `rejection_reason` | TEXT | |
| `is_praying` | BOOLEAN DEFAULT false | Currently active |
| `is_archived` | BOOLEAN DEFAULT false | |
| `status` | TEXT DEFAULT 'pending' | |
| `prayer_count` | INT DEFAULT 0 | Cumulative pray cycles |
| `last_counted_at` | TIMESTAMPTZ | |
| `activated_at` | TIMESTAMPTZ | |
| `created_at` | TIMESTAMPTZ | |
| `karma_awarded` | INT DEFAULT 0 | Milestones already paid out |
| `source_prayer_id` | UUID → prayers.id | For altruistic prayers |
| `source_sinner_id` | UUID → profiles.id | For intercessory prayers |
| `prayer_type` | TEXT DEFAULT 'own' CHECK | `own`, `altruistic`, `intercessory` |

RLS: SELECT own + approved completed. INSERT own. UPDATE own.

---

### `indulgences`
Ad-view ban reduction records. 15 min per record.

| Column | Type |
|--------|------|
| `id` | UUID PK |
| `user_id` | UUID → profiles.id |
| `time_removed_seconds` | INT DEFAULT 900 |
| `created_at` | TIMESTAMPTZ |

RLS: INSERT own. SELECT own.

---

### `player_buildings`
Building ownership per player. Production rates come from `game_config`.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `building_type` | TEXT | `altar`, `shrine`, `temple`, `church`, `cathedral`, `pot`, `patch`, `garden`, `field`, `farm`, `novice`, `monk`, `cleric`, `bishop`, `cardinal`, `cultist`, `coven`, `scriptorium` |
| `is_active` | BOOLEAN DEFAULT true | False = ruined/disabled |
| `purchased_with` | TEXT | shop_items.id or `starting-X` |
| `purchased_at` | TIMESTAMPTZ | |

RLS: SELECT own.

---

### `akashic_logs`
Combat event history. Public read, insert via SECURITY DEFINER only.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `target_id` | UUID → profiles.id | |
| `actor_id` | UUID → profiles.id | NULL for anonymous (plague) |
| `action_type` | TEXT CHECK | `crusade`, `schism`, `plague`, `inquisition` |
| `result_data` | JSONB | |
| `created_at` | TIMESTAMPTZ | |

RLS: SELECT public.

---

### `blessing_types`
Blessing catalog for the Karma Shop.

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | `golden-light`, `holy-flame`, `dove-of-peace`, `divine-crown` |
| `emoji` | TEXT | |
| `name` | TEXT | |
| `description` | TEXT | |
| `karma_cost` | INT | |
| `karma_to_giver` | INT | Rebate |
| `karma_to_receiver` | INT | Awarded to prayer owner |
| `sort_order` | INT | |
| `is_active` | BOOLEAN DEFAULT true | |
| `shield_minutes` | INT | Divine Shield duration on bless |
| `created_at` | TIMESTAMPTZ | |

RLS: SELECT public.

---

### `prayer_blessings`
Junction: who blessed which prayer. UNIQUE(prayer_id, blessing_type_id, giver_id).

| Column | Type |
|--------|------|
| `id` | UUID PK |
| `prayer_id` | UUID → prayers.id |
| `blessing_type_id` | TEXT → blessing_types.id |
| `giver_id` | UUID → profiles.id |
| `receiver_id` | UUID → profiles.id |
| `created_at` | TIMESTAMPTZ |

RLS: SELECT public.

---

### `synods`
Player alliances (guilds).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `name` | TEXT UNIQUE | 3-30 chars |
| `leader_id` | UUID → profiles.id | |
| `tax_rate` | NUMERIC DEFAULT 0.05 | 0.01–0.15 |
| `vault_gold` | INT DEFAULT 0 | |
| `vault_mana` | INT DEFAULT 0 | |
| `created_at` | TIMESTAMPTZ | |

RLS: SELECT public. UPDATE leader only.

---

### `synod_wars`
Holy War declarations between synods. 48h duration.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `attacker_synod_id` | UUID → synods.id | |
| `defender_synod_id` | UUID → synods.id | |
| `declared_at` | TIMESTAMPTZ | |
| `expires_at` | TIMESTAMPTZ | |
| `is_active` | BOOLEAN DEFAULT true | |

RLS: SELECT public.

---

### `research_nodes`
Tech tree definition. 5 light + 4 dark nodes.

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | e.g. `tax_evasion` |
| `name` | TEXT | |
| `description` | TEXT | |
| `emoji_icon` | TEXT | |
| `alignment` | TEXT CHECK | `light`, `dark` |
| `cost` | INT CHECK > 0 | Dogma (light) or heresy (dark) |
| `effect_type` | TEXT | e.g. `vassal_tithe_reduction` |
| `effect_data` | JSONB | |
| `requires_node` | TEXT → research_nodes.id | Prerequisite |
| `sort_order` | INT | |
| `is_active` | BOOLEAN DEFAULT true | |

RLS: SELECT public.

---

### `player_research`
Unlocked tech per player. UNIQUE(user_id, node_id).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `node_id` | TEXT → research_nodes.id | |
| `unlocked_at` | TIMESTAMPTZ | |
| `expires_at` | TIMESTAMPTZ | NULL = permanent |

RLS: SELECT own.

---

### `relics`
10 global unique items. Seeded once, holder changes via theft.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `name` | TEXT UNIQUE | |
| `description` | TEXT | |
| `emoji_icon` | TEXT | |
| `effect_type` | TEXT | e.g. `mana_double` |
| `effect_data` | JSONB | e.g. `{"mana_multiplier": 2.0}` |
| `holder_id` | UUID → profiles.id | NULL = unclaimed |
| `last_stolen_at` | TIMESTAMPTZ | |
| `steal_progress` | INT DEFAULT 0 | |
| `steal_window_start` | TIMESTAMPTZ | |
| `is_active` | BOOLEAN DEFAULT true | |

RLS: SELECT public.

---

### `active_miracles`
Timed effect tracking (Papal Bull, Divine Architect, blessing shields).

| Column | Type |
|--------|------|
| `id` | UUID PK |
| `user_id` | UUID → profiles.id |
| `miracle_type` | TEXT |
| `effect_data` | JSONB |
| `expires_at` | TIMESTAMPTZ |
| `created_at` | TIMESTAMPTZ |

RLS: SELECT public.

---

### `build_queue`
Divine Architect auto-build queue. Max 5 pending per user.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `item_id` | TEXT → shop_items.id | |
| `queued_at` | TIMESTAMPTZ | |
| `auto_execute` | BOOLEAN DEFAULT true | |
| `executed_at` | TIMESTAMPTZ | NULL = pending |

RLS: SELECT own.

---

### `faction_relationships`
Per-faction enemy/ally/neutral config. Created by [`exodus_0.sql`](supabase/migrations/exodus_0.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `sect_key` | TEXT UNIQUE CHECK | `gilded_path`, `holy_way`, `final_watch`, `black_tribunal` |
| `enemy_sect` | TEXT CHECK | |
| `ally_sect` | TEXT CHECK | |
| `neutral_sect` | TEXT CHECK | |
| `rationale_enemy` | TEXT | |
| `rationale_ally` | TEXT | |
| `rationale_neutral` | TEXT | |

RLS: SELECT public.

---

### `combat_sessions`
Tick-based PvP and Holy War combat. Created by [`exodus_1.sql`](supabase/migrations/exodus_1.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `combat_type` | TEXT CHECK | `pvp` or `holy_war` |
| `attacker_id` | UUID → profiles.id | |
| `defender_id` | UUID → profiles.id | |
| `attacker_synod_id` | UUID → synods.id | NULL for PvP |
| `defender_synod_id` | UUID → synods.id | NULL for PvP |
| `ticks_total` | INT | Total ticks (4320 = 3d PvP, 10080 = 7d HW) |
| `ticks_remaining` | INT | Ticks left until stalemate |
| `attacker_mana` | INT | HP pool for attacker |
| `defender_mana` | INT | HP pool for defender |
| `attacker_workers` | INT | DPS per tick for attacker |
| `defender_workers` | INT | DPS per tick for defender (0 for HW) |
| `gold_stolen` | INT DEFAULT 0 | Cumulative gold leeched |
| `gold_spent` | INT DEFAULT 0 | Cumulative gold spent on ticks |
| `started_at` | TIMESTAMPTZ | |
| `last_tick_at` | TIMESTAMPTZ | Last heartbeat tick |
| `is_active` | BOOLEAN DEFAULT true | |
| `result` | TEXT CHECK | `attacker_win`, `defender_win`, `stalemate` |

RLS: Participants can view. Synod members can view holy wars.

---

### `subjugation_timers`
168-hour vassalage countdown. Created by [`exodus_1.sql`](supabase/migrations/exodus_1.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `liege_id` | UUID → profiles.id | |
| `vassal_id` | UUID → profiles.id | |
| `accumulated_hours` | NUMERIC DEFAULT 0 | At 168, target becomes vassal |
| `last_attack_at` | TIMESTAMPTZ | |
| `created_at` | TIMESTAMPTZ | |

UNIQUE(liege_id, vassal_id). RLS: Participants can view.

---

### `synod_applicants`
Petition queue for joining synods. Created by [`exodus_1.sql`](supabase/migrations/exodus_1.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `synod_id` | UUID → synods.id | |
| `created_at` | TIMESTAMPTZ | |

RLS: Users see own applications. Synod leaders/officers see apps to their synod.

---

### `pending_bans`
Deferred ban application queue. Created by [`exodus_2.sql`](supabase/migrations/exodus_2.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `ban_until` | TIMESTAMPTZ | |
| `ban_reason` | TEXT | |
| `applied` | BOOLEAN DEFAULT false | |
| `created_at` | TIMESTAMPTZ | |

---

### `shouts`
Social messages filtered through the Town Crier. Created by [`exodus_6.sql`](supabase/migrations/exodus_6.sql), updated by [`exodus_6_hotfix_7.sql`](supabase/migrations/exodus_6_hotfix_7.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `content` | TEXT | Original user text |
| `crier_content` | TEXT | Town Crier translated text |
| `context` | TEXT CHECK | `global` or `synod` |
| `synod_id` | UUID → synods.id | NULL for global shouts |
| `sect_type` | TEXT CHECK | Set for global shouts (sect filtering) |
| `is_sect_only` | BOOLEAN NOT NULL DEFAULT false | If true, global shouts only visible to same sect |
| `status` | TEXT CHECK | `pending`, `posted`, `failed` |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

RLS: SELECT public. INSERT own. No UPDATE/DELETE (permanent record). Service role: SELECT, UPDATE (Town Crier writes `crier_content` + `status`).

---

### `shout_replies`
Threaded replies to shouts. Created by [`exodus_6.sql`](supabase/migrations/exodus_6.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `shout_id` | UUID → shouts.id | |
| `user_id` | UUID → profiles.id | |
| `content` | TEXT | Original user text |
| `crier_content` | TEXT | Town Crier translated text |
| `status` | TEXT CHECK | `pending`, `posted`, `failed` |
| `created_at` | TIMESTAMPTZ | |

RLS: SELECT public. INSERT own. No UPDATE/DELETE (permanent record). Service role: SELECT, UPDATE (Town Crier writes `crier_content` + `status`).

---

### `shout_blessings`
Blessings placed on shouts or replies. Reuses `blessing_types`. Created by [`exodus_6.sql`](supabase/migrations/exodus_6.sql).

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `shout_id` | UUID → shouts.id | |
| `reply_id` | UUID → shout_replies.id | NULL for shout-level blessing |
| `blessing_type_id` | TEXT → blessing_types.id | |
| `giver_id` | UUID → profiles.id | |
| `receiver_id` | UUID → profiles.id | |
| `created_at` | TIMESTAMPTZ | |

UNIQUE(shout_id, COALESCE(reply_id, nil), blessing_type_id, giver_id). RLS: SELECT public. INSERT own.

---

## RPC Functions

### Prayer Management
| Function | Returns | Notes |
|----------|---------|-------|
| `submit_prayer(TEXT)` | JSONB | Slot-aware FIFO, deducts devotion |
| `activate_prayer(UUID)` | JSONB | Slot-aware, deactivates oldest if full |
| `deactivate_prayer(UUID, INT)` | JSONB | Final sync + karma milestone check |
| `sync_prayer_count(UUID)` | JSONB | Read-only poll |
| `sync_prayer_count(UUID, INT)` | JSONB | Full sync + ban reduction for intercessory |
| `start_altruistic_prayer(UUID, TEXT)` | JSONB | Slot-aware |
| `start_intercessory_prayer(UUID, TEXT)` | JSONB | Slot-aware |
| `get_public_prayers(INT, INT, TEXT)` | JSONB | Paginated, sortable, includes blessings |
| `get_sinners()` | JSONB | Users in purgatory |
| `get_intercessory_prayer_count(UUID)` | INT | |

### Economy & Shop
| Function | Returns | Notes |
|----------|---------|-------|
| `purchase_shop_item(TEXT)` | JSONB | v3: acre validation + sect restrictions + cost scaling |
| `get_player_economy()` | JSONB | Full economy state + buildings + production + vassalage + synod + relics |
| `get_leaderboard(INT, INT)` | JSONB | Top N by karma |
| `get_leaderboard_by_faith(TEXT, INT, INT)` | JSONB | Faith-filtered rankings |
| `get_user_ranks()` | JSONB | Current user's global + faith rank |
| `purchase_prayer_slot()` | JSONB | Legacy slot purchase |
| `refill_tokens(INT)` | INT | |

### Sects
| Function | Returns | Notes |
|----------|---------|-------|
| `choose_sect(TEXT)` | JSONB | One-time, permanent |
| `get_sect_info()` | JSONB | Sect modifiers from game_config |

### Vassalage & Combat
| Function | Returns | Notes |
|----------|---------|-------|
| `get_vassalage_info()` | JSONB | Suzerain, vassals, tithes, chain depth, subjugation timers |
| `initiate_combat(UUID)` | JSONB | Exodus 5: tick-based siege (3-day PvP, 7-day HW). Workers=DPS, mana=HP |
| `get_active_combats()` | JSONB | All active PvP sieges for current player |
| `cancel_combat(UUID)` | JSONB | Exodus 5: attacker withdraws at 50% remaining gold + -5 karma |
| `surrender_combat(UUID)` | JSONB | Exodus 5: defender gives up, becomes vassal (PvP) or synod destroyed (HW) |
| `initiate_holy_war(UUID)` | JSONB | Synod leader only. Sums all members' mana + workers for siege |
| `get_active_holy_wars()` | JSONB | All active Holy Wars for player's synod |
| `process_holy_war_tick(UUID)` | JSONB | Called by heartbeat. Damage, attrition, leech per tick |
| `vanquish_synod(UUID, UUID)` | JSONB | Destroy defeated synod, scatter members, transfer relics, loot gold |
| `start_subjugation(UUID)` | JSONB | Start/advance 168-hour subjugation timer against target |
| `resist_subjugation(UUID)` | JSONB | Pay 1000 Gold -> reduce subjugation timer by 24 hours |
| `attempt_rebellion()` | JSONB | Break free if liege hasn't attacked in 3+ days |
| `launch_crusade(UUID)` | JSONB | **DEPRECATED** -- use initiate_combat. Instant dice-roll with acre theft |
| `declare_schism()` | JSONB | Escalating heresy cost, 24h shield |
| `cast_plague(UUID)` | JSONB | Zeroes target food (anonymous, costs heresy) |
| `launch_inquisition(UUID)` | JSONB | Reveals heresy + miracles, assassinates worker |
| `get_akashic_logs(INT, INT)` | JSONB | Paginated combat logs |
| `lookup_player(TEXT)` | JSONB | Find user by username for targeting |

### Synods
| Function | Returns | Notes |
|----------|---------|-------|
| `create_synod(TEXT)` | JSONB | Costs gold, sets sect_key from founder's faction |
| `join_synod(UUID)` | JSONB | Faction-gated via petition/approval |
| `leave_synod()` | JSONB | Promotes oldest member if leader |
| `initiate_holy_war(UUID)` | JSONB | Synod leader only. Exodus 5: 7-day siege, per-tick combat |
| `find_synod_by_name(TEXT)` | JSONB | Exact name match for war targeting |
| `get_synod_info()` | JSONB | Full synod state with members, roles, wars, relics, applicants |
| `promote_member(UUID)` | JSONB | Leader -> officer |
| `demote_member(UUID)` | JSONB | Officer -> member |
| `kick_member(UUID)` | JSONB | Remove from synod |

### Research
| Function | Returns | Notes |
|----------|---------|-------|
| `research_tech(TEXT)` | JSONB | Deducts dogma/heresy, applies immediate effects |
| `get_research_tree()` | JSONB | All nodes + user unlocks |

### Relics
| Function | Returns | Notes |
|----------|---------|-------|
| `get_relics()` | JSONB | All 10 relics with holder info |
| `attempt_relic_steal(UUID)` | JSONB | Synod-coordinated theft |
| `get_synod_relics()` | JSONB | Relics held by synod members |

### Indulgences
| Function | Returns | Notes |
|----------|---------|-------|
| `consume_indulgence(TEXT)` | JSONB | `papal_bull` or `divine_architect` |

### Social Messaging (Shouts)
| Function | Returns | Notes |
|----------|---------|-------|
| `submit_shout(TEXT, TEXT, BOOLEAN)` | JSONB | Post a shout. Deducts gold (100 global, 50 vault for leaders, 100 personal for members). Creates pending row. Third param: `is_sect_only` (default false). |
| `submit_shout_reply(UUID, TEXT)` | JSONB | Reply to a shout. Deducts 50 gold. Creates pending row. |
| `get_shouts(INT, INT, TEXT)` | JSONB | Paginated shout feed. Filter: `global`, `sect`, `synod`. Global feed respects `is_sect_only` visibility. Includes author info + blessings + reply count. |
| `get_shout_replies(UUID, INT, INT)` | JSONB | Shout detail with paginated replies + blessing aggregates. |
| `grant_shout_blessing(UUID, TEXT, UUID)` | JSONB | Bless a shout or reply. Deducts karma, awards rebate + receiver karma, grants Divine Shield. |
| `get_shout_blessings(UUID[])` | JSONB | Batch blessing aggregates for multiple shouts. |

### Blessings
| Function | Returns | Notes |
|----------|---------|-------|
| `grant_blessing(UUID, TEXT)` | JSONB | Atomic: deducts karma, awards rebate, gives shields |
| `get_prayer_blessings(UUID[])` | JSONB | Batch blessing aggregates |

### Identity
| Function | Returns | Notes |
|----------|---------|-------|
| `change_username(TEXT)` | JSONB | Username change with cooldown |

### Factions
| Function | Returns | Notes |
|----------|---------|-------|
| `get_factions_overview()` | JSONB | All four factions with member counts, top-5, relationships, modifiers, missions |

### Core Utilities
| Function | Returns |
|----------|---------|
| `update_karma(UUID, INT)` | VOID |
| `reset_daily_prayer_count(UUID)` | VOID |
| `reduce_ban_time(UUID)` | INTERVAL |

### Cron Heartbeat
| Function | Returns | Schedule |
|----------|---------|----------|
| `calculate_automated_karma()` | VOID | Every minute (`prayer-heartbeat`) |

9 phases: (1) karma milestones, (2) resource generation + sect/relic bonuses + tithes, (3) synod vault deposits, (4) expire timed effects, (5) Divine Architect queue, (6) combat ticks (PvP + Holy War), (7) subjugation timer advance, (8) vassal tithes + liege karma, (9) apply pending bans.

---

## Triggers

| Trigger | On | Function |
|---------|-----|----------|
| `on_auth_user_created` | `auth.users` INSERT | `create_profile_on_signup()` — creates profile + starting buildings (altar, pot, novice) |

---

## Extensions

| Extension | Purpose |
|-----------|---------|
| `pg_cron` | Schedules `calculate_automated_karma()` every minute |
| `pg_net` | HTTP calls from Postgres (future use) |

---

## Edge Functions

| Function | Purpose |
|----------|---------|
| `process-prayer` | Venice AI prayer validation + response generation |
| `pray-for-sinner` | AI-generated intercessory prayer for purgatory users |
| `generate-onboarding-content` | AI-generated welcome message + faction intro + first prayer prompt |
| `town-crier` | Faction-appropriate message translation for shouts/replies. Accepts `shout_id` or `reply_id` to update DB. Soft-censors slurs/threats/doxxing. |