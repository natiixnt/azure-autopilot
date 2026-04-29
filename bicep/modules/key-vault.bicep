@description('KV name (3-24 chars, must be globally unique)')
@minLength(3)
@maxLength(24)
param name string

param location string = resourceGroup().location
param tags object = {}

@allowed([ 'standard', 'premium' ])
param sku string = 'standard'

@description('Disable public network access (recommended for prod)')
param publicNetworkAccess bool = false

@description('Subnet ID for private endpoint (optional)')
param privateEndpointSubnetId string = ''

@description('Private DNS zone ID for privatelink.vaultcore.azure.net (optional)')
param privateDnsZoneId string = ''

@description('LA workspace ID for diagnostic settings (optional)')
param workspaceId string = ''

@description('Soft delete retention days')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Enable purge protection (irreversible). Required for prod.')
param enablePurgeProtection bool = true

@description('AAD tenant ID')
param tenantId string = subscription().tenantId

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: { family: 'A', name: sku }
    enableRbacAuthorization: true   // RBAC mode, not access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: publicNetworkAccess ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId)) {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'kv-link'
      properties: {
        privateLinkServiceId: kv.id
        groupIds: [ 'vault' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(privateDnsZoneId)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'vault'
      properties: { privateDnsZoneId: privateDnsZoneId }
    }]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: kv
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [
      { categoryGroup: 'audit', enabled: true }
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = kv.id
output name string = kv.name
output uri string = kv.properties.vaultUri
