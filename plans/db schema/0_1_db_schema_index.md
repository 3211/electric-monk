# Database Schema Index

This index provides a modular view of the Holy War Online database schema. For the authoritative, single-file reference, see [`db_schema.md`](./db_schema.md).

## Schema Modules

- [**Core Tables & Player Identity**](./core_tables.md)
  - `network_addresses`
  - `sects`
  - `players`
  - *RPCs: Signup, Onboarding, Network Allocation*
- [**Virtual Computing**](./2_virtual_computing.md)
  - `virtual_machines`
  - `virtual_files`
  - `virtual_logs`
  - *RPCs: Encryption Calculation*
- [**Network & Connection Tracking**](./3_network_connections.md)
  - `connection_logs`
  - *RPCs: Connection Analysis*
- [**Hardware Catalogs**](./4_hardware_catalogs.md)
  - `hardware_shops`
  - `catalog_cpus`, `catalog_memory`, `catalog_storage`, etc.
- [**Akashic Record Mining**](./5_akashic_mining.md)
  - `akashic_sectors`
  - `akashic_scans_pending`
  - `akashic_scans_completed`
  - *RPCs: Compute Speed, Block Timing, Mining Operations*
  - *Edge Function: `akashic-mining` (start, pulse, status)*

## Reference
- [Authoritative Source (Full File)](./db_schema.md)
- [Migration Status](../migrations.md)
