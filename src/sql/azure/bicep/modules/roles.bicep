// Role assignments — 'Cognitive Services User' on AOAI + Content Safety:
//   - APIM system-assigned MI: needs role on both AOAI (for backend forwarding)
//     and Content Safety (for the llm-content-safety policy).
//   - SQL logical server system-assigned MI: needs role on AOAI only
//     (direct sp_invoke + EXTERNAL MODEL embeddings). SQL never calls
//     Content Safety directly — that's APIM's job inside the gateway policy.

param apimPrincipalId string
param sqlPrincipalId string
param aoaiAccountName string
param csAccountName string

// Built-in role: Cognitive Services User
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiAccountName
}

resource cs 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: csAccountName
}

resource apimOnAoai 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aoai
  name: guid(aoai.id, apimPrincipalId, cognitiveServicesUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apimOnCs 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cs
  name: guid(cs.id, apimPrincipalId, cognitiveServicesUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource sqlOnAoai 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aoai
  name: guid(aoai.id, sqlPrincipalId, cognitiveServicesUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: sqlPrincipalId
    principalType: 'ServicePrincipal'
  }
}
