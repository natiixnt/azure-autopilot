@description('Front Door profile name')
param name string
param tags object = {}

@allowed([ 'Standard_AzureFrontDoor', 'Premium_AzureFrontDoor' ])
param sku string = 'Premium_AzureFrontDoor'

@description('Origin host (FQDN of backend, e.g. Container App)')
param originHost string

@description('Origin host header (defaults to originHost)')
param originHostHeader string = originHost

@description('Origin port')
param originPort int = 443

@description('Custom domain (optional)')
param customDomain string = ''

@description('LA workspace ID for diagnostic settings')
param workspaceId string = ''

@description('WAF policy ID (optional, Premium only)')
param wafPolicyId string = ''

resource fd 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: name
  location: 'Global'
  tags: tags
  sku: { name: sku }
  properties: {}
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: fd
  name: '${name}-endpoint'
  location: 'Global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: fd
  name: 'default'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'origin1'
  properties: {
    hostName: originHost
    httpPort: 80
    httpsPort: originPort
    originHostHeader: originHostHeader
    enabledState: 'Enabled'
    priority: 1
    weight: 1000
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    originGroup: { id: originGroup.id }
    supportedProtocols: [ 'Http', 'Https' ]
    patternsToMatch: [ '/*' ]
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Enabled'
  }
  dependsOn: [ origin ]
}

// Optional: WAF + custom domain go in extension modules to keep this lean

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  scope: fd
  name: 'to-la'
  properties: {
    workspaceId: workspaceId
    logs: [
      { category: 'FrontDoorAccessLog', enabled: true }
      { category: 'FrontDoorHealthProbeLog', enabled: true }
      { category: 'FrontDoorWebApplicationFirewallLog', enabled: true }
    ]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output id string = fd.id
output name string = fd.name
output endpointUrl string = 'https://${endpoint.properties.hostName}'
output endpointHostName string = endpoint.properties.hostName
