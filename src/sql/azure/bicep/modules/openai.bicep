// Azure OpenAI account + two deployments (chat + embeddings).

param location string
param accountName string

param chatDeploymentName string
param chatModelName string
param chatModelVersion string
param chatCapacity int
param chatSkuName string = 'GlobalStandard'

param embedDeploymentName string
param embedModelName string
param embedModelVersion string
param embedCapacity int
param embedSkuName string = 'Standard'

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  kind: 'OpenAI'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Deploy chat model first; embeddings depends on it to serialize (AOAI deployments are not parallel-safe).
resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aoai
  name: chatDeploymentName
  sku: {
    name: chatSkuName
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
}

resource embedDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aoai
  name: embedDeploymentName
  sku: {
    name: embedSkuName
    capacity: embedCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embedModelName
      version: embedModelVersion
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
  dependsOn: [ chatDeployment ]
}

output endpoint    string = aoai.properties.endpoint
output accountName string = aoai.name
