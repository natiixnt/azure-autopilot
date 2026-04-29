@description('SQL server name')
param name string
param location string = resourceGroup().location
param tags object = {}

@description('AAD admin group object ID')
param aadAdminObjectId string
param aadAdminName string = 'sql-admins'

@description('Disable public network')
param publicNetworkAccess bool = false

@description('Subnet for private endpoint')
param privateEndpointSubnetId string = ''
@description('Private DNS zone for privatelink.database.windows.net')
param privateDnsZoneId string = ''

@description('LA workspace ID')
param workspaceId string = ''

@description('Databases to create')
param databases array = [
  { name: 'app', skuName: 'GP_S_Gen5_2', tier: 'GeneralPurpose', minCapacity: '0.5', autoPauseDelay: 60, maxSizeBytes: 34359738368 }
]

resource sql 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Group'
      login: aadAdminName
      sid: aadAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true   // disable SQL auth
    }
    version: '12.0'
  }
}

resource db 'Microsoft.Sql/servers/databases@2023-08-01-preview' = [for d in databases: {
  parent: sql
  name: d.name
  location: location
  tags: tags
  sku: { name: d.skuName, tier: d.tier }
  properties: {
    minCapacity: contains(d, 'minCapacity') ? json(d.minCapacity) : null
    autoPauseDelay: contains(d, 'autoPauseDelay') ? d.autoPauseDelay : null
    maxSizeBytes: contains(d, 'maxSizeBytes') ? d.maxSizeBytes : null
    zoneRedundant: false
    readScale: 'Disabled'
  }
}]

resource auditing 'Microsoft.Sql/servers/auditingSettings@2023-08-01-preview' = if (!empty(workspaceId)) {
  parent: sql
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    auditActionsAndGroups: [
      'BATCH_COMPLETED_GROUP'
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
    ]
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (!empty(privateEndpointSubnetId)) {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [{
      name: 'sql-link'
      properties: {
        privateLinkServiceId: sql.id
        groupIds: [ 'sqlServer' ]
      }
    }]
  }
}

resource pdzGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (!empty(privateEndpointSubnetId) && !empty(privateDnsZoneId)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'sql'
      properties: { privateDnsZoneId: privateDnsZoneId }
    }]
  }
}

output id string = sql.id
output name string = sql.name
output fqdn string = sql.properties.fullyQualifiedDomainName
output databaseIds array = [for (d, i) in databases: db[i].id]
