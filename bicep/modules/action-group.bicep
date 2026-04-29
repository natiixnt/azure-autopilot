@description('Action group name')
param name string

@description('Short name (max 12 chars)')
@maxLength(12)
param shortName string

param tags object = {}

@description('Email receivers [{ name, email }]')
param emails array = []

@description('SMS receivers [{ name, country, phone }]')
param smses array = []

@description('Webhook receivers (e.g. Teams) [{ name, url }]')
param webhooks array = []

resource ag 'Microsoft.Insights/actionGroups@2023-09-01-preview' = {
  name: name
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    groupShortName: shortName
    emailReceivers: [for e in emails: {
      name: e.name
      emailAddress: e.email
      useCommonAlertSchema: true
    }]
    smsReceivers: [for s in smses: {
      name: s.name
      countryCode: s.country
      phoneNumber: s.phone
    }]
    webhookReceivers: [for w in webhooks: {
      name: w.name
      serviceUri: w.url
      useCommonAlertSchema: true
    }]
  }
}

output id string = ag.id
output name string = ag.name
