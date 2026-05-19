# Prayer System

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

## Core Mechanics

- **Devotion**: Daily budget (`daily_token_limit`), consumed at 5 chars = 1 devotion
- **Slots**: Up to 5 concurrent prayer slots (purchasable via shop)
- **FIFO**: When all slots full, oldest prayer deactivates
- **Counting**: Client-side counter syncs to server every ~10s via `sync_prayer_count`. Cycle time = response length * 200ms, clamped 15s–3min
- **Karma milestones**: Every 50 pray cycles = 1 milestone. Own: +5 karma, Altruistic: +10 karma, Intercessory: +5 karma
- **Intercessory**: Each pray cycle reduces sinner's ban by 1 minute. Full redemption grants +5 bonus karma

## Akashic Records

Two sub-tabs:
- **Prayers**: All approved completed prayers, sortable by newest/most_prayed, paginated. Shows blessing badges
- **Sinners**: Users in purgatory with rejection reason, live countdown. Players can pray intercessorially to reduce ban time

## Ban System

Rejected prayers by Venice AI → karma -1 + ban. Ban duration scales with rejection severity. Indulgences (ad views) reduce ban by 15 min each. Intercessory prayers from other players reduce ban by 1 min per cycle.