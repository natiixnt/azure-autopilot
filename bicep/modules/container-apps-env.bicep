@description('Container Apps environment name')
param name string
param location string = resourceGroup().location
param tags object = {}

@description('LA workspace customer ID (workspace ID, not resource ID)')
param logAnalyticsCustomerId string

@description('LA workspace shared key - use listKeys() in main.bicep')
@secure()
param logAnalyticsSharedKey string

@description('App Insights connection string')
param appInsightsConnectionString string = ''

@description('Subnet ID for VNet integration. /27 minimum for Consumption-only, /23 for workload profiles.')
param infrastructureSubnetId string = ''

@description('Workload profiles. Default: Consumption only.')
param workloadProfiles array = [
  { name: 'Consumption', workloadProfileType: 'Consumption' }
]

@description('Internal-only ingress (no public)?')
param internalLoadBalancer bool = false

@description('Zone redundancy (requires VNet + zonal region)')
param zoneRedundant bool = false

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    daprAIConnectionString: appInsightsConnectionString
    vnetConfiguration: !empty(infrastructureSubnetId) ? {
      infrastructureSubnetId: infrastructureSubnetId
      internal: internalLoadBalancer
    } : null
    workloadProfiles: workloadProfiles
    zoneRedundant: zoneRedundant
  }
}

output id string = cae.id
output name string = cae.name
output defaultDomain string = cae.properties.defaultDomain
output staticIp string = cae.properties.staticIp
