# Cost control - tags, budgets, reservations

## Tagging policy (do this BEFORE any resources)

Required tags on every RG and resource:
- `Environment` - `dev` | `test` | `prod`
- `CostCenter` - accounting code (e.g. `ENG-Platform`)
- `Owner` - email of accountable engineer
- `Project` - short slug (e.g. `acme-portal`)
- `ManagedBy` - `bicep` | `terraform` | `manual`

Enforce via Azure Policy: `templates/policies/require-tags.json` - denies resource creation without these tags. Inheritance from RG to resources via `Inherit a tag from the resource group` policy.

## Budgets

Set per RG and per subscription. Defaults:
- 50% spend → email warning to owner.
- 80% → email + Teams to action group.
- 100% → email + Teams + (if non-prod) auto-shutdown via Logic App.

Bicep: `bicep/modules/budget.bicep`.

```bash
az consumption budget create --budget-name "rg-acme-prod" \
    --amount 5000 --time-grain Monthly \
    --start-date 2026-04-01 --end-date 2027-04-01 \
    --resource-group rg-acme-prod \
    --notifications-key "80pct" --notifications threshold=80 \
    --enabled true contact-emails owner@acme.com
```

## Reservations + Savings Plans

After 30 days of stable usage, evaluate:
- **Reserved Instances (RI)**: 1y or 3y commitment for VMs, App Service plans, SQL, Cosmos, Redis. Discounts: 20–60%.
- **Compute Savings Plan**: more flexible (1y/3y) across VM families. ~20–30% off.
- **Software Plans**: Windows Server / SQL Server licenses.

Rule: only buy reservations for workloads you've run for 30+ days at >70% utilization. Don't buy on day 1 of a project.

Tools:
- **Cost Management → Recommendations** suggests RIs based on usage.
- **Azure Advisor**.

## Dev/Test pricing

Microsoft offers Dev/Test subscription pricing:
- VM Windows licensing free in dev/test.
- Up to 55% off some services.
- Requires the subscription be marked Dev/Test under the EA / MCA.

Apply for non-prod subs to capture the savings.

## Pause / scale-down patterns

- **Container Apps Consumption**: scale-to-zero - already automatic.
- **App Service**: scale to F1 outside hours via auto-scale rules.
- **AKS**: cluster autoscaler + spot node pools for non-critical workloads.
- **SQL Serverless**: auto-pause after N minutes of no activity.
- **VMs**: Azure Automation Runbooks or Logic Apps to stop nightly.
- **Fabric F-SKU**: `az fabric capacity pause` outside business hours for non-prod.

## Common money leaks (audit checklist)

| Leak | Fix |
|---|---|
| Unused public IPs | `az network public-ip list --query "[?ipConfiguration==null]"` → delete |
| Unmanaged disks attached to deleted VMs | `az disk list --query "[?managedBy==null]"` → delete |
| Old VM snapshots | Lifecycle policy or manual cleanup |
| Premium storage on dev/test | Downgrade to Standard SSD |
| Always-on App Service in dev | Auto-shutdown |
| Cosmos at high RU baseline | Switch to autoscale or serverless |
| Premium KV when Standard suffices | Downgrade |
| AI Search Standard for tiny indexes | Use Basic or share across projects |
| LA workspace daily ingest unbounded | Set daily cap |
| Defender plans enabled on resources you don't have | Disable per-plan |
| Reserved capacity without utilization | Trade in / refund unused (within 50k limit/year) |
| Multiple LA workspaces per env | Consolidate to one |

## Cost reporting

```bash
# Last 30 days by resource group
bash scripts/cost-report.sh --days 30 --group-by ResourceGroupName

# By service (where the money goes)
bash scripts/cost-report.sh --days 30 --group-by ResourceType

# Forecast for the month
az consumption usage list --start-date 2026-04-01 --end-date 2026-04-30 \
  --query "[].{cost:pretaxCost,name:instanceName}" -o table
```

## Cost workbook

Deploy `templates/workbooks/cost-overview.json` to LA workspace. Shows:
- Spend per RG / per service / per env over time.
- Top 20 resources by spend.
- Untagged spend (tagging compliance).
- Forecast vs budget.

## Reservations review cadence

Quarterly:
- Pull all reservations: `az reservations reservation-order list`.
- Calculate utilization in Cost Management → Reservations → Utilization.
- Below 70% → trade in or let expire.
- Above 90% utilization → consider 3y for deeper discount.
