-- ======================================================================================
-- EXODUS 7: MASTER GAME CONFIGURATION & ECONOMY BALANCE
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE: 
-- Do NOT rename this file. Do NOT refactor this file into separate migrations. 
-- This is EXODUS_7. It is an idempotent master configuration sheet designed to be 
-- re-run indefinitely to hot-reload game balance. Respect the ON CONFLICT constraint.
-- ======================================================================================

BEGIN;

INSERT INTO public.game_config (key, value, description, category)
VALUES
    -- ==========================================
    -- 1. KARMA & PRAYER GENERATION
    -- ==========================================
    ('karma.milestone_threshold', 1, 'Number of prayer cycles needed to trigger a karma payout (1 = every cycle)', 'karma'),
    ('karma.milestone_payout', 2, 'Amount of karma awarded per threshold reached', 'karma'),
    ('karma.altruistic_multiplier', 2, 'Multiplier for praying for others', 'karma'),

    -- ==========================================
    -- 2. GLOBAL ENGINE SPEED
    -- ==========================================
    -- 1440 = 1x Real Time (slow), 144 = 10x Speed, 14 = 100x Speed
    ('tick.production_divisor', 144, 'Divisor for per-day to per-minute tick conversion', 'production'),

    -- ==========================================
    -- 3. VASSALAGE & TITHES
    -- ==========================================
    ('tithe.percentage', 0.10, 'Fraction of production paid as tithe to liege', 'vassalage'),
    ('vassalage.liege_karma_per_day', 5, 'Daily karma awarded per vassal', 'vassalage'),
    ('vassalage.subjugation_hours', 168, 'Hours required to subjugate a target', 'vassalage'),
    ('vassalage.tribute_gold_cost', 1000, 'Gold cost to reset 24 hours of subjugation', 'vassalage'),
    ('vassalage.rebellion_idle_days', 3, 'Days without attacks needed for rebellion', 'vassalage'),

    -- ==========================================
    -- 4. SYNODS & SOCIAL (EXODUS 6)
    -- ==========================================
    ('synod.creation_cost_gold', 500, 'Gold cost to found a new Synod', 'social'),
    ('synod.max_members', 20, 'Maximum players allowed in a single Synod', 'social'),
    ('shout.global_cost', 100, 'Gold cost to post a global shout', 'social'),
    ('shout.reply_cost', 50, 'Gold cost to reply to a shout', 'social'),
    ('shout.synod_leader_cost', 50, 'Gold cost for synod leader/officer to post (billed to vault)', 'social'),
    ('shout.synod_member_cost', 100, 'Gold cost for synod member to post (personal gold)', 'social'),

    -- ==========================================
    -- 5. COMBAT & SIEGE TICK TUNING (EXODUS 5)
    -- ==========================================
    ('combat.pvp_initiation_gold', 50, 'Gold cost to start PvP combat', 'combat'),
    ('combat.pvp_gold_per_tick', 2, 'Gold cost per PvP tick (Rescaled in Exo 5)', 'combat'),
    ('combat.pvp_max_ticks', 4320, 'Max ticks for PvP combat (3 days)', 'combat'),
    ('combat.pvp_leech_pct', 0.005, 'Gold leech percent per tick (PvP)', 'combat'),
    ('combat.pvp_attrition_pct', 0.10, 'Worker attrition percent per tick', 'combat'),
    ('combat.pvp_exertion_pct', 0.05, 'Mana exertion percent per tick', 'combat'),
    
    ('combat.holy_war_initiation_gold', 200, 'Gold cost to start Holy War', 'combat'),
    ('combat.holy_war_gold_per_tick', 10, 'Gold cost per tick (Holy War)', 'combat'),
    ('combat.holy_war_max_ticks', 10080, 'Max ticks for Holy War (7 days)', 'combat'),
    ('combat.holy_war_leech_pct', 0.002, 'Gold leech percent per tick (Holy War)', 'combat'),
    ('combat.holy_war_victory_pct', 0.20, 'Defender gold percent taken on Holy War victory', 'combat'),

    -- ==========================================
    -- 6. FACTION BETRAYAL & REWARDS
    -- ==========================================
    ('combat.betrayal_ally_ban_minutes', 15, 'Ban minutes for attacking ally faction', 'combat'),
    ('combat.betrayal_own_ban_minutes', 30, 'Ban minutes for attacking own faction', 'combat'),
    ('combat.betrayal_ally_karma', -5, 'Karma penalty for ally betrayal', 'combat'),
    ('combat.betrayal_own_karma', -10, 'Karma penalty for own faction betrayal', 'combat'),
    ('combat.kill_neutral_karma', 1, 'Karma reward for defeating neutral faction enemy', 'combat'),
    ('combat.kill_enemy_karma', 5, 'Karma reward for defeating faction enemy', 'combat'),

    -- ==========================================
    -- 7. SECT-SPECIFIC RESOURCE MULTIPLIERS
    -- ==========================================
    ('sect.gilded_path.mana_multiplier', 0.8, 'Mana debuff for Gilded Path', 'sect_bonus'),
    ('sect.gilded_path.gold_multiplier', 1.5, 'Gold buff for Gilded Path', 'sect_bonus'),
    ('sect.gilded_path.cathedral_upkeep_multiplier', 2.0, 'Upkeep penalty for Gilded Path', 'sect_bonus'),
    ('sect.holy_way.mana_multiplier', 1.2, 'Mana buff for Holy Way', 'sect_bonus'),
    ('sect.holy_way.food_consumption_multiplier', 0.5, 'Food efficiency buff for Holy Way', 'sect_bonus'),
    ('sect.final_watch.gold_multiplier', 0.75, 'Gold debuff for Final Watch', 'sect_bonus'),
    ('sect.final_watch.food_multiplier', 1.5, 'Food buff for Final Watch', 'sect_bonus'),
    ('sect.black_tribunal.mana_multiplier', 0.7, 'Mana debuff for Black Tribunal', 'sect_bonus'),
    ('sect.black_tribunal.heresy_multiplier', 2.0, 'Heresy generation buff for Black Tribunal', 'sect_bonus')

ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    updated_at = now();

    -- ==========================================
-- SHOP ITEMS: MANA BUILDINGS
-- ==========================================
INSERT INTO public.shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion)
VALUES
    ('altar',      'mana', 'Altar',     'A humble altar where devotion begins. Generates Mana.',                              '🕯️', 360,    0, 0, 'add_building', '{"building_type": "altar"}',     NULL, NULL, 1, true, true, 1, NULL, NULL),
    ('shrine',     'mana', 'Shrine',    'A shrine channeling greater spiritual energy. Generates more Mana.',                 '⛩️', 1800,   0, 0, 'add_building', '{"building_type": "shrine"}',    NULL, 'altar', 2, true, true, 2, NULL, NULL),
    ('temple',     'mana', 'Temple',    'A grand temple of devotion. Generates significant Mana. Requires gold upkeep.',       '🏛️', 9000,   0, 0, 'add_building', '{"building_type": "temple"}',    NULL, 'shrine', 3, true, true, 3, NULL, 'holy_way'),
    ('church',     'mana', 'Church',    'A holy church radiating divine power. Generates abundant Mana. Requires gold upkeep.', '⛪', 43200,  0, 0, 'add_building', '{"building_type": "church"}',    NULL, 'temple', 4, true, true, 5, NULL, 'holy_way'),
    ('cathedral',  'mana', 'Cathedral', 'A towering cathedral, pinnacle of spiritual architecture. Requires gold upkeep.',     '🏰', 216000, 0, 0, 'add_building', '{"building_type": "cathedral"}', NULL, 'church', 5, true, true, 8, NULL, 'holy_way')
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    karma_cost = EXCLUDED.karma_cost,
    gold_cost = EXCLUDED.gold_cost,
    heresy_cost = EXCLUDED.heresy_cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    purchase_limit = EXCLUDED.purchase_limit,
    requires_building = EXCLUDED.requires_building,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    cost_scaling = EXCLUDED.cost_scaling,
    acre_cost = EXCLUDED.acre_cost,
    sect_restriction = EXCLUDED.sect_restriction,
    sect_exclusion = EXCLUDED.sect_exclusion;

    -- ==========================================
-- SHOP ITEMS: FOOD BUILDINGS
-- ==========================================
INSERT INTO public.shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion)
VALUES
    ('pot',     'food', 'Pot',     'A simple pot for brewing sustenance. Generates Food.',                '🍲', 360,    0, 0, 'add_building', '{"building_type": "pot"}',     NULL, NULL,     11, true, true, 1, NULL, NULL),
    ('patch',   'food', 'Patch',   'A garden patch for growing crops. Generates more Food.',              '🌱', 1800,   0, 0, 'add_building', '{"building_type": "patch"}',   NULL, 'pot',     12, true, true, 2, NULL, NULL),
    ('garden',  'food', 'Garden',  'A lush garden of plenty. Generates significant Food.',               '🌾', 9000,   0, 0, 'add_building', '{"building_type": "garden"}',  NULL, 'patch',   13, true, true, 3, NULL, NULL),
    ('field',   'food', 'Field',   'A sprawling field of golden grain. Generates abundant Food.',        '🌻', 43200,  0, 0, 'add_building', '{"building_type": "field"}',   NULL, 'garden',  14, true, true, 5, NULL, NULL),
    ('farm',    'food', 'Farm',    'A grand farm estate, pinnacle of agricultural mastery.',             '🏡', 216000, 0, 0, 'add_building', '{"building_type": "farm"}',    NULL, 'field',   15, true, true, 8, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    karma_cost = EXCLUDED.karma_cost,
    gold_cost = EXCLUDED.gold_cost,
    heresy_cost = EXCLUDED.heresy_cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    purchase_limit = EXCLUDED.purchase_limit,
    requires_building = EXCLUDED.requires_building,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    cost_scaling = EXCLUDED.cost_scaling,
    acre_cost = EXCLUDED.acre_cost,
    sect_restriction = EXCLUDED.sect_restriction,
    sect_exclusion = EXCLUDED.sect_exclusion;

    -- ==========================================
-- SHOP ITEMS: WORKFORCE (GOLD GENERATORS)
-- ==========================================
INSERT INTO public.shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion)
VALUES
    ('novice',   'workforce', 'Novice',   'A novice devotee learning the ways. Generates Gold, consumes Food.',        '🙏', 540,    0,     0, 'add_building', '{"building_type": "novice"}',   NULL, NULL,      21, true, true, 1, NULL, NULL),
    ('monk',     'workforce', 'Monk',     'A disciplined monk. Generates more Gold, consumes more Food.',              '🧘', 2700,   0,     0, 'add_building', '{"building_type": "monk"}',     NULL, 'novice',   22, true, true, 1, NULL, NULL),
    ('cleric',   'workforce', 'Cleric',   'A powerful cleric channeling divine wealth. Generates significant Gold.', '🧙', 14400,  0,     0, 'add_building', '{"building_type": "cleric"}',   NULL, 'monk',     23, true, true, 2, NULL, NULL),
    ('bishop',   'workforce', 'Bishop',   'A bishop commanding vast resources. Generates abundant Gold.',             '👑', 72000,  0,     0, 'add_building', '{"building_type": "bishop"}',   NULL, 'cleric',   24, true, true, 3, NULL, NULL),
    ('cardinal', 'workforce', 'Cardinal', 'A cardinal, highest authority in the divine hierarchy. Generates immense Gold.', '⭐', 360000, 0, 0, 'add_building', '{"building_type": "cardinal"}', NULL, 'bishop', 25, true, true, 5, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    karma_cost = EXCLUDED.karma_cost,
    gold_cost = EXCLUDED.gold_cost,
    heresy_cost = EXCLUDED.heresy_cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    purchase_limit = EXCLUDED.purchase_limit,
    requires_building = EXCLUDED.requires_building,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    cost_scaling = EXCLUDED.cost_scaling,
    acre_cost = EXCLUDED.acre_cost,
    sect_restriction = EXCLUDED.sect_restriction,
    sect_exclusion = EXCLUDED.sect_exclusion;

    -- ==========================================
-- SHOP ITEMS: WORKFORCE (GOLD GENERATORS)
-- ==========================================
INSERT INTO public.shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion)
VALUES
    ('novice',   'workforce', 'Novice',   'A novice devotee learning the ways. Generates Gold, consumes Food.',        '🙏', 540,    0,     0, 'add_building', '{"building_type": "novice"}',   NULL, NULL,      21, true, true, 1, NULL, NULL),
    ('monk',     'workforce', 'Monk',     'A disciplined monk. Generates more Gold, consumes more Food.',              '🧘', 2700,   0,     0, 'add_building', '{"building_type": "monk"}',     NULL, 'novice',   22, true, true, 1, NULL, NULL),
    ('cleric',   'workforce', 'Cleric',   'A powerful cleric channeling divine wealth. Generates significant Gold.', '🧙', 14400,  0,     0, 'add_building', '{"building_type": "cleric"}',   NULL, 'monk',     23, true, true, 2, NULL, NULL),
    ('bishop',   'workforce', 'Bishop',   'A bishop commanding vast resources. Generates abundant Gold.',             '👑', 72000,  0,     0, 'add_building', '{"building_type": "bishop"}',   NULL, 'cleric',   24, true, true, 3, NULL, NULL),
    ('cardinal', 'workforce', 'Cardinal', 'A cardinal, highest authority in the divine hierarchy. Generates immense Gold.', '⭐', 360000, 0, 0, 'add_building', '{"building_type": "cardinal"}', NULL, 'bishop', 25, true, true, 5, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    karma_cost = EXCLUDED.karma_cost,
    gold_cost = EXCLUDED.gold_cost,
    heresy_cost = EXCLUDED.heresy_cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    purchase_limit = EXCLUDED.purchase_limit,
    requires_building = EXCLUDED.requires_building,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    cost_scaling = EXCLUDED.cost_scaling,
    acre_cost = EXCLUDED.acre_cost,
    sect_restriction = EXCLUDED.sect_restriction,
    sect_exclusion = EXCLUDED.sect_exclusion;

    -- ==========================================
-- SHOP ITEMS: INFRASTRUCTURE (PRAYER SLOTS)
-- ==========================================
INSERT INTO public.shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion)
VALUES
    ('prayer-slot-2', 'infrastructure', 'Second Prayer Slot', 'Pray two prayers simultaneously. +100 Devotion per day.',  '🙏', 3600,  0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}', NULL, NULL, 31, true, false, 0, NULL, NULL),
    ('prayer-slot-3', 'infrastructure', 'Third Prayer Slot',  'The truly devoted can pray three prayers at once. +100 Devotion per day.', '🙏', 10800, 0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}', NULL, NULL, 32, true, false, 0, NULL, NULL),
    ('prayer-slot-4', 'infrastructure', 'Fourth Prayer Slot', 'Four simultaneous prayers. A holy multitasker. +100 Devotion per day.', '🙏', 28800, 0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}', NULL, NULL, 33, true, false, 0, NULL, NULL),
    ('prayer-slot-5', 'infrastructure', 'Fifth Prayer Slot',   'Five prayers at once. Divine concurrency. +100 Devotion per day.', '🙏', 72000, 0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}', NULL, NULL, 34, true, false, 0, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    karma_cost = EXCLUDED.karma_cost,
    gold_cost = EXCLUDED.gold_cost,
    heresy_cost = EXCLUDED.heresy_cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    purchase_limit = EXCLUDED.purchase_limit,
    requires_building = EXCLUDED.requires_building,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    cost_scaling = EXCLUDED.cost_scaling,
    acre_cost = EXCLUDED.acre_cost,
    sect_restriction = EXCLUDED.sect_restriction,
    sect_exclusion = EXCLUDED.sect_exclusion;

    -- ==========================================
-- SHOP ITEMS: CATACOMBS (HERESY BUILDINGS)
-- ==========================================
INSERT INTO public.shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion)
VALUES
    ('cultist',     'catacombs', 'Cultist', 'A shadow disciple who generates Heresy. Consumes Food like any worker.', '🧟', 0, 1800,  0, 'add_building', '{"building_type": "cultist"}', NULL, NULL,     41, true, true, 1, NULL, NULL),
    ('coven',       'catacombs', 'Coven',   'A hidden gathering place that increases your Heresy capacity. Requires gold upkeep.', '🔮', 0, 7200,  0, 'add_building', '{"building_type": "coven"}',   NULL, 'cultist', 42, true, true, 3, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    karma_cost = EXCLUDED.karma_cost,
    gold_cost = EXCLUDED.gold_cost,
    heresy_cost = EXCLUDED.heresy_cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    purchase_limit = EXCLUDED.purchase_limit,
    requires_building = EXCLUDED.requires_building,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    cost_scaling = EXCLUDED.cost_scaling,
    acre_cost = EXCLUDED.acre_cost,
    sect_restriction = EXCLUDED.sect_restriction,
    sect_exclusion = EXCLUDED.sect_exclusion;

    -- ==========================================
-- SHOP ITEMS: RESEARCH (DOGMA BUILDINGS)
-- ==========================================
INSERT INTO public.shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion)
VALUES
    ('scriptorium', 'research', 'Scriptorium', 'A monastery scriptorium where Clerics transcribe sacred texts. Generates Dogma instead of Gold when active. Requires gold upkeep and consumes Food.', '📜', 18000, 10800, 0, 'add_building', '{"building_type": "scriptorium"}', NULL, 'cleric', 51, true, true, 4, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    karma_cost = EXCLUDED.karma_cost,
    gold_cost = EXCLUDED.gold_cost,
    heresy_cost = EXCLUDED.heresy_cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    purchase_limit = EXCLUDED.purchase_limit,
    requires_building = EXCLUDED.requires_building,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    cost_scaling = EXCLUDED.cost_scaling,
    acre_cost = EXCLUDED.acre_cost,
    sect_restriction = EXCLUDED.sect_restriction,
    sect_exclusion = EXCLUDED.sect_exclusion;

    -- ==========================================
-- BLESSING TYPES
-- ==========================================
INSERT INTO public.blessing_types (id, emoji, name, description, karma_cost, karma_to_giver, karma_to_receiver, sort_order, is_active, shield_minutes)
VALUES
    ('golden-light',   '✨', 'Golden Light',   'A radiant blessing that illuminates the prayer with divine light.', 10,  1,  5,  1, true, NULL),
    ('holy-flame',     '🔥', 'Holy Flame',     'The sacred fire that purifies and elevates the spirit.',            25,  2,  10, 2, true, NULL),
    ('dove-of-peace',  '🕊️', 'Dove of Peace',  'A gentle blessing that brings tranquility and grace.',              50,  5,  20, 3, true, NULL),
    ('divine-crown',   '👑', 'Divine Crown',   'The highest honor — a crown of divine recognition.',               100, 10, 50, 4, true, NULL)
ON CONFLICT (id) DO UPDATE SET
    emoji = EXCLUDED.emoji,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    karma_cost = EXCLUDED.karma_cost,
    karma_to_giver = EXCLUDED.karma_to_giver,
    karma_to_receiver = EXCLUDED.karma_to_receiver,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    shield_minutes = EXCLUDED.shield_minutes;

    -- ==========================================
-- RESEARCH NODES (TECH TREE)
-- ==========================================
INSERT INTO public.research_nodes (id, name, description, emoji_icon, alignment, cost, effect_type, effect_data, requires_node, sort_order, is_active)
VALUES
    -- Light Alignment (Dogma)
    ('tax_evasion',        'Tax Evasion',        'Reduces vassal tithe from 10% to 5%',                             '💸', 'light', 7200,  'vassal_tithe_reduction', '{"reduction_percent": 50}',                  NULL,                1,  true),
    ('holy_war',           'Holy War',           '+15% Crusade Attack Power',                                        '⚔',  'light', 10800, 'crusade_attack_bonus',  '{"bonus_percent": 15}',                      'tax_evasion',       2,  true),
    ('divine_architecture','Divine Architecture', 'Reduces all building acre costs by 20%',                           '🏛', 'light', 14400, 'acre_cost_reduction',  '{"reduction_percent": 20}',                   'holy_war',          3,  true),
    ('fertile_ground',     'Fertile Ground',     '+25% Food generation',                                              '🌱', 'light', 12600, 'food_bonus',            '{"bonus_percent": 25}',                       NULL,                4,  true),
    ('consecrated_ground', 'Consecrated Ground', '+10 Sacred Acres',                                                  '✞',  'light', 18000, 'acres_bonus',           '{"acres_bonus": 10}',                         'fertile_ground',    5,  true),

    -- Dark Alignment (Heresy)
    ('false_prophet',      'False Prophet',      'Intercept 25% of a target''s incoming tithes for 12 hours',         '👴', 'dark',  5400,  'tithe_intercept',       '{"duration_hours": 12, "intercept_percent": 25}', NULL,             11, true),
    ('shadow_veil',        'Shadow Veil',        'Immune to Inquisitions for 24 hours',                               '🗨',  'dark',  7200,  'inquisition_immunity',  '{"duration_hours": 24}',                      'false_prophet',     12, true),
    ('dark_harvest',       'Dark Harvest',       '+50% Heresy generation',                                            '☠',  'dark',  9000,  'heresy_bonus',          '{"bonus_percent": 50}',                       NULL,                13, true),
    ('plague_mastery',     'Plague Mastery',     'Plagues destroy 150% of food instead of 100%',                      '🦠', 'dark',  10800, 'plague_amplification',  '{"amplification_percent": 150}',              'dark_harvest',      14, true)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    alignment = EXCLUDED.alignment,
    cost = EXCLUDED.cost,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    requires_node = EXCLUDED.requires_node,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active;

    -- ==========================================
-- RELICS (10 GLOBAL UNIQUES)
-- ==========================================
INSERT INTO public.relics (id, name, description, emoji_icon, effect_type, effect_data, is_active)
VALUES
    ('42342d14-1519-4d7f-80c2-c31f328a2580'::uuid, 'The Holy Server Rack',   '+50 Sacred Acres',                                '🖥', 'acres_bonus',           '{"acres_bonus": 50}'::jsonb,                                 true),
    ('53ff2659-edea-4b6b-92aa-7a675f017e3e'::uuid, 'The Golden Compiler',    '+100% Gold generation',                           '✨', 'gold_double',            '{"gold_multiplier": 2}'::jsonb,                               true),
    ('e2fc0f5b-2270-468b-847e-afdf572f789e'::uuid, 'The Eternal Patch',     '+100% Food generation',                          '🌾', 'food_double',            '{"food_multiplier": 2}'::jsonb,                               true),
    ('9051493d-19f1-4d0b-94d6-e652bc1ee368'::uuid, 'The Obsidian Bible',    '+100% Heresy generation',                        '📕', 'heresy_double',          '{"heresy_multiplier": 2}'::jsonb,                             true),
    ('14b71223-49bf-4b86-be00-cb52c313f63a'::uuid, 'The Iron Rosary',       '+50% Crusade defense',                          '📿', 'crusade_defense_bonus',  '{"bonus_percent": 50}'::jsonb,                                true),
    ('51b4d9d5-7c8d-4a20-8c40-41f984e5ac12'::uuid, 'The Sacred Firewall',   'Immune to Plagues',                             '🛡', 'plague_immunity',        '{"immune": true}'::jsonb,                                     true),
    ('5abfd1c6-df7d-484d-a976-9d5623c80a8e'::uuid, 'The Daemon Core',       '+100% Dogma generation',                        '🔥', 'dogma_double',           '{"dogma_multiplier": 2}'::jsonb,                              true),
    ('40433408-1237-495f-a2f2-7d95a9688681'::uuid, 'The Papal Buffer',      '-50% all upkeep costs',                         '📛', 'upkeep_reduction',       '{"reduction_percent": 50}'::jsonb,                             true),
    ('6412aca1-65c8-411c-b77e-318e2acd09ac'::uuid, 'The Null Pointer Relic','+100% Dogma AND Heresy generation',             '💥', 'dual_research_double',   '{"dogma_multiplier": 2, "heresy_multiplier": 2}'::jsonb,       true),
    ('9765dd88-f1dd-42bb-a2db-b1199c81d46f'::uuid, 'The Shroud of Turing',  '+100% Mana generation',                        '📜', 'mana_double',            '{"mana_multiplier": 2}'::jsonb,                               true)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji_icon = EXCLUDED.emoji_icon,
    effect_type = EXCLUDED.effect_type,
    effect_data = EXCLUDED.effect_data,
    is_active = EXCLUDED.is_active;

   -- ==========================================
-- FACTION RELATIONSHIPS
-- ==========================================
INSERT INTO public.faction_relationships (id, sect_key, enemy_sect, ally_sect, neutral_sect, rationale_enemy, rationale_ally, rationale_neutral)
VALUES
    ('c1d10add-e1cf-4a16-b610-71a1ef0cd0c4'::uuid, 'gilded_path',    'black_tribunal', 'holy_way',    'final_watch', 'Needs Mana to fuel defenses; The Tribunal steals Gold.', 'Mutual economic dependency — Gilded provides Gold, Holy provides Mana.', 'Neither ally nor foe; pragmatic coexistence.'),
    ('8b27e10c-450b-45d2-852c-1cb5fb67c855'::uuid, 'holy_way',        'final_watch',    'gilded_path', 'black_tribunal', 'The Watch blocks their ascension; physical stability clashes with pure Mana worship.', 'Gilded Path funds their ascetic lifestyle with Gold.', 'The Tribunal ignores pure monks; no economic overlap.'),
    ('e5bb05b7-d00f-4ca7-8474-8b0786e21317'::uuid, 'final_watch',     'holy_way',       'black_tribunal', 'gilded_path', 'Physical stability clashes with pure Mana worship; the Watch sees asceticism as weakness.', 'The Tribunal serves as an aggressive police force the Watch respects.', 'Pragmatic coexistence; no direct conflict or benefit.'),
    ('f88d0112-7364-4dc4-bf22-de29cef38381'::uuid, 'black_tribunal',  'gilded_path',    'final_watch',  'holy_way', 'High Heresy attracts Gold hoarders; natural enemies.', 'The Tribunal serves as an aggressive police force; the Watch is their enforcer.', 'Pure monks are beneath the Tribunal''s notice.')
ON CONFLICT (sect_key) DO UPDATE SET
    enemy_sect = EXCLUDED.enemy_sect,
    ally_sect = EXCLUDED.ally_sect,
    neutral_sect = EXCLUDED.neutral_sect,
    rationale_enemy = EXCLUDED.rationale_enemy,
    rationale_ally = EXCLUDED.rationale_ally,
    rationale_neutral = EXCLUDED.rationale_neutral; 

COMMIT;