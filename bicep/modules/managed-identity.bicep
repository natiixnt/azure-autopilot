@description('UMI name')
param name string
param location string = resourceGroup().location
param tags object = {}

resource umi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: name
  location: location
  tags: tags
}

output id string = umi.id
output name string = umi.name
output principalId string = umi.properties.principalId
output clientId string = umi.properties.clientId
