@description('Principal that gets the role (object id of UMI/SP/group/user)')
param principalId string

@description('Role definition GUID (the role ID, not the full path)')
param roleDefinitionId string

@description('Resource ID to scope the assignment to')
param scope string = resourceGroup().id

@description('Type of principal - affects eventual consistency handling')
@allowed([ 'ServicePrincipal', 'User', 'Group' ])
param principalType string = 'ServicePrincipal'

@description('Description for the assignment')
param description string = ''

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // GUID name derived from scope + principal + role for idempotency
  name: guid(scope, principalId, roleDefinitionId)
  scope: tenantResourceId(split(scope, '/')[1] == 'subscriptions' ? 'Microsoft.Resources/subscriptions' : 'Microsoft.Resources/resourceGroups', '')
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: principalType
    description: description
  }
}

output id string = ra.id
