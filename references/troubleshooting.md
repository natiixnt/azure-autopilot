# Troubleshooting - top errors → fixes

## Auth + RBAC

| Error | Fix |
|---|---|
| `AuthorizationFailed` on `az` command | SP/user lacks role at scope; check `az role assignment list --assignee <id> --scope <scope>` |
| MI can't access KV | RBAC mode without role assignment; assign `Key Vault Secrets User` to MI |
| MI can't pull from ACR | Assign `AcrPull` to MI on ACR resource |
| App Service can't reach KV reference | App Service identity → `Key Vault Secrets User` on KV; KV in RBAC mode; KV publicly accessible OR private endpoint reachable from App Service VNet |
| GitHub Actions OIDC fails: `AADSTS70021` | federated credential subject doesn't match the workflow's `sub` claim. Confirm `repo:owner/repo:environment:env-name` exact match |
| `Identity not found` after just creating UMI | Eventual consistency, wait 30–60s + retry |

## Networking

| Error | Fix |
|---|---|
| App can't resolve `*.privatelink.<svc>` | Private DNS zone not linked to VNet; or DNS forwarder not configured |
| App connects to PaaS but slow / inconsistent | DNS resolves to public IP (PE not used) → fix DNS link |
| Private endpoint shows but not approved | Check `properties.privateLinkServiceConnections[].properties.privateLinkServiceConnectionState`; `Approved` required |
| App Service VNet integration fails | Subnet not delegated to `Microsoft.Web/serverFarms`; or subnet too small (need /28 minimum, /27 recommended) |
| Container Apps env stuck in `Updating` | Subnet delegation issue or NSG blocking required ports; check delegation `Microsoft.App/environments` and NSG outbound rules to AzureCloud |
| Cross-tenant traffic via VNet peering blocked | Peering doesn't transit by default; configure UDR or use Virtual WAN |

## Bicep deployment

| Error | Fix |
|---|---|
| `InvalidTemplateDeployment` with circular dep | Restructure modules - use `existing` references or split deploys |
| `RoleAssignmentExists` | Used non-deterministic name; use `guid(scope, principal, role)` |
| `BadRequest` from KV: vault already exists | Soft-deleted vault with same name; either purge or pick a new name |
| `QuotaExceeded` for VM/cores | Open quota request via portal - cannot bypass via CLI |
| Storage account name conflict | Globally unique; add `uniqueString(resourceGroup().id)` to name |
| `SubscriptionNotFound` for cross-sub deploy | Deploying SP doesn't have access to target sub; assign Reader on the sub |

## Container Apps

| Error | Fix |
|---|---|
| Revision stuck `Provisioning` then `Failed` | Check `az containerapp revision show` → log shows image pull error / startup probe failure |
| Image pull fails | UMI assigned to CA must have `AcrPull` on ACR; CA must reference UMI in `registries[].identity` |
| App not receiving traffic | Ingress not enabled, or wrong target port; check `properties.configuration.ingress` |
| Scale-to-zero never wakes | HTTP scale rule misconfigured; ensure scale rule is `http` with `concurrency` setting |
| WebSocket disconnects after 4 min | Idle timeout default; use `properties.configuration.ingress.transport: "auto"` and ensure client sends keepalive |

## App Service

| Error | Fix |
|---|---|
| Deployment slot swap fails | App settings or connection strings differ; check warm-up endpoints |
| `appsettings` reference to KV shows literal `@Microsoft.KeyVault(...)` | App Service identity not granted KV access; or KV firewall blocks; check Identity blade + KV firewall |
| App Service P1v3 + VNet integration: `outbound IP changed` | When using VNet integration, outbound IP comes from NAT or VNet egress; allowlist that IP at upstream targets |
| Always-On not available | Tier doesn't support (B-series); upgrade to S1+ |

## SQL / Postgres

| Error | Fix |
|---|---|
| `Cannot connect to server` from app | Server firewall blocks; if PE'd, DNS resolution issue; if AAD-only, app using SQL auth |
| AAD auth fails | Server lacks AAD admin; or app's MI not granted DB user |
| Slow query after deploy | Stats out of date; rebuild stats; check execution plan |
| Connection pool exhaustion | Tier too low for connection count; or app not closing connections; raise tier or fix code |

## Cosmos DB

| Error | Fix |
|---|---|
| 429 throttling | Increase RU/s or switch to autoscale; check hot partition |
| Hot partition | Wrong partition key; analyze with metrics → diagnostic queries |
| `403 ForbiddenException` from app | Data plane RBAC role not assigned; assign `Cosmos DB Built-in Data Contributor` to MI |
| Multi-region writes returning stale data | Consistency level too weak for the use case; tighten to `Bounded Staleness` or `Strong` (lose multi-write) |

## Key Vault

| Error | Fix |
|---|---|
| `403 Forbidden` reading secret | RBAC role missing; or vault firewall blocks; or PE not in path |
| `Vault not found` after deletion | Soft-deleted vault still reserves the name; purge or pick new name (note: purge protection prevents this entirely) |
| `MaximumNumberOfSecrets` exceeded | 25k limit per vault; split into multiple vaults |

## OpenAI / AI services

| Error | Fix |
|---|---|
| `429 Too Many Requests` | Quota exceeded or PTU rate limit; check `Retry-After`, request quota increase, or shift to PTU |
| `404 DeploymentNotFound` | Deployment name vs model name confusion; deployment is what you create per model + sku |
| `ContentFiltered` blocking valid content | Adjust content safety filter via deployment policy; for known-safe domains, lower threshold |
| `403` from AI Search | Index not created; or RBAC role for indexer not assigned |

## Defender / Sentinel

| Error | Fix |
|---|---|
| Defender plan shows enabled, no findings | Resource needs minutes-to-hours to enroll; check resource Defender status individually |
| Sentinel ingestion delay | Connector not configured properly; check connector status; expect ~10 min latency |

## Activity log + diagnostics

| Symptom | Fix |
|---|---|
| No logs in LA from a resource | Diagnostic setting not configured; verify with `az monitor diagnostic-settings list` |
| Logs come in but late | LA ingestion delay (typically 1–5 min, can be 15 min); check `_LogReceivedTime` vs `TimeGenerated` |
| App Insights shows no traces | Connection string wrong, or instrumentation not loaded; check `APPLICATIONINSIGHTS_CONNECTION_STRING` is set + valid |

## Cost surprises

| Pattern | Fix |
|---|---|
| Defender plans on resources you don't own | Check subscription Defender status, disable per-plan |
| LA ingest spike | Set daily cap; identify noisy table |
| Egress charges spike | Cross-region traffic; consolidate region; use service endpoint or PE |
| Idle reserved capacity | Refund up to 50k/year; use Cost Management → Reservations → Utilization |

## Diagnostic helpers

```bash
# Recent activity log entries for a resource
az monitor activity-log list --resource-id <id> --max-events 20

# What's deployed in this RG
az resource list -g <rg> -o table

# What changed recently (last 14d)
az monitor activity-log list --resource-group <rg> --max-events 100 \
  --query "[?operationName.value=='Microsoft.Resources/deployments/write'].{time:eventTimestamp,who:caller,what:resourceId}"

# Resource Graph: complex inventory query
az graph query -q "Resources | where type =~ 'microsoft.web/sites' | project name, location, tags"
```
