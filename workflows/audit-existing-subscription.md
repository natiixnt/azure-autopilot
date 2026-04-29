## Workflow: audit existing Azure subscription

You're handed an existing subscription / tenant. Goal: produce risk register + remediation plan.

Time: 0.5–2 days for inventory, 1–3 days for full audit.

## Step 1: Inventory (30 min, mostly automated)

```bash
mkdir audit-acme-2026-04 && cd audit-acme-2026-04
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh all > inventory-all.tsv
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh by-type > inventory-by-type.txt
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh untagged > inventory-untagged.txt
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh public-endpoints > inventory-public.txt
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh empty-rgs > inventory-empty-rgs.txt
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh stale-resources > inventory-stale.txt
bash ~/.claude/skills/azure-autopilot/scripts/cost-report.sh --days 30 --group-by ResourceGroup > cost-by-rg.txt
bash ~/.claude/skills/azure-autopilot/scripts/cost-report.sh --days 30 --group-by ResourceType > cost-by-type.txt
```

Subscription-level info:
```bash
az account show > account.json
az role assignment list --all > rbac.json
az policy assignment list --all > policy-assignments.json
az policy state list --all --top 1000 > policy-state.json
az consumption budget list > budgets.json
az security pricing list > defender-plans.json
az network vnet list > vnets.json
```

## Step 2: Risk register (2–4 hours)

For each finding, score H/M/L. Common categories:

### Identity (every audit finds these)
- [ ] Owner role assigned to too many principals (> 3 humans = red flag)
- [ ] Service principals with `Contributor` at subscription scope (too broad)
- [ ] PIM not enabled for privileged roles
- [ ] No Conditional Access policies (or not enforcing MFA)
- [ ] Break-glass accounts not configured / not isolated from CA
- [ ] Stale guest users with elevated permissions

### Network
- [ ] Public endpoints on prod data plane (SQL, KV, Cosmos, Storage)
- [ ] NSGs allow `0.0.0.0/0` inbound
- [ ] No NSG flow logs
- [ ] VMs with public IP on RDP/SSH (use Bastion)
- [ ] No DDoS protection on public-facing services
- [ ] Hub VNet missing for multi-workload tenant

### Data
- [ ] SQL servers without AAD-only auth
- [ ] Storage accounts allowing shared key auth
- [ ] No backup configured / not tested
- [ ] No geo-replication on prod data
- [ ] Cosmos at high RU/s baseline (cost waste)
- [ ] KV in access-policy mode (legacy) instead of RBAC
- [ ] KV without purge protection in prod
- [ ] No customer-managed keys where compliance requires

### Observability
- [ ] No diagnostic settings on > 30% of resources
- [ ] Multiple LA workspaces per env (no correlation)
- [ ] App Insights still classic (not workspace-based)
- [ ] No alert rules on critical resources
- [ ] Action groups missing or stale recipient

### Cost
- [ ] No tagging policy (untagged resources > 30%)
- [ ] No budgets / alerts
- [ ] Idle VMs (deallocated > 30 days)
- [ ] Unattached managed disks
- [ ] Unassociated public IPs
- [ ] Reserved capacity > 30% under-utilized
- [ ] Premium SKUs in non-prod

### Security baseline
- [ ] Defender for Cloud free tier only - recommend per-resource plans
- [ ] No Sentinel for tenants > 100 users
- [ ] Resource locks missing on prod
- [ ] No automated patching for VMs
- [ ] Secrets in App Settings as plaintext (search activity log)

## Step 3: Per-finding ticket

For top 10–20 findings, write a ticket:

```
## Finding: Storage account `stcontoso` allows public network access
- Severity: H
- Risk: Anyone with the access key can read/write data; key exfiltration → full data exposure
- Effort: ~2 hours
- Fix:
    1. az storage account update -n stcontoso -g rg-prod --public-network-access Disabled
    2. Add private endpoint (see bicep/modules/storage.bicep)
    3. Update apps to use AAD instead of access key
    4. Rotate access keys (set --allow-shared-key-access false)
- Owner: <name>
- Due: <date>
```

## Step 4: Deliverable

`audit-report.md`:
```
# Azure audit - <Client>
Date: 2026-04-29
Scope: subscription <id> / tenant <id>

## Executive summary
- N resource groups, M resources, $X/month spend
- Critical risks: N (immediate action required)
- High risks: N (fix within 30 days)
- Cost optimization potential: ~$X/month

## Architecture (current state)
[mermaid from `inventory-by-type.txt` aggregation]

## Top risks (ordered by severity × likelihood)
1. <risk> - Why it matters / How to fix / Effort
2. ...

## Quick wins (1 week, total saving / risk reduction)
- ...

## Strategic initiatives (1–3 months)
- ...

## Cost optimization opportunities
- Delete N unattached disks: $X/mo
- Right-size N over-provisioned VMs: $Y/mo
- Pause non-prod off-hours: $Z/mo
- ...

## Roadmap (Gantt-style table)

| Initiative                       | Q2  | Q3  | Q4  |
|----------------------------------|-----|-----|-----|
| Enable AAD-only on all SQL       | ✓   |     |     |
| Implement tagging policy         | ✓   |     |     |
| Migrate KV to RBAC mode          |     | ✓   |     |
| ...                              |     |     |     |
```

Plus appendices: full risk register, inventory CSVs, cost reports.

## Step 5: Drift monitoring (recurring)

Weekly recurring agent (use `/schedule`):
- Run inventory + cost-report.
- Diff against baseline.
- Email anomalies (new untagged resources, new public endpoints, > 20% cost spike).

## Common findings (from real audits, ranked)

1. SP with Owner at sub scope - over-privileged.
2. Storage / KV with public network on.
3. No tagging policy → untagged spend > 30%.
4. Multiple LA workspaces - no observability correlation.
5. No Defender plans on resource types that have them.
6. Idle VMs / unattached disks.
7. SQL with SQL auth still enabled.
8. Stale RBAC (old employees, removed projects).
9. No CI/CD - manual portal deploys.
10. No DR / no backup test.
