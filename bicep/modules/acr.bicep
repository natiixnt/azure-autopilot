@description('ACR name (5-50 alphanumeric, globally unique)')
@minLength(5)
@maxLength(50)
param name string

param location string = resourceGroup().location
param tags object = {}

@allowed([ 'Basic', 'Standard', 'Premium' ])
param sku string = 'Standard'

@description('Disable public network access (Premium only)')
param publicNetworkAccess bool = true

@description('Subnet for private endpoint (Premium only)')
param privateEndpointSubnetId string = ''

@description('Private DNS zone ID for privatelink.azurecr.io')
param privateDnsZoneId string = ''

@description('LA workspace ID')
param workspaceId string = ''

@description('Geo-replication regions (Premium only)')
param geoReplicationLocations array = []

@description('Retention days for untagged manifests (Premium only)')
param retentionDays int = 7

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: { name: sku }
  identity: { type: 'SystemAssigned' }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    policies: sku == 'Premium' ? {
      retentionPolicy: { status: 'enabled', days: retentionDays }
      quarantinePolicy: { status: 'enabled' }
      trustPolicy: { type: 'Notary', status: 'enabled' }
    } : {}
    zoneRedundancy: sku == 'Premium' ? 'Enabled' : 'Disabled'
  }
}

resource replication 'Microsoft.ContainerRegistry/registries/replications@2023-11-01-preview' = [for region in geoReplicationLocations: if (sku == 'Premium') {
  parent: acr
  name: region
  location: region
}]

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId) && sku == 'Premium') {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'acr-link'
      properties: {
        privateLinkServiceId: acr.id
        groupIds: [ 'registry' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(privateDnsZoneId) && sku == 'Premium') {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'acr'
      properties: { privateDnsZoneId: privateDnsZoneId }
    }]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: acr
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = acr.id
output name string = acr.name
output loginServer string = acr.properties.loginServer
