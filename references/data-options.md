# Data options - picking storage that won't bite you

## Relational

### Azure SQL Database
Service tiers:
- **General Purpose Serverless** (auto-pause): dev/test, low-traffic prod, save 50–80% on idle.
- **General Purpose Provisioned**: predictable prod, vCores 2–80.
- **Business Critical**: in-memory + read replica + faster failover.
- **Hyperscale**: > 100GB or fast page-restore needed; storage up to 100TB.

Defaults to set:
- **AAD-only auth** (disable SQL auth): `Set-AzSqlServerActiveDirectoryAdministrator` + `az sql server ad-admin`.
- **Managed identity** for app access; no connection string passwords.
- **Private endpoint** for prod; **deny public network access**.
- **TDE** on (default).
- **Long-term retention** (LTR) policy if compliance needs.
- **Failover group** for cross-region DR.

Bicep: `bicep/modules/sql-server.bicep`.

Pitfalls:
- Don't put dev/test on same server as prod - share connection limits + perf.
- Hyperscale is one-way (can't downgrade to GP without export/import).
- Free vCore / DTU calculator before committing.

### Azure Database for PostgreSQL Flexible Server
Default for OSS workloads.

Defaults:
- **AAD authentication** (Microsoft Entra ID + PostgreSQL roles mapped to Entra users).
- **Private access** (VNet-injected) for prod.
- **High availability** (zone-redundant) for prod; single-zone OK for dev.
- **Backups** with PITR (default 7 days; up to 35 days for prod).
- **Read replica** for cross-region DR.
- **Server parameters** as code (`pg_stat_statements`, `auto_explain`).

Bicep: `bicep/modules/postgres-flexible.bicep`.

Pitfalls:
- VNet injection is permanent - pick the right subnet day 1.
- Burstable B-series fine for dev, NOT for prod (CPU credits exhaust).
- Major version upgrade requires brief downtime; plan window.

### Azure Database for MySQL Flexible Server
Same shape as Postgres Flexible. Used when the workload needs MySQL specifically.

## Document / NoSQL

### Cosmos DB

API choice (one-way decision):
- **NoSQL (default)**: best feature set; new builds.
- **MongoDB API**: only if migrating from MongoDB; for Mongo at scale prefer **Cosmos DB for MongoDB vCore** (different product).
- **Cassandra**: migration only.
- **Gremlin (graph)**: graph workloads.
- **Table**: legacy; use Storage Tables instead for new.
- **PostgreSQL (Citus)**: distributed Postgres for huge OLTP; niche.

Throughput models:
- **Provisioned RU/s**: predictable; reserve via 1-yr / 3-yr.
- **Autoscale**: bursty workload; min RU/s = 10% of max.
- **Serverless**: dev/test or genuinely low traffic (< 1M RU/day); cost spikes if you misuse.

Multi-region:
- **Single write region** + read replicas: simple; cheap.
- **Multi-master (multi-write)**: active-active; conflict resolution policies needed.
- Pick **strong consistency** only if you must (it pins you to single region writes); default **session**.

Defaults:
- **Disable public access** + **private endpoint**.
- **Managed identity** access (RBAC for data plane).
- **Backup policy**: continuous (PITR) for prod.
- **Diagnostic logs** to LA.

Bicep: `bicep/modules/cosmos.bicep`.

Pitfalls:
- Wrong partition key = hot partitions = throttling. Pick high-cardinality + even-access keys. Don't change later.
- Indexing all paths by default → CPU + RU eaten. Use **opt-in** indexing for high-cardinality fields.
- Cross-partition queries are expensive - design schema to query within partition.
- Cosmos serverless has hard 1M RU/s burst cap; not for prod scale.

## Cache

### Azure Cache for Redis
Tiers:
- **Basic**: dev only (no SLA, no failover).
- **Standard**: 99.9% (primary + replica).
- **Premium**: 99.95%, persistence (AOF/RDB), VNet, clustering, geo-replication.
- **Enterprise / Enterprise Flash**: 99.99% with Redis Modules (RediSearch, etc.) and active-active geo.

Patterns:
- Session store, distributed cache, rate limiting.
- Pub/sub for short messaging (NOT durable - use Service Bus for that).
- Vector search via RediSearch in Enterprise tier.

Defaults:
- **Premium for prod** with persistence + private endpoint.
- **AAD auth** (preview-stable; replaces access keys).
- **TLS only**.

Pitfalls:
- Wrong eviction policy → cache misses spike.
- Sub-ms expectations require placing Redis in same region as compute.

## Object storage

### Storage Account (Blob v2 / ADLS Gen2)
Uses: blob, queue, table, file. Hierarchical namespace = ADLS Gen2 = analytics workloads.

Tiers:
- **Hot**: frequent access; default for working set.
- **Cool**: lower cost, higher access $; ≥ 30d minimum.
- **Cold** (2024+): even lower; ≥ 90d minimum.
- **Archive**: ≤ $1/TB/mo; rehydrate hours; compliance archive.

Replication:
- **LRS**: dev only.
- **ZRS**: zone-redundant; default for prod.
- **GRS / GZRS**: cross-region async.
- **RA-GRS / RA-GZRS**: read-access secondary; useful for read-heavy with DR.

Defaults:
- **Disable public network access** + **private endpoint** per blob/dfs/queue endpoint.
- **Allow trusted MS services** for diagnostics integration.
- **Soft delete** + **versioning** + **point-in-time restore**.
- **Lifecycle management**: tier-down rules (Hot → Cool at 30d, Cool → Archive at 180d).
- **Customer-managed key** if compliance requires.

Bicep: `bicep/modules/storage.bicep`.

Pitfalls:
- Not enabling soft-delete → accidental delete is unrecoverable.
- Mixing analytics (ADLS) and app blobs in same account → quota + perf interactions; use separate accounts.

## Search + vector

### Azure AI Search (formerly Cognitive Search)
For: full-text, vector, hybrid retrieval, RAG over enterprise data.

Tiers:
- **Free**: dev/POC.
- **Basic**: small prod (< 2GB).
- **Standard S1–S3**: prod scale.
- **Storage Optimized L1–L2**: cheap large indexes (slower QPS).

Defaults:
- **Semantic ranker** enabled.
- **Vector search** with HNSW.
- **Indexers** for ADLS / SQL / Cosmos / SharePoint.
- **AAD auth** (no API keys).
- **Private endpoint** for prod.

Bicep: `bicep/modules/ai-search.bicep`.

## Time-series

### Azure Data Explorer (ADX) - also via **Eventhouse** in Fabric
For high-volume telemetry, logs, IoT, security analytics. Sub-second over TB.

Default for: > 10M events/day, KQL is OK with the team.

Alt: Log Analytics for log-only workloads + Sentinel for security; that's same engine but managed.

## Analytical

### Microsoft Fabric (lakehouse + warehouse + Power BI)
Default for new analytics workloads in 2026. See sister skill `powerbi-implementation` for details.

Components:
- **Lakehouse**: parquet + delta + Spark.
- **Warehouse**: T-SQL serverless on delta.
- **Data Factory**: ETL pipelines.
- **Real-Time Intelligence**: streaming + KQL.
- **Power BI** semantic models with Direct Lake.

Pre-Fabric stack (still maintained):
- **Synapse Analytics** (workspace with serverless SQL pool, dedicated SQL pool, Spark pool) - choose only if existing investment.
- **Azure Data Factory** standalone - fine if you want pipelines without the rest of Fabric.
- **Azure Databricks** - when team prefers Databricks notebooks + Spark; integrates fine with Azure.

## Messaging (mentioned for completeness; details in `messaging.md`)

| Need | Pick |
|---|---|
| Transactional queue with sessions, dead-letter, scheduling | **Service Bus** |
| Pub/sub event router (CloudEvents-style) | **Event Grid** |
| Streaming ingest (Kafka-compatible) | **Event Hubs** |
| Lightweight queue, simple FIFO | **Storage Queue** (cheap; no advanced features) |

## Decision shortcuts

- "Need OLTP, MS shop" → **Azure SQL** (Hyperscale if >100 GB).
- "Need OLTP, OSS" → **Postgres Flexible**.
- "Need global-write document store" → **Cosmos NoSQL multi-write**.
- "Need search + RAG" → **AI Search** + **Azure OpenAI**.
- "Need analytics" → **Fabric Lakehouse** (or Synapse if existing).
- "Need cache" → **Redis Premium** for prod.
- "Need files" → **Storage Blob** (or Azure Files if SMB/NFS protocol needed).

## Backup + DR matrix

| Service | Backup | Cross-region |
|---|---|---|
| Azure SQL | Auto (PITR 7–35d, LTR up to 10y) | Failover group + active geo-replication |
| Postgres Flex | Auto PITR | Cross-region read replica + promote |
| Cosmos | Continuous (PITR) | Multi-region replica or multi-write |
| Storage | Soft-delete + versioning | GRS/GZRS replication |
| KV | Soft-delete + purge protection | Geo-redundant by default |
| AI Search | Snapshot via REST API | Manual replication to second region |
| Redis | Premium AOF/RDB persistence | Geo-replication (Premium+) |
| VMs | Recovery Services Vault | Azure Site Recovery |

Test restore at least quarterly in non-prod. "Backup not tested = no backup."
