# Network & Connection Tracking

This module handles the registry of all network connections between IPs, tracking encryption levels, and metadata for analysis.

## Related Helper Functions (RPCs)

| Function | Parameters | Returns | Description |
|----------|------------|---------|-------------|
| `calculate_encryption(p_ip1, p_ip2)` | `inet, inet` | INT | Returns the product of two IPs' encryption levels (for connection calculations). |
| `get_connections_by_encryption(p_min_encryption, p_max_encryption)` | `BIGINT, BIGINT` | TABLE | Returns connections within encryption range (default: 1 to max). Limited to 1000 results. |
| `get_connection_stats(p_ip1, p_ip2)` | `inet, inet` | JSON | Returns statistics between two IPs: total connections, bytes transferred, average encryption, last connection time, active connections. |

---

## `connection_logs`

Master registry of all network connections between any two IP addresses. Automatically calculates combined encryption levels and tracks connection metadata.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `log_id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Unique connection record |
| `from_ip` | inet | NOT NULL, FK → network_addresses(ip_address) ON DELETE CASCADE | Source IP initiating connection |
| `to_ip` | inet | NOT NULL, FK → network_addresses(ip_address) ON DELETE CASCADE | Destination IP receiving connection |
| `connection_type` | VARCHAR | NOT NULL DEFAULT 'data_transfer' | Type: `data_transfer`, `attack_probe`, `file_transfer`, `command_control`, etc. |
| `status` | VARCHAR | NOT NULL DEFAULT 'established' | Connection state |
| `port` | INT | | Network port used |
| `protocol` | VARCHAR | DEFAULT 'TCP' | Protocol used |
| `bytes_transferred` | BIGINT | DEFAULT 0 | Total payload size |
| `packets_count` | INT | DEFAULT 0 | Packet count |
| `from_encryption_level` | INT | | Auto-populated from network_addresses |
| `to_encryption_level` | INT | | Auto-populated from network_addresses |
| `combined_encryption_level` | BIGINT | | Product of from_encryption_level * to_encryption_level (defaults to 1 for null/missing) |
| `initiated_at` | TIMESTAMPTZ | DEFAULT now() | Connection start time |
| `terminated_at` | TIMESTAMPTZ | | Connection end time |
| `duration_ms` | INT | | Calculated duration in milliseconds |
| `session_id` | UUID | | Optional session grouping identifier |
| `is_encrypted` | BOOLEAN | DEFAULT false | True if combined_encryption_level > 1 |
| `was_spoofed` | BOOLEAN | DEFAULT false | Whether source was masked |
| `trace_attempted` | BOOLEAN | DEFAULT false | Whether a trace was attempted |

**Indexes:**
- `idx_connection_logs_from_ip` on `from_ip`
- `idx_connection_logs_to_ip` on `to_ip`
- `idx_connection_logs_initiated_at` on `initiated_at DESC`
- `idx_connection_logs_from_to_time` on `(from_ip, to_ip, initiated_at DESC)`
- `idx_connection_logs_combined_encryption` on `combined_encryption_level`
- `idx_connection_logs_type_status` on `(connection_type, status)`
- `idx_connection_logs_active` on `(from_ip, to_ip)` WHERE `terminated_at IS NULL`
- `idx_connection_logs_session` on `session_id` WHERE `session_id IS NOT NULL`

**RLS Policies:**
- ALL: Service role full access
- SELECT: Authenticated users can view connections involving their IP or their VMs (from_ip or to_ip matches player IP or owned VM IPs)
- SELECT: Public (anon) can view connections involving sect IPs

**Triggers:**
- `calculate_connection_encryption_trigger`: Before INSERT/UPDATE, auto-populates from_encryption_level, to_encryption_level, combined_encryption_level (product), and is_encrypted flag.
- `calculate_connection_duration_trigger`: Before INSERT/UPDATE, calculates duration_ms from initiated_at and terminated_at.
