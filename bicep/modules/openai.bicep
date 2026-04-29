@description('Azure OpenAI account name')
param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([ 'S0' ])
param sku string = 'S0'

@description('Custom subdomain (required for AAD auth)')
param customSubDomainName string = name

@description('Disable public network')
param publicNetworkAccess bool = false

@description('Subnet for private endpoint')
param privateEndpointSubnetId string = ''
@description('Private DNS zone for privatelink.openai.azure.com')
param privateDnsZoneId string = ''

@description('LA workspace ID')
param workspaceId string = ''

@description('Model deployments. [{ name, model: { name, version }, sku: { name, capacity } }]')
param deployments array = []

resource oai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  identity: { type: 'SystemAssigned' }
  sku: { name: sku }
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    networkAcls: { defaultAction: publicNetworkAccess ? 'Allow' : 'Deny' }
    disableLocalAuth: true   // AAD-only
  }
}

@batchSize(1)
resource deploy 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for d in deployments: {
  parent: oai
  name: d.name
  sku: d.sku
  properties: {
    model: {
      format: 'OpenAI'
      name: d.model.name
      version: d.model.version
    }
    raiPolicyName: contains(d, 'raiPolicyName') ? d.raiPolicyName : 'Microsoft.DefaultV2'
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
}]

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId)) {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'oai-link'
      properties: {
        privateLinkServiceId: oai.id
        groupIds: [ 'account' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(privateDnsZoneId)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'oai'
      properties: { privateDnsZoneId: privateDnsZoneId }
    }]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: oai
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [
      { category: 'Audit', enabled: true }
      { category: 'RequestResponse', enabled: true }
      { category: 'Trace', enabled: true }
    ]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = oai.id
output name string = oai.name
output endpoint string = oai.properties.endpoint
