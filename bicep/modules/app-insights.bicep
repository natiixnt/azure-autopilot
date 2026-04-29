@description('App Insights name')
param name string
param location string = resourceGroup().location
param tags object = {}

@description('Workspace-based AI requires the LA workspace ID')
param workspaceId string

@description('Sampling percent (0-100). 100 = capture all.')
@minValue(0)
@maxValue(100)
param samplingPercent int = 100

resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceId
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    SamplingPercentage: samplingPercent
  }
}

output id string = ai.id
output name string = ai.name
output instrumentationKey string = ai.properties.InstrumentationKey
output connectionString string = ai.properties.ConnectionString
