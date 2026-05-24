# Akashic Record Mining

This module defines the infrastructure for the Akashic Record mining gameplay feature — a crypto-mining style mechanic where players use their virtual machines to discover and verify "blocks" of text from the Akashic blockchain.

## Related Helper Functions (RPCs)

| Function | Parameters | Returns | Description |
|----------|------------|---------|-------------|
| [`calculate_compute_speed(p_machine_ip)`](supabase/migrations/revelations_3.sql) | `inet` | INT | Calculates mining compute speed from the VM's CPU cores × MHz + RAM MHz × 0.5 + Network Mbps × 10 |
| [`calculate_block_speed_ms(p_compute_speed)`](supabase/migrations/revelations_3.sql) | `INT` | INT | Converts compute speed to milliseconds per block: `MAX(500, 12,000,000 / compute_speed)` |
| [`calculate_expected_completion(p_block_speed_ms, p_target_blocks)`](supabase/migrations/revelations_3.sql) | `INT, INT` | TIMESTAMPTZ | Returns `now() + (block_speed_ms × target_blocks × 1.10)` |
| [`get_player_faction_ip(p_user_id)`](supabase/migrations/revelations_3.sql) | `UUID` | inet | Returns the sect's IP for the given player (NULL if no sect). |
| [`get_player_pending_scans(p_user_id)`](supabase/migrations/revelations_3.sql) | `UUID` | TABLE | Returns all active pending scans for a player's machines. Used for recovery after page refresh. |

---

## `akashic_sectors`

Global registry of every block ever discovered. Each `block_id` can only be mined once, but verified many times.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `block_id` | BIGINT | PRIMARY KEY | Fibonacci seed offset identifying the mined address |
| `discovered_by_ip` | inet | NOT NULL | IP of the virtual machine that first discovered this block |
| `discovered_by_faction_ip` | inet | NULLABLE | IP of the faction (sect) credited with discovery. NULL if solo mining. |
| `discovery_time` | TIMESTAMPTZ | NOT NULL DEFAULT now() | When the block was first discovered |
| `score_value` | INT | NOT NULL DEFAULT 0 | Score awarded for the initial discovery |
| `verification_count` | INT | NOT NULL DEFAULT 0 | Number of times this block has been verified by other machines |
| `last_verified_at` | TIMESTAMPTZ | NULLABLE | Timestamp of the most recent verification |
| `last_verified_by_ip` | inet | NULLABLE | IP of the most recent verifier machine |

**Indexes:**
- `idx_akashic_sectors_discovered_by` on `discovered_by_ip`
- `idx_akashic_sectors_faction` on `discovered_by_faction_ip`
- `idx_akashic_sectors_discovery_time` on `discovery_time DESC`

**RLS Policies:**
- SELECT: Public read-only (anyone can see the global registry)
- ALL: Service role manages all rows

---

## `akashic_scans_pending`

Active mining operations. Each row represents a batch currently being processed by a virtual machine.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `process_id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Unique identifier used by client for resume/pulse |
| `machine_ip` | inet | NOT NULL | IP of the VM performing the mining |
| `faction_ip` | inet | NULLABLE | IP of the faction credited. NULL if solo mining. |
| `start_block_id` | BIGINT | NOT NULL | First Fibonacci seed offset in the batch |
| `target_blocks` | INT | NOT NULL DEFAULT 5 | Number of blocks to mine in this batch |
| `start_time` | TIMESTAMPTZ | NOT NULL DEFAULT now() | When the batch was registered |
| `expected_completion_time` | TIMESTAMPTZ | NOT NULL | Server-calculated time when results should be accepted |
| `block_speed_ms` | INT | NOT NULL | Milliseconds per block (drives client animation timing) |
| `is_verification` | BOOLEAN | NOT NULL DEFAULT false | True if blocks already discovered (faster, 25% payout) |
| `compute_speed_score` | INT | NOT NULL DEFAULT 0 | Raw compute score from VM hardware |

**Indexes:**
- `idx_akashic_pending_machine` on `machine_ip`
- `idx_akashic_pending_faction` on `faction_ip`
- `idx_akashic_pending_expected` on `expected_completion_time`

**RLS Policies:**
- SELECT: Players can view their own pending scans (via VM ownership chain)
- ALL: Service role manages all rows

---

## `akashic_scans_completed`

Archive of finished mining operations. Records scores awarded and processing metadata.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | |
| `process_id` | UUID | NOT NULL | Matches `process_id` from [`akashic_scans_pending`](#akashic_scans_pending) |
| `machine_ip` | inet | NOT NULL | IP of the mining machine |
| `faction_ip` | inet | NULLABLE | IP of the credited faction |
| `start_time` | TIMESTAMPTZ | NOT NULL | When the batch started |
| `end_time` | TIMESTAMPTZ | NOT NULL DEFAULT now() | When the batch was completed |
| `start_block_id` | BIGINT | NOT NULL | First block in the batch |
| `blocks_processed` | INT | NOT NULL | Number of blocks actually processed |
| `score_awarded` | INT | NOT NULL DEFAULT 0 | Total score awarded for this batch |
| `is_verification` | BOOLEAN | NOT NULL DEFAULT false | Whether this was a verification run |

**Indexes:**
- `idx_akashic_completed_machine` on `machine_ip`
- `idx_akashic_completed_faction` on `faction_ip`
- `idx_akashic_completed_process` on `process_id`
- `idx_akashic_completed_time` on `end_time DESC`

**RLS Policies:**
- SELECT: Players can view their own completed scans
- ALL: Service role manages all rows

---

## `network_addresses` (Extension)

The `akashic_score` column was added to [`network_addresses`](1_core_tables.md#network_addresses):

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `akashic_score` | INT | NOT NULL DEFAULT 0 | Cumulative Akashic mining score earned by this IP address. Updated on each completed pulse. |

---

## Edge Function: `akashic-mining`

The [`akashic-mining`](supabase/functions/akashic-mining/index.ts) edge function handles the mining lifecycle with three actions:

### Action: `start`

1. Validates player JWT and VM ownership (owner IP must match player IP).
2. Reads VM hardware from catalogs (CPU, RAM, Network Card).
3. Calculates `compute_speed_score` using formula: `(CPU Cores × CPU MHz) + (RAM MHz × 0.5) + (Network Mbps × 10)`.
4. Converts to `block_speed_ms` = `MAX(500, 12,000,000 / compute_speed_score)`.
5. Calculates `expected_completion_time` = `now() + (block_speed_ms × target_blocks × 1.10)`.
6. Checks if ALL blocks in the batch are already in [`akashic_sectors`](#akashic_sectors) → if so, sets `is_verification = true`.
7. Inserts into [`akashic_scans_pending`](#akashic_scans_pending) and returns `process_id`.

### Action: `pulse`

1. Validates JWT.
2. Fetches the pending scan by `process_id`.
3. **Timing validation**: Rejects if `now < expected_completion_time - (total_duration × 0.05)`.
4. For each block in `block_scores`:
   - If block not in [`akashic_sectors`](#akashic_sectors): **New discovery** — full score, insert sector, credit machine + faction IPs.
   - If block already exists: **Verification** — 25% score, increment `verification_count`.
5. Credits `akashic_score` on [`network_addresses`](1_core_tables.md#network_addresses) for machine IP and faction IP.
6. Moves record from [`akashic_scans_pending`](#akashic_scans_pending) to [`akashic_scans_completed`](#akashic_scans_completed).

### Action: `status`

1. If `process_id` provided: Returns progress info for that specific scan.
2. Without `process_id`: Returns all active scans for player's machines (by ownership chain).

---

## Client Integration

The [`decrypt-records`](src/terminal/akashicScannerCommand.js) command:

1. **Init**: Calls `akashic-mining/start` to register the batch, receive `block_speed_ms` and `expected_completion_time`.
2. **Animation**: Uses `block_speed_ms` for frame timing (`await sleep(serverBlockSpeedMs)`), synchronizing the visual with the server's expected pace.
3. **Pulse**: After all 5 blocks complete, waits until `expected_completion_time - 5% buffer`, then calls `akashic-mining/pulse` with accumulated `block_scores`.
4. **Recovery**: On page refresh, `akashic-status` command queries active scans and can resume the visualizer at the correct progress point.

### Compute Speed Formula

| Hardware | Contribution | Example (Basic CPU) |
|----------|-------------|---------------------|
| CPU: 1 core × 1000 MHz | 1,000 | 1,000 |
| RAM: 1333 MHz × 0.5 | 666.5 | 666 |
| Network: 100 Mbps × 10 | 1,000 | 1,000 |
| **Total Compute** | | **2,666** |
| **Block Speed** | `12,000,000 / 2,666` | **~4,501 ms** |
| **5-Block Batch ETA** | `4,501 × 5 × 1.10` | **~24.8 seconds** |

Upgrading hardware (better CPU, RAM, NIC) directly increases mining speed and reduces batch completion time.