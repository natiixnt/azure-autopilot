@description('Service Bus namespace name')
param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([ 'Basic', 'Standard', 'Premium' ])
param skuName string = 'Standard'

@description('Premium messaging units (1, 2, 4, 8, 16)')
@allowed([ 1, 2, 4, 8, 16 ])
param capacity int = 1

@description('Subnet for private endpoint (Premium only)')
param privateEndpointSubnetId string = ''
@description('Private DNS zone for privatelink.servicebus.windows.net')
param privateDnsZoneId string = ''

@description('LA workspace ID')
param workspaceId string = ''

@description('Queues to create [{ name, maxSizeMB?, defaultMessageTimeToLive?, lockDuration?, requiresSession? }]')
param queues array = []

@description('Topics with subscriptions [{ name, subscriptions: [name] }]')
param topics array = []

resource sb 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
    capacity: skuName == 'Premium' ? capacity : null
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: empty(privateEndpointSubnetId) ? 'Enabled' : 'Disabled'
    disableLocalAuth: true   // AAD-only
    zoneRedundant: skuName == 'Premium'
  }
}

@batchSize(1)
resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = [for q in queues: {
  parent: sb
  name: q.name
  properties: {
    maxSizeInMegabytes: contains(q, 'maxSizeMB') ? q.maxSizeMB : 1024
    defaultMessageTimeToLive: contains(q, 'defaultMessageTimeToLive') ? q.defaultMessageTimeToLive : 'P14D'
    lockDuration: contains(q, 'lockDuration') ? q.lockDuration : 'PT5M'
    requiresSession: contains(q, 'requiresSession') ? q.requiresSession : false
    deadLetteringOnMessageExpiration: true
  }
}]

@batchSize(1)
resource topic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = [for t in topics: {
  parent: sb
  name: t.name
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P14D'
    enablePartitioning: false
  }
}]

@batchSize(1)
resource sub 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = [for (t, ti) in topics: if (length(t.subscriptions) > 0) {
  parent: topic[ti]
  name: t.subscriptions[0]
  properties: {
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT5M'
    maxDeliveryCount: 10
  }
}]

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId) && skuName == 'Premium') {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'sb-link'
      properties: {
        privateLinkServiceId: sb.id
        groupIds: [ 'namespace' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(privateDnsZoneId) && skuName == 'Premium') {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'sb'
      properties: { privateDnsZoneId: privateDnsZoneId }
    }]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: sb
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = sb.id
output name string = sb.name
output namespace string = sb.properties.serviceBusEndpoint
