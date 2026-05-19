# Cron Heartbeat

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

Runs every minute (`prayer-heartbeat`). 9 phases:

1. Karma milestones for active prayers
2. Resource generation (per-minute = daily_rate / 1440, min 1) with sect modifiers, relic bonuses, tithe siphoning
3. Synod tax collection → vault deposits
4. Expire timed effects (miracles, research, holy wars, papal bulls, divine shields)
5. Process Divine Architect build queue
6. **Combat ticks** — Process all active PvP and Holy War combat_sessions. Live re-reads of mana/workers/gold each tick. Apply damage, leech, attrition, exertion. Check victory conditions.
7. **Subjugation timer advance** — +1/60th hour per active combat minute. Auto-vassalize at 168 hours.
8. **Vassal tithes + liege karma** — Transfer gold tithes from vassals to lieges each tick. Award fractional daily karma.
9. Apply pending bans from betrayal/vanquish events