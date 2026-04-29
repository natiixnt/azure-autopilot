@description('AI Search service name')
param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([ 'free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2' ])
param sku string = 'basic'

@description('Number of replicas (queries) - 1 for dev, 2+ for prod')
@minValue(1)
@maxValue(12)
param replicaCount int = 1

@description('Number of partitions (storage) - 1 for small, scale up for big indexes')
@minValue(1)
@maxValue(12)
param partitionCount int = 1

@allowed([ 'disabled', 'free', 'standard' ])
param semanticSearch string = 'free'

@description('Disable public network')
param publicNetworkAccess bool = false

@description('Subnet for private endpoint')
param privateEndpointSubnetId string = ''
@description('Private DNS zone for privatelink.search.windows.net')
param privateDnsZoneId string = ''

@description('LA workspace ID')
param workspaceId string = ''

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: { name: sku }
  identity: { type: 'SystemAssigned' }
  properties: {
    replicaCount: replicaCount
    partitionCount: partitionCount
    semanticSearch: semanticSearch
    publicNetworkAccess: publicNetworkAccess ? 'enabled' : 'disabled'
    authOptions: { aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge' } }
    disableLocalAuth: true   // AAD-only
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId)) {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'search-link'
      properties: {
        privateLinkServiceId: search.id
        groupIds: [ 'searchService' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(privateDnsZoneId)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'search'
      properties: { privateDnsZoneId: privateDnsZoneId }
    }]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: search
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = search.id
output name string = search.name
output endpoint string = 'https://${search.name}.search.windows.net'
