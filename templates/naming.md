# Naming convention (CAF-aligned)

Pattern: `<resource-type-abbr>-<workload>-<env>-<region-abbr>[-<instance>]`

For globally unique names (storage, KV, ACR, Cosmos, Front Door): append `<uniqueString>` suffix.

## Resource type abbreviations

| Resource | Abbr |
|---|---|
| Resource group | `rg` |
| Virtual network | `vnet` |
| Subnet | `snet` |
| Network security group | `nsg` |
| Public IP | `pip` |
| Bastion | `bas` |
| VPN gateway | `vpngw` |
| ExpressRoute | `er` |
| Front Door | `fd` |
| App Gateway | `agw` |
| Azure Firewall | `afw` |
| Load Balancer | `lb` |
| Storage account | `st` (no dash; lowercase only) |
| Key Vault | `kv` |
| App Service plan | `asp` |
| App Service / Web App | `app` |
| Function App | `func` |
| Container App | `ca` |
| Container Apps env | `cae` |
| Container Registry | `acr` (lowercase only) |
| AKS cluster | `aks` |
| SQL Server | `sql` |
| SQL Database | `sqldb` |
| Postgres Flexible | `pg` |
| Cosmos DB | `cosmos` |
| Redis | `redis` |
| Service Bus | `sb` |
| Event Hub namespace | `evhns` |
| Event Hub | `evh` |
| Event Grid topic | `evgt` |
| API Management | `apim` |
| Log Analytics | `la` |
| App Insights | `ai` |
| Action Group | `ag` |
| Azure OpenAI | `oai` |
| AI Search | `srch` |
| Managed Identity (UMI) | `umi` |
| Private endpoint | `pe` |
| Private DNS zone | `pdz` (or use FQDN) |
| Recovery Services Vault | `rsv` |
| Automation Account | `aut` |

## Region abbreviations

| Region | Abbr |
|---|---|
| westeurope | `we` |
| northeurope | `ne` |
| polandcentral | `plc` |
| eastus | `eus` |
| eastus2 | `eus2` |
| westus | `wus` |
| westus2 | `wus2` |
| westus3 | `wus3` |
| centralus | `cus` |
| southcentralus | `scus` |
| uksouth | `uks` |
| ukwest | `ukw` |
| swedencentral | `swc` |
| francecentral | `frc` |
| germanywestcentral | `gwc` |
| switzerlandnorth | `chn` |
| japaneast | `jpe` |
| australiaeast | `aue` |
| southeastasia | `sea` |
| eastasia | `ea` |

## Examples

```
rg-acme-prod              (resource group)
vnet-acme-prod-we
snet-compute              (subnet, scoped to vnet)
kv-acme-prod-we-a3b9c     (KV with uniqueness suffix)
stacmeprodwea3b9c         (storage; no dashes; lowercase)
acracmeprodwe a3b9c       (ACR; lowercase + alphanumeric only)
ca-acme-app-prod          (container app)
cae-acme-prod             (container apps env)
pg-acme-prod-we           (postgres)
oai-acme-prod-swc         (Azure OpenAI in Sweden Central - model availability)
fd-acme-prod              (Front Door is global, no region suffix)
la-acme-prod-we           (Log Analytics)
ai-acme-prod-we           (App Insights)
umi-acme-prod-we          (User Assigned Identity)
pe-kv-acme-prod-we        (Private endpoint targeting KV)
```

## Special cases

- **Storage account**: 3–24 lowercase alphanumeric, globally unique. Use `take(toLower('st${prefix}${env}${uniqueString(rg.id)}'), 24)`.
- **ACR**: 5–50 lowercase alphanumeric, globally unique.
- **KV**: 3–24 chars, globally unique (DNS label).
- **Front Door endpoint**: subdomain of `*.azurefd.net`; pattern `${name}-${suffix}.z01.azurefd.net`.
- **Azure DNS zone for private link**: fixed names per service (e.g. `privatelink.vaultcore.azure.net`); store in shared "DNS" RG if hub-spoke.

## Tags (separate from name; both required)

```yaml
Environment: dev | test | prod | shared
Project: <slug>
ManagedBy: bicep | terraform | manual
CostCenter: <accounting code>
Owner: <email>
DataClassification: public | internal | confidential | restricted   # optional
```

Inherit from RG to children via Azure Policy `Inherit a tag from the resource group`.

## Lengths to remember (for `uniqueString` budgeting)

| Resource | Max name length |
|---|---|
| Storage account | 24 |
| KV | 24 |
| ACR | 50 |
| App Service | 60 |
| Container App | 32 |
| Cosmos | 44 |
| Postgres Flex | 63 |
| SQL Server | 63 |

When close to limit: use `take(...)` to clip safely.
