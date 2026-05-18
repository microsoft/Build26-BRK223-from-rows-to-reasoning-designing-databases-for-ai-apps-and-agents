// Azure SQL Hyperscale — logical server + database + firewall (AzureServices).
// AAD-only admin (no SQL auth). Vector / JSON support is built-in to SQL 2025.

param location string
param serverName string
param databaseName string
param aadAdminObjectId string
param aadAdminLogin string

@description('DB SKU name, e.g. HS_PRMS_32, HS_Gen5_32, HS_Gen5_2.')
param skuName string = 'HS_PRMS_32'

@description('DB SKU family. PRMS = Hyperscale Premium-series, Gen5 = standard Gen5.')
param skuFamily string = 'PRMS'

@description('DB SKU capacity (vCores).')
param skuCapacity int = 32

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: aadAdminLogin
      sid: aadAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// Allow any Azure service (incl. APIM, dev clients with public IP via AAD)
resource fwAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: skuName
    tier: 'Hyperscale'
    family: skuFamily
    capacity: skuCapacity
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}

output serverFqdn   string = sqlServer.properties.fullyQualifiedDomainName
output serverName   string = sqlServer.name
output principalId  string = sqlServer.identity.principalId
