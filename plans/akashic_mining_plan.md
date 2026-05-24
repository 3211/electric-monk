# Akashic Record Mining Architecture Plan

## 1. Database Schema (`supabase/migrations/revelations_3.sql`)

We will create a new migration for the Akashic Record system. 

### Tables:
*   `akashic_scans_pending`: Tracks active mining operations.
    *   `process_id` (UUID, Primary Key)
    *   `machine_ip` (INET, References `virtual_machines(ip_address)`)
    *   `faction_ip` (INET, References `network_addresses(ip_address)`, nullable if solo)
    *   `start_time` (TIMESTAMPTZ, Default NOW())
    *   `expected_completion_time` (TIMESTAMPTZ)
    *   `block_speed_ms` (INT)
    *   `is_verification` (BOOLEAN, Default FALSE)
    *   `target_blocks` (INT, Default 5)

*   `akashic_scans_completed`: Archive of finished work.
    *   `id` (UUID, Primary Key)
    *   `process_id` (UUID)
    *   `machine_ip` (INET)
    *   `faction_ip` (INET)
    *   `start_time` (TIMESTAMPTZ)
    *   `end_time` (TIMESTAMPTZ, Default NOW())
    *   `score_awarded` (INT)
    *   `is_verification` (BOOLEAN)

*   `akashic_sectors`: Global state of discovered blocks.
    *   `block_id` (INT, Primary Key)
    *   `discovered_by_ip` (INET)
    *   `discovered_by_faction_ip` (INET)
    *   `discovery_time` (TIMESTAMPTZ)
    *   `score_value` (INT)

### RLS Policies:
*   Service role has full access to manage these tables.
*   Public read access to `akashic_sectors`.
*   Users can read their own pending/completed scans based on their `machine_ip` ownership.

## 2. Edge Function (`akashic-mining`)

A single edge function with two main actions (`start` and `pulse`).

### Action: `start`
1.  **Input**: `machine_ip`, `start_block_id`.
2.  **Hardware Lookup**: Fetch the VM's hardware (CPU, RAM, Network) from `virtual_machines` joining with catalog tables.
3.  **Compute Speed Calculation**: 
    *   *Formula Idea*: `(CPU Cores * CPU MHz) + (RAM MHz * 0.5) + (Network Mbps * 10)`
    *   Determine base time per block, adjusted by compute speed.
4.  **Verification Check**: Check `akashic_sectors` if blocks are already discovered. If so, `is_verification = true`, which is faster but yields lower score.
5.  **State Creation**: Insert into `akashic_scans_pending` with expected completion time.
6.  **Output**: `process_id`, `block_speed_ms`, `expected_completion_time`.

### Action: `pulse` (Complete)
1.  **Input**: `process_id`, `results` (scores/words found).
2.  **Validation**: Fetch pending scan. 
    *   Ensure `now() >= expected_completion_time - (total_duration * 0.05)` (5% early buffer allowed).
    *   If too early, reject.
3.  **Finalization**: 
    *   Move record from `pending` to `completed`.
    *   If initial mining, insert into `akashic_sectors`.
    *   Credit faction/player score (update `network_addresses` or `sects` table).
4.  **Output**: Score awarded, next block info.

## 3. Client Implementation (`src/terminal/akashicScannerCommand.js`)

*   **Init**: When the user runs `akashic-scan`, call the edge function `start` action.
*   **Visuals**: Use the returned `block_speed_ms` to drive the animation, ensuring it aligns perfectly with the server's expected time.
*   **Pulse**: When the 5-block batch visually completes, call the edge function `pulse` action to submit results and claim the score. If successful, automatically trigger the next `start`.
*   **Recovery**: If the user refreshes, check for an active `process_id` via DB/Edge Function and resume the visualizer based on the elapsed time.