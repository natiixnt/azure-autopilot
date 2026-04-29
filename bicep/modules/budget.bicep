// Budget at resource-group scope
targetScope = 'resourceGroup'

@description('Budget name')
param name string

@description('Monthly budget amount (in subscription default currency)')
param amount int

@description('Start date YYYY-MM-DD; defaults to first of current month')
param startDate string = '${utcNow('yyyy-MM')}-01'

@description('End date YYYY-MM-DD; defaults to 5 years out')
param endDate string = '${dateTimeAdd(utcNow(), 'P5Y', 'yyyy')}-12-31'

@description('Email recipients for budget notifications')
param contactEmails array

@description('Action group ID for notifications (optional)')
param actionGroupId string = ''

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: name
  properties: {
    timePeriod: {
      startDate: startDate
      endDate: endDate
    }
    timeGrain: 'Monthly'
    amount: amount
    category: 'Cost'
    notifications: {
      'Actual_50pct': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: contactEmails
        contactGroups: empty(actionGroupId) ? [] : [ actionGroupId ]
      }
      'Actual_80pct': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: contactEmails
        contactGroups: empty(actionGroupId) ? [] : [ actionGroupId ]
      }
      'Actual_100pct': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: contactEmails
        contactGroups: empty(actionGroupId) ? [] : [ actionGroupId ]
      }
      'Forecast_100pct': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: contactEmails
        contactGroups: empty(actionGroupId) ? [] : [ actionGroupId ]
      }
    }
  }
}

output id string = budget.id
