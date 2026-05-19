UPDATE combat_sessions
SET is_active = false, result = 'defender_win', last_tick_at = now()
WHERE combat_type = 'holy_war' AND is_active = true;

UPDATE synods SET active_war_id = NULL WHERE active_war_id IS NOT NULL;

UPDATE synod_wars SET is_active = false WHERE is_active = true;
