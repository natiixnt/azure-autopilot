@description('Postgres Flexible Server name')
param name string
param location string = resourceGroup().location
param tags object = {}

@description('SKU name e.g. Standard_B1ms (burstable), Standard_D2ds_v5 (general purpose)')
param skuName string = 'Standard_B1ms'

@description('Tier inferred from SKU prefix')
@allowed([ 'Burstable', 'GeneralPurpose', 'MemoryOptimized' ])
param tier string = 'Burstable'

@description('Postgres version')
@allowed([ '13', '14', '15', '16', '17' ])
param version string = '16'

@description('Storage in GB')
@minValue(32)
@maxValue(32768)
param storageSizeGB int = 32

@description('VNet-injected subnet (delegated to Microsoft.DBforPostgreSQL/flexibleServers)')
param delegatedSubnetId string = ''

@description('Private DNS zone for postgres.database.azure.com (auto-created if not provided)')
param privateDnsZoneId string = ''

@description('AAD admin object ID (group recommended)')
param aadAdminGroupObjectId string

@description('AAD admin display name')
param aadAdminName string = 'pg-admins'

@description('LA workspace ID')
param workspaceId string = ''

@description('HA mode')
@allowed([ 'Disabled', 'ZoneRedundant', 'SameZone' ])
param highAvailability string = 'Disabled'

@description('Backup retention days')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@description('Geo-redundant backup')
param geoRedundantBackup bool = false

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: skuName, tier: tier }
  properties: {
    version: version
    storage: { storageSizeGB: storageSizeGB, autoGrow: 'Enabled' }
    network: !empty(delegatedSubnetId) ? {
      delegatedSubnetResourceId: delegatedSubnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    } : { publicNetworkAccess: 'Enabled' }
    highAvailability: { mode: highAvailability }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup ? 'Enabled' : 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'   // AAD-only
      tenantId: subscription().tenantId
    }
  }
}

resource aadAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: pg
  name: aadAdminGroupObjectId
  properties: {
    principalType: 'Group'
    principalName: aadAdminName
    tenantId: subscription().tenantId
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: pg
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = pg.id
output name string = pg.name
output fqdn string = pg.properties.fullyQualifiedDomainName
