@description('VNet name')
param name string
param location string = resourceGroup().location
param tags object = {}

@description('VNet address space (CIDR)')
param addressPrefix string = '10.10.0.0/16'

@description('Subnets to create. Array of {name, cidr, delegation?, serviceEndpoints?, privateEndpointPolicies?}')
param subnets array = [
  { name: 'snet-compute', cidr: '10.10.1.0/24', delegation: 'Microsoft.App/environments' }
  { name: 'snet-data', cidr: '10.10.2.0/24' }
  { name: 'snet-mgmt', cidr: '10.10.3.0/24' }
  { name: 'snet-apim', cidr: '10.10.4.0/24' }
]

@description('LA workspace ID for flow logs / diagnostic settings')
param workspaceId string = ''

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ addressPrefix ] }
    subnets: [for s in subnets: {
      name: s.name
      properties: {
        addressPrefix: s.cidr
        delegations: contains(s, 'delegation') ? [{
          name: '${s.name}-delegation'
          properties: { serviceName: s.delegation }
        }] : []
        serviceEndpoints: contains(s, 'serviceEndpoints') ? [for se in s.serviceEndpoints: { service: se }] : []
        privateEndpointNetworkPolicies: contains(s, 'privateEndpointPolicies') ? s.privateEndpointPolicies : 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
      }
    }]
  }
}

output id string = vnet.id
output name string = vnet.name
output computeSubnetId string = first(filter(vnet.properties.subnets, s => s.name == 'snet-compute')).id
output dataSubnetId string = first(filter(vnet.properties.subnets, s => s.name == 'snet-data')).id
output mgmtSubnetId string = first(filter(vnet.properties.subnets, s => s.name == 'snet-mgmt')).id
output apimSubnetId string = !empty(filter(vnet.properties.subnets, s => s.name == 'snet-apim')) ? first(filter(vnet.properties.subnets, s => s.name == 'snet-apim')).id : ''
