@description('Cosmos account name (3-44 lowercase, globally unique)')
@minLength(3)
@maxLength(44)
param name string

param location string = resourceGroup().location
param tags object = {}

@allowed([ 'Eventual', 'Session', 'BoundedStaleness', 'Strong', 'ConsistentPrefix' ])
param defaultConsistencyLevel string = 'Session'

@description('Additional regions for replication / multi-write')
param additionalRegions array = []

@description('Enable multi-region writes')
param multipleWriteLocations bool = false

@description('Enable serverless (mutually exclusive with provisioned/autoscale)')
param serverless bool = false

@description('Disable public network access')
param publicNetworkAccess bool = false

@description('Subnet for private endpoint')
param privateEndpointSubnetId string = ''
@description('Private DNS zone for privatelink.documents.azure.com')
param privateDnsZoneId string = ''

@description('LA workspace ID')
param workspaceId string = ''

@description('Databases to create. {name, containers: [{name, partitionKey, autoscaleMaxRU?, throughput?}]}')
param databases array = []

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: { defaultConsistencyLevel: defaultConsistencyLevel }
    enableMultipleWriteLocations: multipleWriteLocations
    capabilities: serverless ? [{ name: 'EnableServerless' }] : []
    locations: concat([
      { locationName: location, failoverPriority: 0, isZoneRedundant: false }
    ], [for (r, i) in additionalRegions: {
      locationName: r
      failoverPriority: i + 1
      isZoneRedundant: false
    }])
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    isVirtualNetworkFilterEnabled: !publicNetworkAccess
    backupPolicy: { type: 'Continuous', continuousModeProperties: { tier: 'Continuous7Days' } }
    disableLocalAuth: true   // AAD-only data plane
  }
}

@batchSize(1)
resource db 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = [for d in databases: {
  parent: cosmos
  name: d.name
  properties: {
    resource: { id: d.name }
  }
}]

@batchSize(1)
resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = [for (d, di) in databases: if (length(d.containers) > 0) {
  parent: db[di]
  name: d.containers[0].name   // simplified - single container per db; for multiple, refactor to flat array
  properties: {
    resource: {
      id: d.containers[0].name
      partitionKey: { paths: [ d.containers[0].partitionKey ], kind: 'Hash' }
    }
    options: serverless ? {} : (contains(d.containers[0], 'autoscaleMaxRU') ? {
      autoscaleSettings: { maxThroughput: d.containers[0].autoscaleMaxRU }
    } : {
      throughput: contains(d.containers[0], 'throughput') ? d.containers[0].throughput : 400
    })
  }
}]

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId)) {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'cosmos-link'
      properties: {
        privateLinkServiceId: cosmos.id
        groupIds: [ 'Sql' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(privateDnsZoneId)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'cosmos'
      properties: { privateDnsZoneId: privateDnsZoneId }
    }]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: cosmos
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = cosmos.id
output name string = cosmos.name
output endpoint string = cosmos.properties.documentEndpoint
