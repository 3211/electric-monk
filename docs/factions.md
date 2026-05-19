# Factions (Sects)

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

Four one-time-choice factions with asymmetric modifiers:

| Faction | Sect Key | Bonus | Penalty |
|---------|----------|-------|---------|
| Gilded Path | `gilded_path` | +50% Gold | -20% Mana, +100% Cathedral upkeep |
| Holy Way | `holy_way` | +20% Mana, -50% Food consumption | Max building tier 2 |
| Final Watch | `final_watch` | +50% Food, +50% Crusade defense | -25% Gold |
| Black Tribunal | `black_tribunal` | +100% Heresy, -50% Inquisition cost | -30% Mana |

## Faction Relationships

(stored in `faction_relationships`)

- Gilded Path: enemy=Black Tribunal, ally=Holy Way, neutral=Final Watch
- Holy Way: enemy=Final Watch, ally=Gilded Path, neutral=Black Tribunal
- Final Watch: enemy=Holy Way, ally=Black Tribunal, neutral=Gilded Path
- Black Tribunal: enemy=Gilded Path, ally=Final Watch, neutral=Holy Way