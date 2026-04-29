# Bicep - quick reference

Bicep is the Azure-native DSL that compiles to ARM JSON. Use Bicep over raw ARM. Use Bicep over Terraform unless the user already has a Terraform estate (then `terraform-azure.md`).

## File anatomy

```bicep
targetScope = 'resourceGroup'   // or 'subscription' | 'managementGroup' | 'tenant'

@description('Resource name prefix')
param namePrefix string

@allowed(['dev','test','prod'])
param environment string

@secure()
param sqlAdminPassword string  // never logged or shown in outputs

var location = resourceGroup().location
var tags = {
  Environment: environment
  Project: namePrefix
  ManagedBy: 'bicep'
}

// resource declarations
resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${namePrefix}${environment}'
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// module composition
module la 'modules/log-analytics.bicep' = {
  name: 'la-deploy'
  params: {
    name: 'la-${namePrefix}-${environment}'
    location: location
    tags: tags
  }
}

// loop over array
param subnets array
resource snets 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = [for s in subnets: {
  parent: vnet
  name: s.name
  properties: { addressPrefix: s.cidr }
}]

// conditional resource
param deployRedis bool = false
resource redis 'Microsoft.Cache/Redis@2023-08-01' = if (deployRedis) {
  name: 'redis-${namePrefix}-${environment}'
  location: location
  properties: { sku: { name: 'Standard', family: 'C', capacity: 1 } }
}

// outputs
output workspaceId string = la.outputs.workspaceId
output storageAccountName string = sa.name

// secure output (never in plaintext logs)
@secure()
output connectionString string = sa.listKeys().keys[0].value
```

## Common patterns

### Reference an existing resource
```bicep
resource existingKv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: 'kv-shared'
  scope: resourceGroup('rg-shared')
}
```

### Cross-resource group / subscription deployment
```bicep
module remoteRg './modules/storage.bicep' = {
  name: 'remote-storage'
  scope: resourceGroup(remoteSubId, 'rg-other')
  params: { ... }
}
```

### User-assigned managed identity assignment
```bicep
resource ca 'Microsoft.App/containerApps@2024-03-01' = {
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${umi.id}': {} }
  }
  properties: { ... }
}
```

### Role assignment (correct way)
```bicep
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv  // narrowest scope possible
  name: guid(kv.id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
  }
}
```

`name` MUST be a deterministic GUID derived from scope+principal+role - otherwise duplicate creates fail.

### Diagnostic settings
```bicep
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: kv
  name: 'to-la'
  properties: {
    workspaceId: laWorkspaceId
    logs: [
      { categoryGroup: 'audit', enabled: true }
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}
```

### Private endpoint
```bicep
resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${kv.name}'
  location: location
  properties: {
    subnet: { id: dataSubnetId }
    privateLinkServiceConnections: [{
      name: 'kv-link'
      properties: {
        privateLinkServiceId: kv.id
        groupIds: ['vault']
      }
    }]
  }
}

resource pdz 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.vaultcore.azure.net'
  scope: resourceGroup(dnsRgName)
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'vault'
      properties: { privateDnsZoneId: pdz.id }
    }]
  }
}
```

### Key Vault references (App Service / Functions / Container Apps)
```bicep
properties: {
  siteConfig: {
    appSettings: [
      { name: 'DB_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=${kv.properties.vaultUri}secrets/db-password)' }
    ]
  }
}
```

App must have `Key Vault Secrets User` role on the vault, and KV must be in RBAC mode.

## Built-in functions you'll use a lot

- `resourceGroup()` / `subscription()` / `tenant()` - context.
- `uniqueString(seed, ...)` - deterministic random for global names.
- `guid(seed, ...)` - deterministic GUID for role assignment names.
- `concat(a, b)` - string join. Prefer string interpolation `${a}${b}`.
- `take(s, n)` - substring.
- `toLower(s)` - for storage account names that demand lowercase.
- `loadTextContent('config.json')` - embed config files.
- `loadJsonContent('config.json')` - embed parsed JSON.

## Module reuse pattern

```
modules/
  log-analytics.bicep
  app-insights.bicep
  key-vault.bicep
  managed-identity.bicep
  ...

main.bicep
```

`main.bicep` orchestrates; modules are reusable. Each module has clear `params` and `outputs`.

For shared modules across projects: publish to **Bicep registry (ACR)**:
```bicep
module kv 'br:acmebicep.azurecr.io/bicep/modules/key-vault:v1.2.0' = { ... }
```

## .bicepparam (parameter files)

```bicepparam
using './main.bicep'

param namePrefix = 'acme'
param environment = 'prod'
param location = 'westeurope'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')   // pulled from env
```

`readEnvironmentVariable` and `getSecret` (from KV) keep secrets out of the file.

## Bicep what-if

```bash
az deployment group what-if -g $RG -f main.bicep -p prod.bicepparam
```

Output:
- `+` resources to create
- `~` resources to modify (and exact property diff)
- `-` resources to delete
- `=` no change

Read every `~` and `-` carefully. NEVER deploy if you can't explain what will change.

## Linter

Bicep has a built-in linter. Add `bicepconfig.json` at repo root:
```json
{
  "analyzers": {
    "core": {
      "rules": {
        "no-hardcoded-location": { "level": "error" },
        "secure-parameter-default": { "level": "error" },
        "no-unused-params": { "level": "warning" },
        "outputs-should-not-contain-secrets": { "level": "error" }
      }
    }
  }
}
```

`bicep build main.bicep` validates + emits ARM JSON.

## Common gotchas

- **Storage account names** must be 3–24 chars, lowercase, globally unique. Use `toLower('st${prefix}${uniqueString(rg.id)}')`.
- **Role assignment name conflicts**: always use `guid()` derived from scope+principal+role.
- **Resource locks** are NOT in Bicep idiomatic flow - apply via separate deployment or `Microsoft.Authorization/locks` resource.
- **Implicit dependencies**: Bicep figures out dependsOn from references; explicit `dependsOn:` rarely needed (and discouraged).
- **API versions** matter - pin to specific stable versions; bump deliberately.
