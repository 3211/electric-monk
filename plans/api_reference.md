# API Reference (RPCs)

This document provides usage examples and technical details for the Supabase Remote Procedure Calls (RPCs) used in Holy War Online.

---

## JavaScript/TypeScript Usage Examples

All RPCs are called via the `supabase.rpc()` method. Ensure you are using an authenticated client where required.

```typescript
// Get player status (Profile + Onboarding state)
const { data } = await supabase.rpc('get_player_status');
console.log(data.username, data.sect_name, data.onboarding_complete);

// Update username (Validates and saves)
const { data } = await supabase.rpc('update_player_username', { 
  p_new_username: 'NewName_123' 
});
if (!data.success) console.error(data.error);

// Choose a sect (Sets faction affiliation)
const { data } = await supabase.rpc('choose_player_sect', { 
  p_sect_id: 'gilded_path' 
});

// Complete onboarding (Marks profile as ready)
const { data } = await supabase.rpc('complete_player_onboarding');

// Get all available sects (Returns data for selection UI)
const { data: sects } = await supabase.rpc('get_available_sects');
```

---

## Technical Security Note

All RPC functions use `SECURITY DEFINER` with `SET search_path = ''` to prevent PostgreSQL search-path hijacking attacks. 

Permissions are managed via explicit `GRANT` statements to the `authenticated` and `service_role` roles. Refer to [`docs/migrations.md`](./migrations.md) for details on the `service_role` requirement for Edge Functions.
