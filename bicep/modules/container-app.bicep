@description('Container App name')
param name string
param location string = resourceGroup().location
param tags object = {}

@description('Container Apps environment ID')
param environmentId string

@description('User-assigned managed identity ID (for ACR pull + KV + data plane)')
param userAssignedIdentityId string

@description('Container image (full path)')
param containerImage string

@description('ACR login server (for registries[].server)')
param registryServer string = ''

@description('Target port for ingress')
param targetPort int = 8080

@description('External (public) ingress?')
param ingressExternal bool = true

@description('Internal-only ingress?')
param ingressInternal bool = false

@description('Min replicas (0 for scale-to-zero on Consumption)')
@minValue(0)
@maxValue(1000)
param minReplicas int = 0

@description('Max replicas')
@minValue(1)
@maxValue(1000)
param maxReplicas int = 10

@description('Workload profile name (must exist in env)')
param workloadProfileName string = 'Consumption'

@description('CPU cores')
param cpu string = '0.5'
@description('Memory')
param memory string = '1Gi'

@description('Environment variables')
param envVars array = []

@description('Secrets to mount (KV-backed). Array of {name, keyVaultUrl, identity?}')
param secrets array = []

@description('Scale rules (HTTP, KEDA-based)')
param scaleRules array = [
  { name: 'http-scale', http: { metadata: { concurrentRequests: '50' } } }
]

resource ca 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${userAssignedIdentityId}': {} }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: workloadProfileName
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: ingressExternal || ingressInternal ? {
        external: ingressExternal && !ingressInternal
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        traffic: [{ weight: 100, latestRevision: true }]
      } : null
      registries: !empty(registryServer) ? [{
        server: registryServer
        identity: userAssignedIdentityId
      }] : []
      secrets: secrets
    }
    template: {
      containers: [{
        name: 'app'
        image: containerImage
        resources: { cpu: json(cpu), memory: memory }
        env: envVars
      }]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: scaleRules
      }
    }
  }
}

output id string = ca.id
output name string = ca.name
output fqdn string = ca.properties.configuration.ingress.?fqdn ?? ''
output latestRevisionName string = ca.properties.latestRevisionName
