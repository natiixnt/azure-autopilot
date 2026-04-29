# Architecture decisions - the framework

Don't ask the user to name services. Ask what they're building, then pick. Here's the decision tree the skill should run mentally.

## 5 questions that drive 80% of decisions

1. **What is the workload shape?** stateless web → batch → event-driven → ML → IoT. Picks compute family.
2. **What is the data shape?** OLTP → document → blob → analytics → time-series. Picks data layer.
3. **Who consumes it?** internal employees → external customers → anonymous → B2B partners. Picks identity + ingress.
4. **Where does it run from?** single region → paired region → multi-region active → on-prem hybrid. Picks networking + DR.
5. **What's the budget envelope?** scrappy → standard → enterprise. Picks SKUs + reserved capacity strategy.

## Workload shape → compute mapping

```
HTTP request/response, low ops               → Container Apps (default) or App Service
Many small APIs, polyglot, internal mesh     → Container Apps (internal env), or AKS if >10 services
Event-triggered short jobs                   → Functions (Flex Consumption)
Long-running CPU/GPU                         → Batch / AKS spot
Lift-and-shift VM                            → VM Scale Set (avoid single VMs)
Static frontend                              → Static Web Apps
WebSockets / SSE / long-lived                → Container Apps (handles WS) or AKS
Realtime (sub-100ms global)                  → Container Apps multi-region + Front Door
```

Rule: prefer **Container Apps** over AKS unless you have a real reason for full Kubernetes (custom CRDs, Istio, GPU pools with bin-packing, >10 service catalog). Container Apps gives 90% of the value at 20% of the ops cost.

## Data shape → data service mapping

```
OLTP relational, MS shop, modest volume      → Azure SQL (Hyperscale > 1 TB)
OLTP relational, OSS, modest volume          → Azure Database for PostgreSQL Flexible Server
OLTP global writes / multi-region active     → Cosmos DB (NoSQL API)
Document store / flexible schema             → Cosmos DB (NoSQL API)
Cache / session                              → Redis Cache
Files (logs, parquet, media, backup)         → Storage Account (Blob v2)
Analytical big data                          → ADLS Gen2 + Synapse / Fabric
Search + vector                              → Azure AI Search
Time-series / telemetry                      → Azure Data Explorer (or Eventhouse in Fabric)
Graph                                        → Cosmos DB Gremlin API (or Neo4j on VM if heavy)
Queue (transactional, ordered, dead-letter)  → Service Bus
Pub/sub fan-out                              → Event Grid
High-throughput streaming (Kafka-like)       → Event Hubs
```

Rule: don't use the same database for OLTP + analytics. Hot path → SQL/Cosmos; analytical reads → Synapse/Fabric reading from ADLS or via Mirroring.

## Audience → identity + ingress

```
Workforce only                               → Entra ID, internal Front Door + private endpoints
External users in your tenant (B2B)          → Entra ID guest accounts (External ID for B2B)
Customers signing up to your SaaS            → Entra External ID for customers
Anonymous public                             → Front Door (public) → App Gateway WAF if needed
B2B API consumers                            → APIM with subscription keys + OAuth client credentials
```

## Region strategy

```
Internal tool, no SLA pressure               → Single region, paired region as cold DR (recovery via backup restore)
Standard prod                                → Single primary region + warm passive (Azure Site Recovery / DB geo-replication)
99.95+%                                      → Two regions active-active (Front Door multi-origin, Cosmos multi-write, traffic split)
Global low-latency                           → Multi-region active + Front Door anycast + Cosmos multi-write
```

Rule: don't promise multi-region without dedicating ~30–50% extra budget AND ~2× ops complexity. "Active-active" needs idempotent writes, conflict resolution, traffic management, sync infrastructure.

## Budget shape → SKU patterns

```
Scrappy (<$500/mo)
  - Container Apps Consumption + scale-to-zero
  - Azure SQL serverless (auto-pause)
  - KV Standard
  - LA pay-as-you-go (caps if scared)
  - Front Door Standard
  - Storage LRS
  - No Defender plans except free baseline

Standard ($500–$10k/mo)
  - Container Apps with min replicas + dedicated workload profile
  - Azure SQL S0–S2 (or PG B-series Flex)
  - KV Premium
  - App Insights + LA with retention 90d
  - Front Door Standard or Premium
  - Storage GRS for prod
  - Defender on App Services + KV + Storage + Servers if VMs

Enterprise (>$10k/mo)
  - AKS or full Container Apps with VNet + Premium SKUs
  - Azure SQL Hyperscale or Cosmos Multi-region
  - Premium KV with HSM-backed keys (BYOK)
  - APIM Premium for SLA + multi-region
  - Front Door Premium with WAF + DDoS Std
  - Storage RA-GZRS
  - Defender Servers P2 + all data plans
  - Sentinel + Purview
  - PIM, Conditional Access, customer-managed keys
  - ExpressRoute (10 Gbps+), redundant circuits
```

## Default opinionated choices (when no contradicting input)

When the user says "build a SaaS app on Azure", default to:
- **Compute**: Azure Container Apps (consumption + workload profiles for prod)
- **Database**: Azure Database for PostgreSQL Flexible Server (or Azure SQL if MS shop)
- **Cache**: Redis Cache (Standard tier; Premium if persistence/cluster needed)
- **Identity**: Entra ID + managed identities for service-to-service; Entra External ID for customer sign-in
- **Ingress**: Front Door Standard with WAF + custom domain
- **Secrets**: Key Vault Standard with private endpoint + RBAC mode (not vault access policies)
- **Storage**: Storage Account v2, LRS dev / ZRS prod, blob private endpoint
- **Container registry**: ACR Standard with private endpoint + admin user disabled
- **Observability**: One LA workspace per env; App Insights in workspace mode
- **CI/CD**: GitHub Actions OIDC; Bicep what-if on PR; deploy on merge to main; environments gating prod
- **Networking**: VNet with subnets `compute`, `data`, `mgmt`; private endpoints on data; NSG default-deny
- **Cost**: tags policy enforced; per-RG budget at $X (set with user) with 50/80/100% alerts to action group; no premium SKUs in Dev sub
- **Region**: closest to user audience (PL → `westeurope` or `polandcentral`); paired region for DR

When user says "for an app that needs LLM features": same as above + Azure OpenAI + AI Search; pattern `ai-app.md`.

## When to push the user back

If the user says they want X but the right answer is Y, say so:

- "We need Kubernetes" → "What's pulling you toward AKS specifically? Container Apps handles 90% of these cases at less ops. Real reasons: custom controllers, Istio mesh, GPU bin-packing, >10 service catalog." Push back unless they have one.
- "Single VM with everything on it" → "OK for proof-of-concept; for prod: split into PaaS pieces or risk one-VM-of-doom. Costs and reliability both improve."
- "Public endpoints on SQL because it's simpler" → "Costs you maybe 1h to do private endpoint; saves you a CVE response down the line. Default to private."
- "Multi-region active-active for 99.99%" → "You'll pay 2× minimum. Have you measured what 99.95% single-region buys you and is the gap real?"
- "Cosmos DB because 'NoSQL is fast'" → "What's the access pattern? If single-key reads + writes at scale: yes. If you have joins or BI queries: SQL is faster + cheaper. Don't choose Cosmos for vibes."
- "OpenAI gpt-4 mini for everything" → "For deterministic structured tasks, smaller models or non-LLM logic might be 100× cheaper. What's the actual task?"

The skill's job is to be a senior architect, not a yes-machine.
