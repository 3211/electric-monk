ALTER FUNCTION submit_shout(TEXT, TEXT) SET search_path = public;
ALTER FUNCTION submit_shout_reply(UUID, TEXT) SET search_path = public;
ALTER FUNCTION get_shouts(INT, INT, TEXT) SET search_path = public;
ALTER FUNCTION get_shout_replies(UUID, INT, INT) SET search_path = public;
ALTER FUNCTION grant_shout_blessing(UUID, TEXT, UUID) SET search_path = public;
ALTER FUNCTION get_shout_blessings(UUID[]) SET search_path = public;