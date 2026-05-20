// BRK223 — Azure variant — RG-scope orchestrator.
//
// Deploy:
//   az deployment group create -g zavalivesiterg -f main.bicep -p @params.json
//
// Or via Prep-Cloud.ps1 (idempotent, recommended).

targetScope = 'resourceGroup'

@description('Azure region. Default: resource group region.')
param location string = resourceGroup().location

@description('Short suffix for globally-unique resource names. Auto from RG id.')
param nameSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('AAD principal that will be the SQL server AAD admin (object id).')
param sqlAadAdminObjectId string

@description('AAD principal login (UPN) for display.')
param sqlAadAdminLogin string

@description('APIM publisher email (required by ApiManagement service).')
param publisherEmail string

@description('APIM publisher name displayed in the developer portal.')
param publisherName string = 'BRK223 Demo'

@description('AOAI chat deployment name. Cannot contain dots.')
param chatDeploymentName string = 'gpt-5-4-mini'

@description('AOAI chat model name.')
param chatModelName string = 'gpt-5.4-mini'

@description('AOAI chat model version.')
param chatModelVersion string = '2026-03-17'

@description('AOAI embeddings deployment name.')
param embedDeploymentName string = 'text-embedding-3-small'

@description('AOAI embeddings model name.')
param embedModelName string = 'text-embedding-3-small'

@description('AOAI embeddings model version.')
param embedModelVersion string = '1'

@description('Chat TPM capacity in 1000-token units.')
param chatCapacity int = 50

@description('Embeddings TPM capacity in 1000-token units.')
param embedCapacity int = 30

@description('SQL logical server name. Must be globally unique.')
param sqlServerName string = 'zavasqlserver-${nameSuffix}'

@description('SQL database name. Default: zavalivesitedb.')
param sqlDatabaseName string = 'zavalivesitedb'

@description('SQL DB SKU name (e.g. HS_PRMS_32 = Hyperscale Premium-series 32 vCore).')
param sqlSkuName string = 'HS_PRMS_32'

@description('SQL DB SKU family (Gen5 | PRMS).')
param sqlSkuFamily string = 'PRMS'

@description('SQL DB SKU capacity (vCores).')
param sqlSkuCapacity int = 32

var aoaiName      = 'zava-aoai-${nameSuffix}'
var csName        = 'zava-cs-${nameSuffix}'
var apimName      = 'zava-apim-${nameSuffix}'

module sql 'modules/sql.bicep' = {
  name: 'sql'
  params: {
    location: location
    serverName: sqlServerName
    databaseName: sqlDatabaseName
    aadAdminObjectId: sqlAadAdminObjectId
    aadAdminLogin: sqlAadAdminLogin
    skuName: sqlSkuName
    skuFamily: sqlSkuFamily
    skuCapacity: sqlSkuCapacity
  }
}

module openai 'modules/openai.bicep' = {
  name: 'openai'
  params: {
    location: location
    accountName: aoaiName
    chatDeploymentName: chatDeploymentName
    chatModelName: chatModelName
    chatModelVersion: chatModelVersion
    chatCapacity: chatCapacity
    embedDeploymentName: embedDeploymentName
    embedModelName: embedModelName
    embedModelVersion: embedModelVersion
    embedCapacity: embedCapacity
  }
}

module cs 'modules/contentsafety.bicep' = {
  name: 'contentsafety'
  params: {
    location: location
    accountName: csName
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    location: location
    apimName: apimName
    aoaiEndpoint: openai.outputs.endpoint
    csEndpoint: cs.outputs.endpoint
    chatDeploymentName: chatDeploymentName
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

module roles 'modules/roles.bicep' = {
  name: 'roles'
  params: {
    apimPrincipalId: apim.outputs.principalId
    sqlPrincipalId: sql.outputs.principalId
    aoaiAccountName: aoaiName
    csAccountName: csName
  }
}

output sqlServerFqdn      string = sql.outputs.serverFqdn
output sqlDatabaseName    string = sqlDatabaseName
output aoaiEndpoint       string = openai.outputs.endpoint
output aoaiAccountName    string = aoaiName
output csEndpoint         string = cs.outputs.endpoint
output csAccountName      string = csName
output apimGatewayUrl     string = apim.outputs.gatewayUrl
output apimName           string = apimName
output chatDeploymentName string = chatDeploymentName
output embedDeploymentName string = embedDeploymentName
