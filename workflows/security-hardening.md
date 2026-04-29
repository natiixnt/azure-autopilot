## Workflow: security hardening sweep

For: bringing existing subscription up to a secure-by-default baseline.

## Day 0 - Baseline (1 hour)

```bash
# Defender for Cloud secure score
az security secure-scores list -o table

# What's enabled
az security pricing list --query "[].{name:name,tier:pricingTier}" -o table

# Conditional Access state (UI: Entra → Security → Conditional Access)
# (no CLI for full export; use ConditionalAccessPolicies graph endpoint)
```

## Day 1 - Identity hardening (mostly UI)

Walk-through: `ui-walkthroughs/conditional-access.md`. Critical policies:

1. **Block legacy auth** tenant-wide.
2. **MFA required for admins** - apply to all directory roles + privileged Azure roles.
3. **MFA required for all users** (or risk-based via Identity Protection).
4. **Block sign-in from unsupported countries** (allowlist your operation regions).
5. **Compliant device required** for accessing Azure portal, M365 admin.
6. **Break-glass exception**: 2 cloud-only accounts excluded from CA, hardware token only.

PIM:
```
Entra → Privileged Identity Management → Azure resources → enable for sub
→ Roles → make Owner, Contributor, User Access Administrator eligible (not active)
→ Settings: max activation 4h, MFA required, ticket reason required
→ For Global Admin: same with approval required from another admin
```

## Day 1 - Network hardening

```bash
# Find public-facing data plane
bash ~/.claude/skills/azure-autopilot/scripts/inventory.sh public-endpoints
```

Per finding, add private endpoint + disable public access. See `bicep/modules/{kv,storage,sql-server,cosmos}.bicep` patterns.

```bash
# NSG audit: any 0.0.0.0/0 inbound except Front Door / App Gateway?
az network nsg list --query "[].{name:name, rules:securityRules[?(direction=='Inbound' && access=='Allow' && sourceAddressPrefix=='*')].name}" -o table
```

Add Bastion if there's any public SSH/RDP:
```bash
az network bastion create -g rg-platform-mgmt -n bastion-prod \
    --vnet-name vnet-hub-prod --public-ip-address pip-bastion
```

## Day 2 - Defender plans

Enable per resource type matching your deployment:
```bash
for plan in AppServices KeyVaults StorageAccounts SqlServers KubernetesService Containers Servers Databases Api OpenSourceRelationalDatabases; do
  az security pricing create -n "$plan" --tier Standard
done
```

For Servers: pick P1 ($5/server/mo) or P2 ($15/server/mo with file integrity, JIT, vuln scan).
For SQL: $X/server/mo with anomalous query detection.
For OpenAI / AI Services: enable for jailbreak / prompt injection detection.

Run a probe of recommendations:
```bash
az security assessment list --query "[?status.code=='Unhealthy'].{name:displayName,sev:metadata.severity}" -o table
```

## Day 2 - Key Vault hardening

For every KV in scope:
```bash
for kv in $(az keyvault list --query "[].name" -o tsv); do
  echo "── $kv ──"
  rbac=$(az keyvault show -n "$kv" --query properties.enableRbacAuthorization -o tsv)
  pp=$(az keyvault show -n "$kv" --query properties.enablePurgeProtection -o tsv)
  pna=$(az keyvault show -n "$kv" --query properties.publicNetworkAccess -o tsv)
  echo "RBAC: $rbac, PurgeProt: $pp, PublicAccess: $pna"
  
  # If not RBAC mode, migrate (one-way)
  [[ "$rbac" != "true" ]] && az keyvault update -n "$kv" --enable-rbac-authorization true
  
  # Enable purge protection for prod KVs
  # (irreversible - get explicit consent first)
done
```

## Day 3 - Storage + SQL + Cosmos hardening

Storage:
```bash
for sa in $(az storage account list --query "[].name" -o tsv); do
  az storage account update -n "$sa" --min-tls-version TLS1_2 --https-only true
  az storage account update -n "$sa" --allow-shared-key-access false   # forces AAD
  # Public network: case-by-case (some need public)
done
```

SQL:
```bash
for srv in $(az sql server list --query "[].name" -o tsv); do
  rg=$(az sql server list --query "[?name=='$srv'].resourceGroup | [0]" -o tsv)
  az sql server ad-only-auth enable --name "$srv" --resource-group "$rg"
  az sql server update -n "$srv" -g "$rg" --enable-public-network false
done
```

Cosmos:
```bash
for c in $(az cosmosdb list --query "[].name" -o tsv); do
  rg=$(az cosmosdb list --query "[?name=='$c'].resourceGroup | [0]" -o tsv)
  az cosmosdb update -n "$c" -g "$rg" --disable-key-based-metadata-write-access true
  # Disable local auth (data plane RBAC only) - irreversible-ish
  az cosmosdb update -n "$c" -g "$rg" --disable-local-auth true
done
```

## Day 3 - Resource locks on prod

```bash
# Lock prod RGs to prevent accidental delete
for rg in $(az group list --query "[?tags.Environment=='prod'].name" -o tsv); do
  az lock create --name "no-delete" --lock-type CanNotDelete --resource-group "$rg"
done
```

## Day 4 - Sentinel (if SIEM in scope)

- Onboard Sentinel to existing LA workspace (if not yet).
- Connect Microsoft 365 Defender, Entra ID Sign-ins, Activity log connectors.
- Enable analytics rules (built-in Microsoft templates first).
- Configure incident → ITSM (ServiceNow / Jira) integration.

## Day 4 - Apply Azure Policy baseline

```bash
# Apply at MG level (or sub if no MG)
az policy assignment create \
    --name "require-tags" \
    --display-name "Require tags on resource groups" \
    --policy-set-definition "/providers/Microsoft.Authorization/policySetDefinitions/CIS_Azure_2.0.0" \
    --scope "/providers/Microsoft.Management/managementGroups/<mg>"
```

Custom policies in `templates/policies/`:
- `require-tags.json` - deny RG without required tags.
- `allowed-locations.json` - deny resources outside region whitelist.
- `https-only-storage.json` - deny non-HTTPS storage.
- `diag-settings-required.json` - DeployIfNotExists for diagnostic settings.

## Day 5 - Validate + report

```bash
az security secure-scores list -o table
# Should show improvement in subscription score
```

Output:
```
# Security hardening report - <Client>
Date: 2026-04-29
Baseline secure score: X%
Current secure score: Y%

## Implemented
- Conditional Access: <list of policies>
- PIM enabled for: <roles>
- Defender plans: <enabled list>
- Private endpoints added: <count>
- Public endpoints disabled: <count>
- KVs in RBAC mode: <count> (was <before>)
- SQL with AAD-only: <count>
- Resource locks on prod: <count>
- Azure Policy initiative applied: <name>

## Remaining (next sprint)
- ...

## Recurring controls
- Quarterly secure score review scheduled
- Monthly Defender recommendation triage
- Sentinel monitoring active
```

## Common gotchas

- **Disable public access on KV** breaks app that uses public DNS - verify private endpoint resolves first.
- **AAD-only on SQL** breaks any app using SQL auth - coordinate with app teams.
- **Purge protection on KV** is irreversible - explicit consent required.
- **CA blocking legacy auth** breaks old SMTP/IMAP clients - communicate ahead.
- **Resource locks** on RG cascade to children - block legitimate deletes; document the unlock process.
