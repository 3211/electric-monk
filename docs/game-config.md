# Game Config

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

All balance values live in `game_config` table. Change a row to rebalance — no code changes needed. Key categories:

- `building.*.mana_per_day`, `building.*.gold_per_day`, `building.*.food_per_day` — production rates
- `building.*.gold_upkeep_per_day`, `building.*.food_consumption_per_day` — upkeep
- `building.*.acre_cost` — sacred acres consumed
- `sect.*.*_multiplier` — faction modifiers
- `combat.pvp_*`, `combat.holy_war_*` — siege duration + tick costs
- `crusade.*`, `schism.*`, `plague.*`, `inquisition.*` — combat costs
- `tithe.percentage` — vassalage tax rate
- `vassalage.*` — subjugation timer hours, tribute cost, rebellion idle days
- `karma.milestone_*` — karma milestone tuning
- `synod.*` — guild config
- `tick.production_divisor` — per-day to per-minute conversion (currently 1440)
- `indulgence.*` — premium config
- `shop.cost_scaling_multiplier` — exponential building cost