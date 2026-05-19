# File-to-Feature Map

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

## Views → What They Render

| View | Route/Tab | Purpose |
|------|-----------|---------|
| [`LoginView.vue`](../src/views/LoginView.vue) | Unauthenticated | Google OAuth + email/password signup/login |
| [`AltarView.vue`](../src/views/AltarView.vue) | "Altar" tab | Main prayer interface — submit, cycle prayers, resource bar |
| [`AkashicRecordsView.vue`](../src/views/AkashicRecordsView.vue) | "Records" tab | Public prayer feed + sinners list, altruistic/intercessory praying |
| [`FactionsView.vue`](../src/views/FactionsView.vue) | "Factions" tab | Diamond layout showing 4 factions + relationships |
| [`VaticanView.vue`](../src/views/VaticanView.vue) | "Vatican" tab | Vassalage management + siege combat + subjugation + combat log |
| [`SynodHallView.vue`](../src/views/SynodHallView.vue) | "Synod Hall" tab | Guild management, members, vault, holy war |
| [`ScriptoriumView.vue`](../src/views/ScriptoriumView.vue) | "Scriptorium" tab | Light/dark tech tree with prerequisite lines |
| [`KarmaShopView.vue`](../src/views/KarmaShopView.vue) | "Shop" tab | Real Estate, Workforce, Blessings, Infrastructure tabs |
| [`ReliquaryView.vue`](../src/views/ReliquaryView.vue) | "Reliquary" tab | 10 global relics with holders + steal progress |
| [`LeaderboardView.vue`](../src/views/LeaderboardView.vue) | "Rankings" tab | Faith-filtered leaderboard |
| [`CatacombsView.vue`](../src/views/CatacombsView.vue) | "Catacombs" tab | Heresy economy: cultists, covens, schism, plague |
| [`PurgatoryView.vue`](../src/views/PurgatoryView.vue) | Banned-only overlay | Ban timer + indulgence ad reduction + active siege status |

**Nav order:** altar → records → factions → vatican → synod → scriptorium → shop → rankings

## Composables → What They Manage

| Composable | Supabase Tables | Key RPCs Used |
|------------|----------------|---------------|
| [`useAuth.js`](../src/composables/useAuth.js) | auth.users, profiles | Supabase Auth |
| [`usePrayers.js`](../src/composables/usePrayers.js) | prayers, profiles | `submit_prayer`, `sync_prayer_count`, `activate_prayer`, `deactivate_prayer` |
| [`usePrayerCounter.js`](../src/composables/usePrayerCounter.js) | prayers | Client-side counting with server sync |
| [`useAkashicRecords.js`](../src/composables/useAkashicRecords.js) | prayers, profiles | `get_public_prayers`, `get_sinners`, `start_altruistic_prayer`, `start_intercessory_prayer` |
| [`useEconomy.js`](../src/composables/useEconomy.js) | profiles, player_buildings, game_config | `get_player_economy` |
| [`useShop.js`](../src/composables/useShop.js) | shop_items, player_buildings, profiles | `purchase_shop_item` |
| [`useKarmaShop.js`](../src/composables/useKarmaShop.js) | blessing_types, prayer_blessings | `grant_blessing` |
| [`useBlessings.js`](../src/composables/useBlessings.js) | blessing_types, prayer_blessings | `get_prayer_blessings` |
| [`useFactions.js`](../src/composables/useFactions.js) | faction_relationships, profiles | `get_factions_overview` |
| [`useSects.js`](../src/composables/useSects.js) | profiles, game_config | `choose_sect`, `get_sect_info` |
| [`useSynod.js`](../src/composables/useSynod.js) | synods, synod_wars, profiles | `create_synod`, `join_synod`, `leave_synod`, `initiate_holy_war`, `get_synod_info`, promote/demote/kick |
| [`useVassalage.js`](../src/composables/useVassalage.js) | profiles, akashic_logs, subjugation_timers | `get_vassalage_info`, `launch_crusade` (deprecated), `declare_schism`, `cast_plague`, `start_subjugation`, `resist_subjugation`, `attempt_rebellion`, `get_akashic_logs`, `lookup_player` |
| [`useCombat.js`](../src/composables/useCombat.js) | combat_sessions, profiles | Exodus 5: `initiate_combat`, `cancel_combat`, `surrender_combat`, `get_active_combats` |
| [`useHolyWar.js`](../src/composables/useHolyWar.js) | combat_sessions, synods | `findTarget`, `initiateHolyWar`, `get_active_holy_wars` |
| [`useCatacombs.js`](../src/composables/useCatacombs.js) | profiles, player_buildings | Heresy economy display |
| [`useInquisition.js`](../src/composables/useInquisition.js) | profiles, akashic_logs | `launch_inquisition` |
| [`useResearch.js`](../src/composables/useResearch.js) | research_nodes, player_research, profiles | `research_tech`, `get_research_tree` |
| [`useRelics.js`](../src/composables/useRelics.js) | relics | `get_relics`, `attempt_relic_steal` |
| [`useIndulgences.js`](../src/composables/useIndulgences.js) | profiles, active_miracles | `consume_indulgence` |
| [`useLeaderboard.js`](../src/composables/useLeaderboard.js) | profiles | `get_leaderboard_by_faith`, `get_user_ranks` |
| [`useOnboarding.js`](../src/composables/useOnboarding.js) | profiles | `choose_sect`, `change_username` |
| [`useBanTimer.js`](../src/composables/useBanTimer.js) | profiles, indulgences | `reduce_ban_time` |

## Components → What They Render

| Component | Type | Purpose |
|-----------|------|---------|
| [`OnboardingWizard.vue`](../src/components/organisms/OnboardingWizard.vue) | Organism | 4-step onboarding: AI welcome → identity → faction intro → first prayer |
| [`SectSelectionModal.vue`](../src/components/organisms/SectSelectionModal.vue) | Organism | Faction picker with lore + modifiers |
| [`AkashicPrayerCard.vue`](../src/components/organisms/AkashicPrayerCard.vue) | Organism | Public prayer card with blessing badges |
| [`SinnerCard.vue`](../src/components/organisms/SinnerCard.vue) | Organism | Purgatory user card with countdown |
| [`BlessingPicker.vue`](../src/components/organisms/BlessingPicker.vue) | Organism | Modal to select + grant a blessing |
| [`BlessingDetailModal.vue`](../src/components/organisms/BlessingDetailModal.vue) | Organism | Full blessing breakdown popup |
| [`PrayerHistoryModal.vue`](../src/components/organisms/PrayerHistoryModal.vue) | Organism | User's prayer history |
| [`UsernameChangeModal.vue`](../src/components/organisms/UsernameChangeModal.vue) | Organism | Username change with cooldown |
| [`BlessingBadgeBar.vue`](../src/components/molecules/BlessingBadgeBar.vue) | Molecule | Emoji badge bar with overflow |
| [`KarmaToast.vue`](../src/components/molecules/KarmaToast.vue) | Molecule | Karma milestone notification |
| [`MiracleBuffBar.vue`](../src/components/molecules/MiracleBuffBar.vue) | Molecule | Active miracle indicators |
| [`ShieldTimer.vue`](../src/components/molecules/ShieldTimer.vue) | Molecule | Divine shield countdown |

## Edge Functions

| Function | Trigger | Purpose |
|----------|---------|---------|
| `process-prayer` | Prayer submitted | Venice AI validates + responds. Applies karma (+1 approved / -1 rejected), bans on rejection |
| `pray-for-sinner` | Intercessory prayer started | Venice AI generates intercessory prayer text for the sinner |
| `generate-onboarding-content` | Onboarding steps | AI-generated welcome message, faction intro, prayer suggestion |