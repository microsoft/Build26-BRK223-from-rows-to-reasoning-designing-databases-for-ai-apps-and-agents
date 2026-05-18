// Azure AI Content Safety account.

param location string
param accountName string

resource cs 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  kind: 'ContentSafety'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
  }
}

output endpoint    string = cs.properties.endpoint
output accountName string = cs.name
