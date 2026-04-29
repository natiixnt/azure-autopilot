# Subscription + Management Group setup (one-time per tenant)

The hierarchy below has no API for the EA-side billing parts. After this is done, everything else is Bicep.

## Decide the topology

### Tiny project (1–2 workloads, 1 team)
Single subscription. Skip MG hierarchy.

### Standard (3+ workloads, multiple envs, dev/test/prod separation)
- 1 top MG (`<Org>`)
- Children: `Platform`, `Landing Zones`, `Decommissioned`, `Sandbox`
- Subscriptions:
  - `<Org>-Platform-Identity` (Entra Connect, KV shared, Defender)
  - `<Org>-Platform-Connectivity` (Hub VNet, AzFW, ExpressRoute)
  - `<Org>-Platform-Mgmt` (LA, Sentinel, Automation)
  - `<Org>-LZ-Dev`
  - `<Org>-LZ-Test`
  - `<Org>-LZ-Prod`

## Step 1: Provision new subscriptions (UI - billing-bound)

Microsoft offers programmatic subscription creation only via the **Microsoft Customer Agreement (MCA)** with billing API access. Most orgs do this in the UI:

1. **https://portal.azure.com/** → search **Subscriptions**.
2. **+ Add** → fill:
   - **Billing scope**: pick MCA / EA / CSP profile.
   - **Subscription name**: e.g. `Acme-LZ-Prod`.
   - **Account admin**: a user (typically a privileged admin).
   - **Subscription directory**: your tenant.
3. **Review + Create**.

Repeat per environment. Time: ~5 min per sub.

CLI (only works if you have appropriate billing permissions):
```bash
az billing account list --query "[].{id:id,name:displayName}"  # find billing account
az account create \
    --offer-type "MS-AZR-0017P" \
    --display-name "Acme-LZ-Prod" \
    --enrollment-account-name <enrollment-account-id>
```

## Step 2: Set up Management Groups

UI:
1. Portal → search **Management groups**.
2. **+ Create** at the Tenant Root level → name: `<Org>` (e.g. `Acme`).
3. Click your `<Org>` MG → **+ Create** to add child MGs: `Platform`, `Landing Zones`, `Decommissioned`, `Sandbox`.
4. Repeat under `Platform`: `Identity`, `Connectivity`, `Management`.
5. Repeat under `Landing Zones`: `Corp`, `Online` (or per workload).

CLI:
```bash
az account management-group create --name acme
az account management-group create --name acme-platform --parent acme
az account management-group create --name acme-platform-identity --parent acme-platform
az account management-group create --name acme-platform-connectivity --parent acme-platform
az account management-group create --name acme-platform-mgmt --parent acme-platform
az account management-group create --name acme-landingzones --parent acme
az account management-group create --name acme-corp --parent acme-landingzones
az account management-group create --name acme-online --parent acme-landingzones
az account management-group create --name acme-decommissioned --parent acme
az account management-group create --name acme-sandbox --parent acme
```

## Step 3: Move subscriptions into MGs

UI: each subscription → Properties → Manage parent management group → pick.

CLI:
```bash
az account management-group subscription add \
    --name acme-platform-mgmt \
    --subscription <sub-id-of-mgmt-sub>

az account management-group subscription add \
    --name acme-online \
    --subscription <sub-id-of-prod>
```

## Step 4: RBAC at MG level

Custom role for "Workload Owner":
```bash
# Define role
cat > workload-owner.json <<EOF
{
  "Name": "Workload Owner",
  "IsCustom": true,
  "Description": "Full control of resources within a workload subscription, no RBAC management.",
  "Actions": ["*"],
  "NotActions": [
    "Microsoft.Authorization/*/Delete",
    "Microsoft.Authorization/*/Write",
    "Microsoft.Authorization/elevateAccess/Action"
  ],
  "AssignableScopes": ["/providers/Microsoft.Management/managementGroups/acme-landingzones"]
}
EOF
az role definition create --role-definition workload-owner.json
```

Assign:
```bash
az role assignment create \
    --assignee <group-or-user> \
    --role "Workload Owner" \
    --scope "/providers/Microsoft.Management/managementGroups/acme-online"
```

## Step 5: Default policies at MG level

Apply Microsoft built-in initiatives:
```bash
# CIS Benchmark (Audit-only initially)
az policy assignment create \
    --name "cis-benchmark" \
    --display-name "CIS Microsoft Azure Foundations Benchmark v2.0.0" \
    --policy-set-definition "1f3afdf9-d0c9-4c3d-847f-89da613e70a8" \
    --scope "/providers/Microsoft.Management/managementGroups/acme"

# Required tags (custom - see templates/policies/require-tags.json)
az policy definition create \
    --name "require-tags-on-rg" \
    --rules templates/policies/require-tags.json \
    --management-group acme

az policy assignment create \
    --name "require-tags-rg" \
    --policy "require-tags-on-rg" \
    --scope "/providers/Microsoft.Management/managementGroups/acme"
```

## Validation

```bash
# Show hierarchy
az account management-group list -o table

# Subs per MG
az account management-group show -n acme --expand --recurse \
    --query "children[].{name:displayName,kind:type,children:children[].displayName}" -o jsonc

# Compliance check against initiative
az policy state summarize --management-group acme -o table
```

## Common gotchas

- **Default subscription** placement: new subs land in Tenant Root MG by default; move into the proper MG immediately.
- **Tenant Root MG** RBAC: avoid assigning broad roles here - they inherit everywhere.
- **MG move requires** the user/SP to have RBAC on both old + new MG.
- **Policy scope**: changes propagate within ~30 min; expect lag.
- **Don't delete `Tenant Root Group`** - irreversible.
