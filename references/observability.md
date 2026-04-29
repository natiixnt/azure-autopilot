# Observability - Log Analytics, App Insights, alerts, dashboards

## Default architecture (one per environment)

```
Log Analytics workspace (la-<project>-<env>-<region>)
├── App Insights (workspace-based) for compute resources
├── Diagnostic settings from every PaaS resource
├── NSG flow logs + traffic analytics
├── Defender for Cloud findings
├── Activity log
└── (optional) Sentinel
```

One LA per environment, not per resource. Cross-resource queries get easy.

Bicep: `bicep/modules/log-analytics.bicep` + `app-insights.bicep` + `diagnostic-settings.bicep`.

## Log Analytics

Pricing tiers:
- **Pay-as-you-go**: ~$2.30/GB ingested (varies by region).
- **Commitment tiers** (100/200/500/1000+ GB/day): 15–30% discount. Switch when steady > 80% of tier limit.
- **Basic Logs**: cheaper for high-volume low-query data (e.g. raw firewall logs); 8d retention; query has $.
- **Auxiliary Logs** (2024+): even cheaper for archival.

Defaults:
- **Retention**: 30d for non-prod, 90d for prod (extend to 2y for compliance via archive).
- **Daily cap**: set in non-prod to prevent runaway bills.
- **Tables**: opt-in to "Basic" for noisy tables (NSG flow logs, AzFW logs).

Defaults to apply via Azure Policy (`policies/diag-settings-required.json`):
- Every supported resource sends diagnostic settings to the workspace.
- Audit log diagnostic to a long-retained table.

## App Insights

Workspace-based AI = AI data lives inside the LA workspace. Default for new builds (legacy classic AI is deprecated for new resources).

Wire-up:
- Bicep creates AI resource bound to the LA workspace.
- Compute resources (App Service, Function, Container App) get AI auto-instrumentation enabled or use SDK.
- Connection string in App Setting `APPLICATIONINSIGHTS_CONNECTION_STRING` (KV reference, MI-fetched).

Patterns:
- **Auto-instrumentation** for App Service (set `ApplicationInsightsAgent_EXTENSION_VERSION=~3` and `XDT_MicrosoftApplicationInsights_Mode=recommended`).
- **OpenTelemetry SDK** for Container Apps / AKS - code-side; export to AI via OTel endpoint.
- **Live Metrics** for real-time perf during deploys.
- **Profiler + Snapshot Debugger** for prod CPU/memory issues (App Service / VMs).

Custom metrics + traces:
- Use OTel naming convention (`http.server.request.duration`, etc.).
- Add custom dimensions for tenant_id, feature_flag, model_used (AI apps), etc.

## Alerts (the ones that matter)

Default alert rules (deployed by `bicep/modules/action-group.bicep` + alert rules per resource):

| Signal | Threshold | Severity |
|---|---|---|
| App Insights `requests/failed` rate | > 5% over 5min | Sev2 |
| App Insights p95 latency | > 1s over 10min | Sev3 |
| App Service unhealthy hosts | > 0 | Sev2 |
| Container App revision failed | any | Sev2 |
| KV vault throttling | > 0 | Sev3 |
| SQL DTU/CPU | > 80% sustained 15min | Sev3 |
| Cosmos 429s | > 100/min | Sev3 |
| Service Bus dead-letter | > 0 | Sev3 |
| Storage availability | < 99% | Sev2 |
| Defender critical recommendation | new | Sev2 |
| Subscription budget | 80% / 100% | Sev3 / Sev1 |

Action group: email + Teams webhook + (optional) PagerDuty / Opsgenie.

## Workbooks + dashboards

For each pattern, a curated Workbook is deployed alongside resources:
- **Web app workbook**: latency / throughput / failure / dependency map.
- **AI app workbook**: tokens used / model / cost per user / latency.
- **Data platform workbook**: pipeline runs, SLA, data freshness.
- **Cost workbook**: per-RG / per-service / forecast.

Bicep: `Microsoft.Insights/workbooks`. Deploy from JSON template in `templates/workbooks/`.

## OTel / cross-platform

Tools that emit OTel can ship directly to App Insights via the OTel endpoint, no Azure SDK lock-in. Supports JS, Python, .NET, Java, Go.

Distributed tracing: enable W3C trace context. AI shows the dependency map across services automatically.

## Sentinel (SIEM)

Add when:
- Compliance requires SIEM.
- > 10 employees or external user base.
- Anomaly detection is a need.

Sentinel sits ON TOP of LA - same workspace, different SKU/features. Connectors:
- Azure Activity, Sign-ins, Audit logs.
- Microsoft 365 (Defender, Purview).
- 3rd party (Cisco, Palo Alto, etc.).

Typical retention: 90d in LA hot, then archive longer.

## Probes

```bash
# Verify diagnostic settings on a resource
az monitor diagnostic-settings list --resource <resource-id>

# Recent ingestion to LA from a resource
az monitor log-analytics query --workspace <id> --analytics-query \
    "AzureDiagnostics | where ResourceId =~ '<id>' | summarize count() by bin(TimeGenerated, 1h)"

# Active alerts
az monitor scheduled-query list -g <rg>
```

`scripts/observability.sh` automates the wire-up + verification.
