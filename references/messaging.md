# Messaging - Service Bus, Event Grid, Event Hubs, Storage Queue

## Quick chooser

| Need | Pick |
|---|---|
| Transactional queue, exactly-once-ish, sessions, scheduling, dead-letter | **Service Bus** (queue or topic) |
| Pub/sub, fan-out events to N subscribers, CloudEvents | **Event Grid** |
| Streaming high-throughput (Kafka-like) | **Event Hubs** |
| Lightweight queue, cheap, basic FIFO | **Storage Queue** |

## Service Bus

Two shapes:
- **Queue**: 1-to-1 (one consumer group at a time).
- **Topic + Subscriptions**: 1-to-N with filter rules per subscription.

Pick Service Bus when:
- You need ordered delivery within a partition (sessions).
- You need scheduled delivery (e.g. process tomorrow at 09:00).
- You need dead-letter queue for poison messages.
- You need transactions across queue ops.

Tiers:
- **Basic**: queues only, no DLQ.
- **Standard**: topics + subs, AAD, 1MB messages.
- **Premium**: dedicated capacity, predictable perf, geo-DR, larger messages (up to 100MB), VNet.

Defaults:
- **Premium for prod** if reliability matters.
- **AAD auth** (no SAS).
- **Private endpoint** (Premium feature).
- **Dead-letter queue** wired with a processor function/app.
- **TTL** set on every queue (avoid infinite buildup).

Bicep: `bicep/modules/service-bus.bicep`.

Pitfall: Service Bus is NOT for stream processing. Use Event Hubs.

## Event Grid

Pub/sub event router. Push-based (not pull). Supports CloudEvents + Event Grid schema.

Use cases:
- React to Storage blob created → trigger Function.
- React to resource created in subscription → log to Sentinel.
- Custom topics for app-to-app events.
- MQTT broker (Event Grid namespaces support MQTT).

Defaults:
- Custom **topics** in their own namespace.
- **Dead-lettering** to Storage account.
- **Retry policy**: configurable, default 24h with exponential backoff.

Bicep: `bicep/modules/event-grid.bicep`.

## Event Hubs

High-throughput streaming. Kafka protocol-compatible. Use when ingesting >> 1000 events/sec.

Tiers:
- **Standard**: 1 MB/s per TU; up to 20 TU (or auto-inflate).
- **Premium**: dedicated; predictable perf; multi-region geo.
- **Dedicated**: full cluster, 10s of GB/s.

Defaults:
- **Capture** to Storage / ADLS automatically (parquet) for downstream analytics.
- **Schema Registry** for schema evolution (Premium).
- Partition count: align to expected consumer parallelism (default 4 fine for most).

Bicep: `bicep/modules/event-hub.bicep`.

Pattern: producers fire events → Event Hub → consumers (Stream Analytics, Functions, ADX, Fabric Eventstream) for processing → outputs (DBs, dashboards).

## Storage Queue

Cheapest queue. No advanced features. Up to 64KB messages. ~20K transactions/sec/queue. Auto-archive via lifecycle policy.

Pick when: you need a queue and nothing else, cost matters, FIFO not critical (Storage Queue is best-effort FIFO).

## Defaults across all messaging

- AAD auth (managed identity for senders/receivers).
- Diagnostic logs to LA.
- Alerts on dead-letter count > 0, throttling, connection failures.
- Schema versioning via JSON Schema or Protobuf in Schema Registry.
- Idempotent consumers (use message ID as dedup key when possible).
