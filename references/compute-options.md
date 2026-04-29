# Compute options - pick the right runtime

## Quick chooser

| Workload | Best | When NOT to pick |
|---|---|---|
| HTTP web app, container | **Container Apps** | Need full K8s; need Linux pod-level networking; >10 svcs with mesh |
| HTTP web app, code-not-container | **App Service** | Fine-grained scale per route; DAPR; scale-to-zero |
| Many microservices, advanced needs | **AKS** | Most teams. Container Apps does this with less ops |
| Event-triggered short jobs | **Functions Flex Consumption** | >15min runtime; need always-warm; need VNet (use Premium then) |
| Long-running jobs / GPU / HPC | **Batch** or **AKS spot** | One-off short jobs (use Functions) |
| Lift-and-shift OS-locked apps | **VM Scale Set** | Anything that runs as a container (use CA) |
| Static frontend | **Static Web Apps** | Server-side rendering required (use App Service) |

## Container Apps (default for new container workloads)

Why default: serverless containers, scale-to-zero, KEDA-based scalers, DAPR for service mesh-lite, Workload Profiles for predictable perf, VNet integration, revisions for blue-green.

Patterns:
- **Consumption plan**: scale-to-zero, pay per request. Best for bursty / dev / cheap prod.
- **Workload profiles**: dedicated CPU/memory pools (D-, E-, GPU). Best for sustained prod or memory-heavy apps.
- **Internal env**: ingress only inside VNet - for backend services that don't face users.
- **External env**: public ingress with built-in TLS + custom domains.

Bicep: `bicep/modules/container-apps-env.bicep` + `container-app.bicep`.

Gotchas:
- Cold start ~1–3s on Consumption (use min replicas=1 if you need sub-second).
- Sticky sessions: not native; use Front Door affinity cookie if needed.
- WebSocket: supported. SSE: supported. Long-lived connections: yes.
- Scale rule: HTTP, KEDA (Service Bus, Event Hubs, Cosmos, etc.), or CPU/memory.

## App Service

Picks: when the workload is built as a process (Node, .NET, Python, Java) without containerization, or when the team's familiar with App Service ops.

Plans:
- **F1/D1**: free/shared, dev only.
- **B1–B3**: basic, no slot/auto-scale, dev/test.
- **S1+**: standard with slots + auto-scale.
- **P1v3+**: premium with VNet integration, larger SKUs.
- **I1v2+**: isolated (App Service Environment v3) for full network isolation.

Patterns:
- Use **deployment slots** for blue-green (`staging` slot → swap into `production`).
- Use **VNet integration** + private endpoints on data tier.
- App Settings → **Key Vault references** (`@Microsoft.KeyVault(SecretUri=...)`); never raw secrets.

Gotchas:
- B-tier doesn't support slots or VNet integration.
- Always-on must be enabled for non-static apps (otherwise idle apps unload).
- WebJobs deprecated path; use Functions instead.

Bicep: `bicep/modules/app-service.bicep`.

## Functions

Plans:
- **Consumption**: classic serverless; cold start; no VNet.
- **Flex Consumption (2024+)**: serverless + VNet + concurrency control. Default for new Functions.
- **Premium**: always-warm + VNet + larger memory.
- **Dedicated (App Service plan)**: shares App Service; rare choice.

Triggers covered: HTTP, Timer, Service Bus, Event Hub, Event Grid, Queue Storage, Blob, Cosmos change feed, Kafka, RabbitMQ.

Patterns:
- HTTP-triggered API: prefer Container Apps unless you want fine-grained per-function scale or use Durable Functions.
- Timer-triggered cron: Functions Consumption is unbeatable cost.
- Event-triggered processors: Functions Flex with managed identity reading from Event Hub / Service Bus.

Bicep: `bicep/modules/function-app.bicep`.

## AKS

Pick AKS only if you can answer "yes" to ≥2:
- Need Istio or Linkerd service mesh.
- Need GPU node pools with bin-packing.
- > 10 microservices already on K8s elsewhere.
- Compliance demands K8s-specific controls (PSPs, OPA Gatekeeper).
- Team has K8s expertise.

Otherwise: Container Apps. Less ops, fewer footguns.

If AKS:
- **Cluster autoscaler** + **multiple node pools** (system + workload + spot).
- **Azure CNI Overlay** for sane networking (vs. kubenet legacy).
- **Workload Identity** (federated MI per pod, no secrets in pods).
- **AGIC** (Application Gateway Ingress Controller) or **NGINX ingress** + AGW external.
- **AKS Automatic** if available in your region - opinionated managed AKS.
- **Azure Monitor for containers** + **Container Insights**.

## VMs

Last resort. If you must:
- **VM Scale Set** (not single VM) for HA.
- **Managed disks** + **trusted launch** for security.
- **Azure Bastion** for SSH/RDP (no public IP on VMs).
- **Azure Backup** + **Azure Site Recovery** for prod.
- **JIT VM access** via Defender for Cloud.

## Decision quick tests

- "I need autoscale to zero" → Container Apps Consumption or Functions Flex.
- "I need WebSockets / SSE" → Container Apps or App Service P-series (B-series doesn't).
- "I need VNet" → Container Apps (default), App Service P1v3+, Functions Flex/Premium, AKS.
- "I need GPU" → AKS GPU pool, or Container Apps GPU profiles (workload profile env).
- "I need DAPR" → Container Apps native; otherwise self-host on AKS.
- "I need predictable cost" → reserved capacity App Service plan or Container Apps workload profile, not Consumption.

## Cost shape

Rough monthly for "small prod" (1 web app, modest traffic):
- Container Apps Consumption with min=1, ~5M requests: ~$30–$50.
- App Service P1v3: ~$120 base + storage.
- Functions Flex 1M req/mo: ~$15–$25.
- AKS: $73 base for control plane + nodes (any tier you pick) → typically $200+ even for small.
- VM Scale Set 2× B2ms: ~$120 + disk.

Container Apps wins on $/value for most new workloads.
