# Genesis Series — CLOSED

**Date:** 2026-05-18  
**Status:** The Genesis migration series is **closed and complete**.

## Scope

Genesis is the **foundation** of the Electric Monk database. Running all Genesis files in order rebuilds the entire game database from scratch.

## Files

| File | Purpose |
|------|---------|
| `genesis_1.sql` | Tables (16), indexes, RLS policies, seed data, core prayer functions |
| `genesis_2.sql` | All game RPCs: sects, synods, research, relics, combat, economy, vassalage, blessings |
| `genesis_3.sql` | `calculate_automated_karma()` — 5-phase cron heartbeat |
| `genesis_4.sql` | Trigger (`create_profile_on_signup`), all GRANTs, cron scheduling |
| `genesis_5.sql` | Permission fix: GRANT SELECT/INSERT/UPDATE on prayers, profiles, indulgences |
| `genesis_6.sql` | Sect rename (custom keys), PFP column, username uniqueness, `change_username` |
| `genesis_7.sql` | Blessing shield buff system: shields on bless, `shield_minutes` column |
| `genesis_8.sql` | `lookup_player`, shield checks in `cast_plague`, newbie protection shield |
| `genesis_9.sql` | Synod roles (leader/officer/member), promote/demote/kick, synod-wide relic buffs |
| `genesis_9_hotfix.sql` | Resilient `get_player_economy()` — wraps `get_synod_relics()` in try/catch |
| `genesis_10.sql` | Faith-filtered leaderboard: `get_leaderboard_by_faith`, `get_user_ranks` |

## Chronology

Genesis is **closed**. All future migrations use the **Exodus** naming convention:

```
exodus_0.sql   (already exists — faction relationships)
exodus_1.sql   (next migration)
exodus_2.sql   ...
```

To rebuild the database: run all `.sql` files in `supabase/migrations/` in lexicographic order.

## Genesis is the Foundation

Genesis is not obsolete — it is the bedrock. Every Exodus migration builds on top of Genesis tables, functions, and seed data. The closure marker indicates that no new Genesis files will be created; the series is complete.