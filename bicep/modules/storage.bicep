@description('Storage account name (3-24 lowercase, globally unique)')
@minLength(3)
@maxLength(24)
param name string

param location string = resourceGroup().location
param tags object = {}

@allowed([ 'Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_GZRS', 'Standard_RAGRS', 'Premium_LRS', 'Premium_ZRS' ])
param skuName string = 'Standard_LRS'

@allowed([ 'StorageV2', 'BlobStorage', 'BlockBlobStorage' ])
param kind string = 'StorageV2'

@description('Hierarchical namespace = ADLS Gen2')
param isHnsEnabled bool = false

@description('Disable public network access for prod')
param publicNetworkAccess bool = false

@description('Subnet ID for blob private endpoint')
param privateEndpointSubnetId string = ''
@description('Private DNS zone ID for privatelink.blob.core.windows.net')
param blobPrivateDnsZoneId string = ''

@description('LA workspace ID for diagnostic settings')
param workspaceId string = ''

@description('Containers to create')
param containers array = []

@description('Soft delete retention days for blobs')
@minValue(1)
@maxValue(365)
param softDeleteRetentionDays int = 30

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: skuName }
  kind: kind
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false   // force AAD auth
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    isHnsEnabled: isHnsEnabled
    networkAcls: {
      defaultAction: publicNetworkAccess ? 'Allow' : 'Deny'
      bypass: 'AzureServices, Logging, Metrics'
    }
    encryption: {
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: sa
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: { enabled: true, days: softDeleteRetentionDays }
    containerDeleteRetentionPolicy: { enabled: true, days: softDeleteRetentionDays }
    changeFeed: { enabled: true }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for c in containers: {
  parent: blobs
  name: c
  properties: { publicAccess: 'None' }
}]

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId)) {
  name: 'pe-${name}-blob'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'blob-link'
      properties: {
        privateLinkServiceId: sa.id
        groupIds: [ 'blob' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(blobPrivateDnsZoneId)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'blob'
      properties: { privateDnsZoneId: blobPrivateDnsZoneId }
    }]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: blobs
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = sa.id
output name string = sa.name
output blobEndpoint string = sa.properties.primaryEndpoints.blob
output dfsEndpoint string = sa.properties.primaryEndpoints.dfs
