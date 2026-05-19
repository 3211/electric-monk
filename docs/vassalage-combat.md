# Vassalage & Combat

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

## Vassalage

- Pyramid hierarchy: suzerain → vassal → sub-vassal
- Suzerain receives 10% tithe of vassal's gross resource generation
- Circular vassalage prevented (recursive chain check)
- 168-hour subjugation system: active sieges accumulate hours toward forced vassaldom
- Resist (1000 Gold → -24h) and Rebel (3+ idle days → break free) mechanics
- `get_vassalage_info()` returns suzerain, vassals, tithes, subjugation timers

## Combat (Exodus 5 — Tick-Based Siege)

All 1v1 PvP uses [`initiate_combat`](../supabase/migrations/exodus_5.sql) — tick-based siege combat:

- **Initiation**: 50 Gold. Creates `combat_sessions` row.
- **Duration**: PvP = 3 days (4,320 ticks), Holy War = 7 days (10,080 ticks). One tick per minute via heartbeat.
- **Damage**: Attacker workers = DPS per tick against defender's mana pool (HP). Defender workers counter-attack.
- **Gold economy**: 0.5% leech per tick (PvP), 0.2% (HW). Tick cost: 2 gold/min (PvP), 10 gold/min (HW).
- **Victory**: Attacker wins when defender mana ≤ 0 → vassaldom. Defender wins when attacker mana ≤ 0 or can't pay tick cost. Stalemate when ticks exhausted.
- **Vanquish** (Holy War attacker win): Defender synod destroyed. Members scattered + 5-min ban. Relics transferred to attacker leader. 20% gold looted, distributed weighted by workers.
- **Cancel** (`cancel_combat`): Attacker pays 50% of remaining tick gold + -5 karma to withdraw.
- **Surrender** (`surrender_combat`): Defender immediately becomes vassal (PvP) or synod vanquished (HW).
- **One-at-a-time**: `active_combat_target_id` column prevents multiple simultaneous attacks.

## Deprecated Combat

- **`launch_crusade`** (Genesis-era): Instant dice-roll, 50 mana cost, mana+clerics attack power. Still in DB but no Vue calls it. Use `initiate_combat` instead.

## Other Combat Actions

- **Schism** (`declare_schism`): Costs escalating heresy (base 100 × 2^count). Breaks vassalage. Grants 24h Divine Shield.
- **Plague** (`cast_plague`): Costs 75 heresy. Zeroes target's food. Anonymous. Blocked by Divine Shield, Papal Bull, Sacred Firewall relic.
- **Inquisition** (`launch_inquisition`): Costs 200 gold. Reveals target's exact heresy + miracles. Assassinates highest-tier worker.