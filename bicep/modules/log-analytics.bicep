@description('Log Analytics workspace name')
param name string

@description('Location')
param location string = resourceGroup().location

@description('Tags')
param tags object = {}

@description('Retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Daily ingestion cap (GB). 0 = no cap.')
param dailyQuotaGb int = 0

@description('Pricing tier')
@allowed([ 'PerGB2018', 'CapacityReservation' ])
param sku string = 'PerGB2018'

@description('Capacity reservation level (only used if sku=CapacityReservation)')
@allowed([ 100, 200, 300, 400, 500, 1000, 2000, 5000 ])
param capacityReservationLevel int = 100

resource la 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: sku == 'CapacityReservation' ? {
      name: sku
      capacityReservationLevel: capacityReservationLevel
    } : { name: sku }
    retentionInDays: retentionInDays
    workspaceCapping: dailyQuotaGb > 0 ? {
      dailyQuotaGb: dailyQuotaGb
    } : null
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output id string = la.id
output workspaceId string = la.id
output customerId string = la.properties.customerId
output name string = la.name
