# Electric Monk — Internal Documentation

**For:** AI agents and developers  
**Last updated:** 2026-05-18  

---

## Project

Holy War Online (Formerly Electric Monk) is a theological PBBG (Persistent Browser-Based Game) built with Vue 3 + Supabase. Players choose a faction, build an economy, wage asymmetric war, research tech, join synods, steal relics, and pray to generate karma.

**Tech stack:** Vue 3 (Vite), Supabase (PostgreSQL + Auth + Edge Functions), Venice AI (prayer processing), Tailwind CSS.

---

## File-to-Feature Map

### Views → What They Render

| View | Route/Tab | Purpose |
|------|-----------|---------|
| [`LoginView.vue`](src/views/LoginView.vue) | Unauthenticated | Google OAuth + email/password signup/login |
| [`AltarView.vue`](src/views/AltarView.vue) | "Altar" tab | Main prayer interface — submit, cycle prayers, resource bar |
| [`AkashicRecordsView.vue`](src/views/AkashicRecordsView.vue) | "Records" tab | Public prayer feed + sinners list, altruistic/intercessory praying |
| [`FactionsView.vue`](src/views/FactionsView.vue) | "Factions" tab | Diamond layout showing 4 factions + relationships |
| [`VaticanView.vue`](src/views/VaticanView.vue) | "Vatican" tab | Vassalage management + crusade targeting + combat log |
| [`SynodHallView.vue`](src/views/SynodHallView.vue) | "Synod Hall" tab | Guild management, members, vault, holy war |
| [`ScriptoriumView.vue`](src/views/ScriptoriumView.vue) | "Scriptorium" tab | Light/dark tech tree with prerequisite lines |
| [`KarmaShopView.vue`](src/views/KarmaShopView.vue) | "Shop" tab | Real Estate, Workforce, Blessings, Infrastructure tabs |
| [`ReliquaryView.vue`](src/views/ReliquaryView.vue) | "Reliquary" tab | 10 global relics with holders + steal progress |
| [`LeaderboardView.vue`](src/views/LeaderboardView.vue) | "Rankings" tab | Faith-filtered leaderboard |
| [`CatacombsView.vue`](src/views/CatacombsView.vue) | "Catacombs" tab | Heresy economy: cultists, covens, schism, plague |
| [`PurgatoryView.vue`](src/views/PurgatoryView.vue) | Banned-only overlay | Ban timer + indulgence ad reduction |

**Nav order:** altar → records → factions → vatican → synod → scriptorium → shop → rankings

### Composables → What They Manage

| Composable | Supabase Tables | Key RPCs Used |
|------------|----------------|---------------|
| [`useAuth.js`](src/composables/useAuth.js) | auth.users, profiles | Supabase Auth |
| [`usePrayers.js`](src/composables/usePrayers.js) | prayers, profiles | `submit_prayer`, `sync_prayer_count`, `activate_prayer`, `deactivate_prayer` |
| [`usePrayerCounter.js`](src/composables/usePrayerCounter.js) | prayers | Client-side counting with server sync |
| [`useAkashicRecords.js`](src/composables/useAkashicRecords.js) | prayers, profiles | `get_public_prayers`, `get_sinners`, `start_altruistic_prayer`, `start_intercessory_prayer` |
| [`useEconomy.js`](src/composables/useEconomy.js) | profiles, player_buildings, game_config | `get_player_economy` |
| [`useShop.js`](src/composables/useShop.js) | shop_items, player_buildings, profiles | `purchase_shop_item` |
| [`useKarmaShop.js`](src/composables/useKarmaShop.js) | blessing_types, prayer_blessings | `grant_blessing` |
| [`useBlessings.js`](src/composables/useBlessings.js) | blessing_types, prayer_blessings | `get_prayer_blessings` |
| [`useFactions.js`](src/composables/useFactions.js) | faction_relationships, profiles | `get_factions_overview` |
| [`useSects.js`](src/composables/useSects.js) | profiles, game_config | `choose_sect`, `get_sect_info` |
| [`useSynod.js`](src/composables/useSynod.js) | synods, synod_wars, profiles | `create_synod`, `join_synod`, `leave_synod`, `declare_holy_war`, `get_synod_info`, promote/demote/kick |
| [`useVassalage.js`](src/composables/useVassalage.js) | profiles, akashic_logs | `get_vassalage_info`, `launch_crusade`, `declare_schism`, `cast_plague`, `get_akashic_logs`, `lookup_player` |
| [`useCatacombs.js`](src/composables/useCatacombs.js) | profiles, player_buildings | Heresy economy display |
| [`useInquisition.js`](src/composables/useInquisition.js) | profiles, akashic_logs | `launch_inquisition` |
| [`useResearch.js`](src/composables/useResearch.js) | research_nodes, player_research, profiles | `research_tech`, `get_research_tree` |
| [`useRelics.js`](src/composables/useRelics.js) | relics | `get_relics`, `attempt_relic_steal` |
| [`useIndulgences.js`](src/composables/useIndulgences.js) | profiles, active_miracles | `consume_indulgence` |
| [`useLeaderboard.js`](src/composables/useLeaderboard.js) | profiles | `get_leaderboard_by_faith`, `get_user_ranks` |
| [`useOnboarding.js`](src/composables/useOnboarding.js) | profiles | `choose_sect`, `change_username` |
| [`useBanTimer.js`](src/composables/useBanTimer.js) | profiles, indulgences | `reduce_ban_time` |

### Components → What They Render

| Component | Type | Purpose |
|-----------|------|---------|
| [`OnboardingWizard.vue`](src/components/organisms/OnboardingWizard.vue) | Organism | 4-step onboarding: AI welcome → identity → faction intro → first prayer |
| [`SectSelectionModal.vue`](src/components/organisms/SectSelectionModal.vue) | Organism | Faction picker with lore + modifiers |
| [`AkashicPrayerCard.vue`](src/components/organisms/AkashicPrayerCard.vue) | Organism | Public prayer card with blessing badges |
| [`SinnerCard.vue`](src/components/organisms/SinnerCard.vue) | Organism | Purgatory user card with countdown |
| [`BlessingPicker.vue`](src/components/organisms/BlessingPicker.vue) | Organism | Modal to select + grant a blessing |
| [`BlessingDetailModal.vue`](src/components/organisms/BlessingDetailModal.vue) | Organism | Full blessing breakdown popup |
| [`PrayerHistoryModal.vue`](src/components/organisms/PrayerHistoryModal.vue) | Organism | User's prayer history |
| [`UsernameChangeModal.vue`](src/components/organisms/UsernameChangeModal.vue) | Organism | Username change with cooldown |
| [`BlessingBadgeBar.vue`](src/components/molecules/BlessingBadgeBar.vue) | Molecule | Emoji badge bar with overflow |
| [`KarmaToast.vue`](src/components/molecules/KarmaToast.vue) | Molecule | Karma milestone notification |
| [`MiracleBuffBar.vue`](src/components/molecules/MiracleBuffBar.vue) | Molecule | Active miracle indicators |
| [`ShieldTimer.vue`](src/components/molecules/ShieldTimer.vue) | Molecule | Divine shield countdown |

### Edge Functions

| Function | Trigger | Purpose |
|----------|---------|---------|
| `process-prayer` | Prayer submitted | Venice AI validates + responds. Applies karma (+1 approved / -1 rejected), bans on rejection |
| `pray-for-sinner` | Intercessory prayer started | Venice AI generates intercessory prayer text for the sinner |
| `generate-onboarding-content` | Onboarding steps | AI-generated welcome message, faction intro, prayer suggestion |

---

## Game Systems

### Onboarding Flow
1. User signs up → `onboarding_complete` = false
2. AI-generated welcome message displayed
3. User picks username + faction (one-time permanent choice via `choose_sect`)
4. `onboarding_complete` set to true **immediately** after identity step (prevents dropout loop)
5. If user continues: AI-generated faction intro + prayer prompt shown
6. First prayer submitted with `is_onboarding=true` — rejected prayers during onboarding do NOT ban

### Prayer System
- **Devotion**: Daily budget (`daily_token_limit`), consumed at 5 chars = 1 devotion
- **Slots**: Up to 5 concurrent prayer slots (purchasable via shop)
- **FIFO**: When all slots full, oldest prayer deactivates
- **Counting**: Client-side counter syncs to server every ~10s via `sync_prayer_count`. Cycle time = response length * 200ms, clamped 15s–3min
- **Karma milestones**: Every 50 pray cycles = 1 milestone. Own: +5 karma, Altruistic: +10 karma, Intercessory: +5 karma
- **Intercessory**: Each pray cycle reduces sinner's ban by 1 minute. Full redemption grants +5 bonus karma

### Economy (4 Resources)
- **Karma**: Premium currency. Earned via prayer milestones, approved prayers. Spent in shop + blessings
- **Mana**: Generated by mana estates (altar/shrine/temple/church/cathedral). Used for crusades. Capped at 10x daily rate
- **Gold**: Generated by workforce (novice/monk/cleric/bishop/cardinal). Pays building upkeep. Capped at 10x daily rate
- **Food**: Generated by food estates (pot/patch/garden/field/farm). Consumed by workforce. Capped at 10x daily rate
- **Heresy**: Dark currency. Generated by cultists. Cap = base (100) + coven bonus (50 each). Used for schism, plague, dark research
- **Dogma**: Light currency. Generated by scriptoriums. Capped at 10x daily rate. Used for light research
- **Sacred Acres**: Finite land (starting 25). Buildings consume acres. Stolen via crusade. If over capacity: LIFO ruin
- **Indulgences**: Premium currency purchased via Stripe. Spent on Papal Bull, Divine Architect, titles, avatars
- **Building cost scaling**: Each additional building of same type costs 1.15× more (exponential)

### Starting Assets
New signups receive: altar (mana), pot (food), novice (gold), 25 sacred acres, 100 daily devotion.

### Karma Shop Tabs
1. **Real Estate**: Mana estates (altar → shrine → temple → church → cathedral) and Food estates (pot → patch → garden → field → farm)
2. **Workforce**: Gold generators (novice → monk → cleric → bishop → cardinal)
3. **Blessings**: 4 blessing types purchasable to place on public prayers
4. **Infrastructure**: Prayer slots 2-5 (+100 devotion each)
5. **Catacombs**: Cultists (heresy generation) and Covens (heresy cap increase)
6. **Research**: Scriptorium (dogma generation)

### Blessings
4 types purchased with karma, placed on others' prayers:
- **Golden Light** (✨): Cost 10, giver gets +1, receiver gets +5
- **Holy Flame** (🔥): Cost 25, giver gets +2, receiver gets +10
- **Dove of Peace** (🕊️): Cost 50, giver gets +5, receiver gets +20
- **Divine Crown** (👑): Cost 100, giver gets +10, receiver gets +50

Blessings grant Divine Shield protection to both giver and receiver (duration = karma cost × shield_minutes_per_karma from game_config).

### Akashic Records
Two sub-tabs:
- **Prayers**: All approved completed prayers, sortable by newest/most_prayed, paginated. Shows blessing badges
- **Sinners**: Users in purgatory with rejection reason, live countdown. Players can pray intercessorially to reduce ban time

### Factions (Sects)
Four one-time-choice factions with asymmetric modifiers:

| Faction | Sect Key | Bonus | Penalty |
|---------|----------|-------|---------|
| Gilded Path | `gilded_path` | +50% Gold | -20% Mana, +100% Cathedral upkeep |
| Holy Way | `holy_way` | +20% Mana, -50% Food consumption | Max building tier 2 |
| Final Watch | `final_watch` | +50% Food, +50% Crusade defense | -25% Gold |
| Black Tribunal | `black_tribunal` | +100% Heresy, -50% Inquisition cost | -30% Mana |

Faction relationships (stored in `faction_relationships`):
- Gilded Path: enemy=Black Tribunal, ally=Holy Way, neutral=Final Watch
- Holy Way: enemy=Final Watch, ally=Gilded Path, neutral=Black Tribunal
- Final Watch: enemy=Holy Way, ally=Black Tribunal, neutral=Gilded Path
- Black Tribunal: enemy=Gilded Path, ally=Final Watch, neutral=Holy Way

### Vassalage
- Pyramid hierarchy: suzerain → vassal → sub-vassal
- Suzerain receives 10% tithe of vassal's gross resource generation
- Circular vassalage prevented (recursive chain check)
- `get_player_economy` returns suzerain info, vassal list, daily tithe estimates

### Combat (4 RPCs)
- **Crusade** (`launch_crusade`): Costs 50 mana. Attack power = mana + clerics. Defense = churches + cathedrals. On success: target becomes vassal, N sacred acres stolen (default 3), LIFO ruin on defender. Checks: Divine Shield, Papal Bull, Holy War bonus (+20%), sect bonuses, relic bonuses, research bonuses.
- **Schism** (`declare_schism`): Costs escalating heresy (base 100 × 2^count). Breaks vassalage. Grants 24h Divine Shield immunity.
- **Plague** (`cast_plague`): Costs 75 heresy. Zeroes target's food. Anonymous (actor_id = NULL). Blocked by Divine Shield, Papal Bull, Sacred Firewall relic.
- **Inquisition** (`launch_inquisition`): Costs 200 gold (×0.5 for Black Tribunal). Reveals target's exact heresy + active miracles. Assassinates highest-tier worker. Blocked by Shadow Veil research.

### Synods (Guilds)
- Max 20 members. Tax rate 1-15% on gross production → vault
- Leader, officer, member roles. Leader can promote/demote/kick
- **Holy War**: Leader declares war on another synod. 48h duration. +20% attack for all members vs target synod
- **Relic theft**: Requires N unique synod members to crusade relic holder within 1h window. On success: relic transfers to attacking synod's leader

### Research
Light tree (costs dogma): Tax Evasion → Holy War → Divine Architecture, Fertile Ground → Consecrated Ground  
Dark tree (costs heresy): False Prophet → Shadow Veil, Dark Harvest → Plague Mastery

Timed effects (False Prophet, Shadow Veil) expire. Permanent effects (acre bonus, % bonuses) are forever.

### Relics
10 global unique items with powerful effects. Claimed/held by one player at a time. Stolen via synod-coordinated crusades. Synod-wide: relics held by any synod member benefit all members.

| Relic | Effect |
|-------|--------|
| Shroud of Turing | +100% Mana |
| Holy Server Rack | +50 Sacred Acres |
| Golden Compiler | +100% Gold |
| Eternal Patch | +100% Food |
| Obsidian Bible | +100% Heresy |
| Iron Rosary | +50% Crusade defense |
| Sacred Firewall | Plague immunity |
| Daemon Core | +100% Dogma |
| Papal Buffer | -50% all upkeep |
| Null Pointer Relic | +100% Dogma AND Heresy |

### Indulgences (Premium)
- **Papal Bull** (500 indulgences): 12h immunity from Crusades + Plagues. Cannot activate during Holy War.
- **Divine Architect** (200 indulgences): Enables build queue (up to 5). Cron auto-executes when resources met.
- Custom titles and avatars also purchasable.

### Cron Heartbeat
Runs every minute (`prayer-heartbeat`). 5 phases:
1. Karma milestones for active prayers
2. Resource generation (per-tick = daily_rate / 1440) with sect modifiers, relic bonuses, tithe siphoning
3. Synod tax collection → vault deposits
4. Expire timed effects (miracles, research, holy wars, papal bulls, divine shields)
5. Process Divine Architect build queue

### Ban System
Rejected prayers by Venice AI → karma -1 + ban. Ban duration scales with rejection severity. Indulgences (ad views) reduce ban by 15 min each. Intercessory prayers from other players reduce ban by 1 min per cycle.

---

## Game Config

All balance values live in `game_config` table. Change a row to rebalance — no code changes needed. Key categories:

- `building.*.mana_per_day`, `building.*.gold_per_day`, `building.*.food_per_day` — production rates
- `building.*.gold_upkeep_per_day`, `building.*.food_consumption_per_day` — upkeep
- `building.*.acre_cost` — sacred acres consumed
- `cap.*_multiplier` — resource caps (× daily rate)
- `sect.*.*_multiplier` — faction modifiers
- `crusade.*`, `schism.*`, `plague.*`, `inquisition.*` — combat balance
- `tithe.percentage` — vassalage tax rate
- `karma.milestone_*` — karma milestone tuning
- `synod.*` — guild config
- `indulgence.*` — premium config
- `shop.cost_scaling_multiplier` — exponential building cost

---

## Dev Notes

- **All mutations are RPCs** — no direct table INSERT/UPDATE from frontend
- **RLS** prevents direct writes; SECURITY DEFINER functions bypass RLS
- **Cron** is the sole resource generator — frontend only reads
- **Venice AI** handles all prayer text generation server-side (API key never reaches client)
- **`src/lib/supabase-schema.sql`** is legacy; migrations in `supabase/migrations/` are authoritative
- **Blessing config** is duplicated in `src/config/blessings.json` (frontend display) and `blessing_types` table (server authority)
- **`plans/` directory** contains NO current planning files — all are obsolete. Current planning happens in Exodus migration series