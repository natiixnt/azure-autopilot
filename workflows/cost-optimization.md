## Workflow: Azure cost optimization sweep

For: bringing down monthly Azure spend without breaking prod. Typical realistic savings: 15–35%.

## Step 1: Baseline + breakdown (1 hour)

```bash
bash ~/.claude/skills/azure-autopilot/scripts/cost-report.sh --days 30 --group-by ResourceGroup > cost-by-rg.txt
bash ~/.claude/skills/azure-autopilot/scripts/cost-report.sh --days 30 --group-by ResourceType > cost-by-type.txt
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh stale-resources > stale.txt
```

Open in Cost Management:
- Total monthly spend.
- Forecast vs actual.
- Top 10 RGs.
- Top 10 services.
- Untagged spend (governance gap).

## Step 2: Quick wins (1 day; usually 5–15% saving)

| Action | Find | Fix | Saving |
|---|---|---|---|
| Delete unattached managed disks | `az disk list --query "[?managedBy==null]"` | `az disk delete` | $X |
| Delete unassociated public IPs | `az network public-ip list --query "[?ipConfiguration==null]"` | `az network public-ip delete` | small but free |
| Stop deallocated VMs that aren't deallocated properly | `az vm list -d --query "[?powerState=='VM running']" + check usage | Right-size or stop | varies |
| Delete empty RGs | `inventory.sh empty-rgs` | `az group delete -n <rg>` | clean-up only |
| Disable Defender plans on resource types you don't have | `az security pricing list` | `az security pricing create -n <plan> --tier Free` | per-resource savings |
| Reduce LA retention from 730 to 90 days | `az monitor log-analytics workspace show` | Update retention | up to 50% LA cost |
| Set LA daily cap on noisy non-prod workspaces | LA → Usage → Daily cap | Set 5–10 GB | prevents runaway |

## Step 3: Right-size + tier-down (3–5 days)

For each RG, look at:
- **VMs**: B-series (burstable) instead of D-series for dev/test. CPU credit usage in Metrics.
- **App Service plans**: B-series → S-series only if needing slots/scale; otherwise stay B.
- **SQL DTU/vCore**: check actual avg usage in Metrics; downsize if < 30% sustained.
- **Cosmos**: switch from provisioned to autoscale or serverless for spiky workloads.
- **Storage**: lifecycle policy Hot → Cool at 30d, Cool → Archive at 180d.
- **Redis**: Premium → Standard if persistence not needed.

## Step 4: Pause/resume non-prod (1 day; 30–50% savings on non-prod)

Schedule shutdowns via Logic Apps / Automation Runbooks:

```bash
# Example: stop VMs in dev RG every weekday 19:00
az automation runbook create --name "shutdown-dev" \
    --resource-group rg-platform-mgmt \
    --automation-account-name aut-platform \
    --type PowerShell

# Schedule it
```

Or via Container Apps min replicas = 0 (already scale-to-zero).
SQL serverless: auto-pause after 60 min idle.
Fabric F-SKU: `az fabric capacity pause` outside business hours.

## Step 5: Reservations + Savings Plans (after 30 days of stable usage)

For VMs sustained > 70% utilization:
```bash
az reservations catalog show --reserved-resource-type VirtualMachines
```

Buy 1y RIs for confirmed long-running VMs. Discount: 25–40%.

For App Service plans, SQL, Cosmos: same logic.

For mixed workloads: **Compute Savings Plan** (1y/3y) - more flexible than RI; ~20–30% off.

Refund / trade-in unused RIs (up to $50k/yr) - Cost Management → Reservations → Manage.

## Step 6: F-SKU pause (if Fabric in scope)

```bash
# Off-hours pause non-prod
az fabric capacity pause --resource-group rg-data --capacity-name fab-acme-dev
# Resume
az fabric capacity resume --resource-group rg-data --capacity-name fab-acme-dev
```

Schedule via Azure Logic App + cron.

## Step 7: Bigger architectural shifts (when justified)

| Shift | Saving | Effort |
|---|---|---|
| Move VMs to PaaS (App Service / Container Apps) | 30–60% on compute + ops | weeks |
| Replace Premium SQL with Hyperscale or Postgres Flexible | 20–40% | weeks |
| Replace 2-region active-active with active-passive | 50% on second region | week |
| Replace Cosmos provisioned with Direct Lake on Fabric | varies (read patterns) | weeks |
| Consolidate LA workspaces | minimal $$, big observability win | days |

## Step 8: Establish guardrails (so it doesn't drift back)

- **Tagging policy enforced** at MG level (`templates/policies/require-tags.json`).
- **Budgets** per RG with action group alerts at 50/80/100%.
- **SKU policy** for non-prod (deny VM > Standard_D4s_v5).
- **Weekly cost review** - `/schedule` agent runs `cost-report.sh` weekly, posts to Slack/Teams if spike.
- **Quarterly RI utilization review**.

## Cost optimization deliverable

```
# Cost optimization report - <Client>
Date: 2026-04-29
Baseline: $X/month

## Quick wins (implemented today)
- Delete N unattached disks: -$Y/mo
- Disable unused Defender plans: -$Z/mo
- LA retention 730 → 90d: -$W/mo
- Total: -$AB/mo (XX% saving)

## Right-sizing (this sprint)
- Downsize 3 over-provisioned VMs: -$X/mo
- Cosmos provisioned → autoscale: -$Y/mo

## Reservations (after Q2 usage data)
- Recommend buying RIs for: <list>
- Estimated annual saving: $X

## Architectural changes (Q3-Q4)
- ...

## New guardrails
- Tagging policy applied at MG level: <date>
- Budgets configured for all RGs: <date>
- Weekly cost review scheduled: <date>

## New baseline
$X → $Y/month (target)
```

## Common cost surprises to flag

- Egress charges from cross-region traffic.
- LA ingestion spike from a misconfigured app logging too much.
- Defender for Servers P2 left on dev VMs.
- ExpressRoute idle but charging.
- Premium tiers turned on "just in case" but not used.
- Reserved capacity not actually applied (mismatched type).
