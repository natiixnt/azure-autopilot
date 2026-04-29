// Generic orchestrator entry point. Most projects will copy this and trim/extend
// based on their pattern. This default composes the webapp-saas blueprint;
// for ai-app, data-platform, etc., add/swap modules.

targetScope = 'resourceGroup'

@description('Project / app name slug')
param namePrefix string

@allowed([ 'dev', 'test', 'prod' ])
param environment string

param location string = resourceGroup().location

@description('AAD group object ID that admins the database')
param sqlAdminGroupObjectId string

@description('Email recipients for budget + alert action group')
param notifyEmails array = []

var tags = {
  Environment: environment
  Project: namePrefix
  ManagedBy: 'bicep'
  CostCenter: 'TBD'
  Owner: 'TBD'
}

// ─── Foundation ──────────────────────────────────────────────────────────────

module la 'modules/log-analytics.bicep' = {
  name: 'la'
  params: {
    name: 'la-${namePrefix}-${environment}'
    location: location
    tags: tags
    retentionInDays: environment == 'prod' ? 90 : 30
    dailyQuotaGb: environment == 'prod' ? 0 : 5
  }
}

module ai 'modules/app-insights.bicep' = {
  name: 'ai'
  params: {
    name: 'ai-${namePrefix}-${environment}'
    location: location
    tags: tags
    workspaceId: la.outputs.id
  }
}

module umi 'modules/managed-identity.bicep' = {
  name: 'umi'
  params: { name: 'umi-${namePrefix}-${environment}', location: location, tags: tags }
}

module ag 'modules/action-group.bicep' = {
  name: 'ag'
  params: {
    name: 'ag-${namePrefix}-${environment}'
    shortName: take(namePrefix, 12)
    tags: tags
    emails: [for (e, i) in notifyEmails: { name: 'rcv${i}', email: e }]
  }
}

// ─── Network ─────────────────────────────────────────────────────────────────

module vnet 'modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    name: 'vnet-${namePrefix}-${environment}'
    addressPrefix: environment == 'prod' ? '10.30.0.0/16' : (environment == 'test' ? '10.20.0.0/16' : '10.10.0.0/16')
    location: location
    tags: tags
    workspaceId: la.outputs.id
  }
}

// ─── Data ────────────────────────────────────────────────────────────────────

module kv 'modules/key-vault.bicep' = {
  name: 'kv'
  params: {
    name: 'kv-${namePrefix}-${environment}-${take(uniqueString(resourceGroup().id), 5)}'
    location: location
    tags: tags
    privateEndpointSubnetId: vnet.outputs.dataSubnetId
    workspaceId: la.outputs.id
    enablePurgeProtection: environment == 'prod'
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: toLower('st${namePrefix}${environment}${take(uniqueString(resourceGroup().id), 5)}')
    location: location
    tags: tags
    skuName: environment == 'prod' ? 'Standard_GZRS' : 'Standard_LRS'
    privateEndpointSubnetId: vnet.outputs.dataSubnetId
    workspaceId: la.outputs.id
    containers: [ 'app-uploads', 'logs' ]
  }
}

module pg 'modules/postgres-flexible.bicep' = {
  name: 'pg'
  params: {
    name: 'pg-${namePrefix}-${environment}'
    location: location
    tags: tags
    skuName: environment == 'prod' ? 'Standard_D2ds_v5' : 'Standard_B1ms'
    tier: environment == 'prod' ? 'GeneralPurpose' : 'Burstable'
    delegatedSubnetId: vnet.outputs.dataSubnetId
    aadAdminGroupObjectId: sqlAdminGroupObjectId
    workspaceId: la.outputs.id
    highAvailability: environment == 'prod' ? 'ZoneRedundant' : 'Disabled'
    backupRetentionDays: environment == 'prod' ? 35 : 7
    geoRedundantBackup: environment == 'prod'
  }
}

// ─── Compute ─────────────────────────────────────────────────────────────────

module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    name: 'acr${namePrefix}${environment}${take(uniqueString(resourceGroup().id), 5)}'
    location: location
    tags: tags
    sku: environment == 'prod' ? 'Premium' : 'Standard'
    privateEndpointSubnetId: environment == 'prod' ? vnet.outputs.dataSubnetId : ''
    workspaceId: la.outputs.id
  }
}

module caEnv 'modules/container-apps-env.bicep' = {
  name: 'caEnv'
  params: {
    name: 'cae-${namePrefix}-${environment}'
    location: location
    tags: tags
    logAnalyticsCustomerId: la.outputs.customerId
    logAnalyticsSharedKey: listKeys(la.outputs.id, '2023-09-01').primarySharedKey
    appInsightsConnectionString: ai.outputs.connectionString
    infrastructureSubnetId: vnet.outputs.computeSubnetId
    workloadProfiles: environment == 'prod' ? [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
      { name: 'D4', workloadProfileType: 'D4', minimumCount: 1, maximumCount: 3 }
    ] : [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
    zoneRedundant: environment == 'prod'
  }
}

module app 'modules/container-app.bicep' = {
  name: 'app'
  params: {
    name: 'ca-${namePrefix}-app-${environment}'
    location: location
    tags: tags
    environmentId: caEnv.outputs.id
    userAssignedIdentityId: umi.outputs.id
    containerImage: 'mcr.microsoft.com/k8se/quickstart:latest'   // replace with real image post-first-deploy
    registryServer: acr.outputs.loginServer
    targetPort: 8080
    minReplicas: environment == 'prod' ? 2 : 0
    maxReplicas: environment == 'prod' ? 10 : 3
    workloadProfileName: environment == 'prod' ? 'D4' : 'Consumption'
    envVars: [
      { name: 'AZURE_CLIENT_ID', value: umi.outputs.clientId }
      { name: 'POSTGRES_HOST', value: pg.outputs.fqdn }
      { name: 'STORAGE_ACCOUNT', value: storage.outputs.name }
      { name: 'KEY_VAULT_URI', value: kv.outputs.uri }
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: ai.outputs.connectionString }
    ]
  }
}

// ─── RBAC ────────────────────────────────────────────────────────────────────

// KV Secrets User on KV
module rbacKv 'modules/role-assignment.bicep' = {
  name: 'rbac-kv'
  params: {
    principalId: umi.outputs.principalId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6'
    scope: kv.outputs.id
  }
}

// AcrPull on ACR
module rbacAcr 'modules/role-assignment.bicep' = {
  name: 'rbac-acr'
  params: {
    principalId: umi.outputs.principalId
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    scope: acr.outputs.id
  }
}

// Storage Blob Data Contributor
module rbacStorage 'modules/role-assignment.bicep' = {
  name: 'rbac-storage'
  params: {
    principalId: umi.outputs.principalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    scope: storage.outputs.id
  }
}

// ─── Cost guardrails ─────────────────────────────────────────────────────────

module budget 'modules/budget.bicep' = if (!empty(notifyEmails)) {
  name: 'budget'
  params: {
    name: 'budget-${namePrefix}-${environment}'
    amount: environment == 'prod' ? 5000 : 500
    contactEmails: notifyEmails
    actionGroupId: ag.outputs.id
  }
}

// ─── Outputs ─────────────────────────────────────────────────────────────────

output workspaceId string = la.outputs.id
output appInsightsConnectionString string = ai.outputs.connectionString
output managedIdentityClientId string = umi.outputs.clientId
output managedIdentityPrincipalId string = umi.outputs.principalId
output keyVaultUri string = kv.outputs.uri
output acrLoginServer string = acr.outputs.loginServer
output postgresFqdn string = pg.outputs.fqdn
output containerAppFqdn string = app.outputs.fqdn
