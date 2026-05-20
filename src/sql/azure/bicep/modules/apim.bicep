// API Management — BasicV2 + system-assigned MI + AOAI backend + Content Safety backend
// + Azure OpenAI API + llm-content-safety policy.
//
// MI auth to Cognitive Services (AOAI and Content Safety) is configured via
// <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
// inside the policy XML — see ../apim-policies/aoai-api.xml.

param location string
param apimName string
param aoaiEndpoint string
param csEndpoint string
param chatDeploymentName string
param publisherEmail string
param publisherName string = 'BRK223 Demo'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
    virtualNetworkType: 'None'
  }
}

resource aoaiBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'aoai-backend'
  properties: {
    url: '${aoaiEndpoint}openai'
    protocol: 'http'
    description: 'Azure OpenAI account; MI auth applied via policy.'
  }
}

resource csBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'cs-backend'
  properties: {
    url: csEndpoint
    protocol: 'http'
    description: 'Azure AI Content Safety; consumed by llm-content-safety policy.'
  }
}

// Azure OpenAI API — exposes /openai/deployments/{deployment-id}/chat/completions etc.
resource aoaiApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'azure-openai'
  properties: {
    displayName: 'Azure OpenAI (gateway)'
    path: 'openai'
    protocols: [ 'https' ]
    // MI all the way: SQL MI → APIM (Authorization: Bearer <SQL MI token for cognitiveservices.azure.com>)
    // APIM does NOT validate that token (demo simplification); the policy overwrites Authorization
    // with APIM's own MI-acquired token before forwarding to AOAI. No subscription keys anywhere.
    subscriptionRequired: false
    serviceUrl: '${aoaiEndpoint}openai'
    format: 'openapi+json'
    value: string({
      openapi: '3.0.1'
      info: {
        title: 'Azure OpenAI'
        version: '2024-10-21'
      }
      paths: {
        '/deployments/{deployment-id}/chat/completions': {
          post: {
            operationId: 'chat-completions'
            parameters: [
              {
                name: 'deployment-id'
                'in': 'path'
                required: true
                schema: { type: 'string' }
              }
              {
                name: 'api-version'
                'in': 'query'
                required: true
                schema: { type: 'string' }
              }
            ]
            requestBody: {
              required: true
              content: {
                'application/json': {
                  schema: { type: 'object' }
                }
              }
            }
            responses: {
              '200': { description: 'OK' }
            }
          }
        }
        '/deployments/{deployment-id}/embeddings': {
          post: {
            operationId: 'embeddings'
            parameters: [
              {
                name: 'deployment-id'
                'in': 'path'
                required: true
                schema: { type: 'string' }
              }
              {
                name: 'api-version'
                'in': 'query'
                required: true
                schema: { type: 'string' }
              }
            ]
            requestBody: {
              required: true
              content: {
                'application/json': {
                  schema: { type: 'object' }
                }
              }
            }
            responses: {
              '200': { description: 'OK' }
            }
          }
        }
      }
    })
  }
}

// Policy attaches the GenAI gateway behavior:
//   - llm-token-limit per subscription key
//   - llm-content-safety with shield-prompt and Hate/Violence/SelfHarm/Sexual thresholds
//   - llm-emit-token-metric to App Insights (dims: Client IP / API ID / User ID)
//   - authentication-managed-identity for AOAI bearer token
//   - set-backend-service to aoai-backend
resource aoaiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: aoaiApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim-policies/aoai-api.xml')
  }
}

output gatewayUrl  string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
output apimName    string = apim.name
