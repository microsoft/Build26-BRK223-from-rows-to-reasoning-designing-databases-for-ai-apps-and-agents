// BRK223 — Azure hosting layer (lift-and-shift of Blazor + DAB).
//
// Deploys ON TOP OF main.bicep (which provisioned Hyperscale + AOAI + APIM +
// Content Safety). This file adds:
//
//   ACR          — private registry for the DAB container image.
//   ACA env      — workload profile environment for DAB.
//   ACA DAB app  — Data API Builder, system-assigned MI, HTTPS ingress,
//                  pulls image from ACR, points at Hyperscale.
//                  Connection string uses `Authentication=Active Directory
//                  Default` so DAB's SqlClient grabs an AAD token from the
//                  ACA system MI via DefaultAzureCredential.
//   Static Web App — hosting for the Blazor WASM front-end (no GitHub
//                    integration; deploy uploads built wwwroot directly).
//
// What lives OUTSIDE this file (because it depends on resources not in
// scope here):
//
//   * Role assignments on AOAI/APIM        — see modules/roles.bicep
//   * SQL MI grants for the ACA app        — see hosting/sql/grant_aca_mi.sql
//   * ACR image build/push                 — `az acr build` in the
//                                            Prep-Cloud-Hosting.ps1 orchestrator
//   * Blazor static files upload to SWA    — `dotnet publish` + `swa deploy`
//                                            in the orchestrator
//
// Deploy via:
//   az deployment group create -g <rg> -f hosting.bicep -p ...
//   (Prep-Cloud-Hosting.ps1 wraps this idempotently.)

targetScope = 'resourceGroup'

@description('Azure region. Default: resource group region.')
param location string = resourceGroup().location

@description('Short suffix for globally-unique resource names. Must match main.bicep nameSuffix so the SQL FQDN etc. resolve consistently.')
param nameSuffix string

@description('SQL logical server FQDN (e.g. zavasqlserver.database.windows.net). Used to build the DAB connection string.')
param sqlServerFqdn string

@description('SQL database name. Default: zavalivesitedb.')
param sqlDatabaseName string = 'zavalivesitedb'

@description('Container image reference for the DAB app. Default: a public placeholder so the first bicep deploy can succeed before the real image has been pushed to ACR. Prep-Cloud-Hosting.ps1 swaps to the ACR image via `az containerapp update` after `az acr build`.')
param dabImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('DAB container image tag in ACR (kept for backward compat; ignored when dabImage is set).')
param dabImageTag string = 'latest'

@description('Allowed CORS origins for the DAB ingress. The SWA URL is added after SWA is provisioned (chicken-and-egg).')
param dabAllowedOrigins array = ['*']

var acrName       = replace('zavaacr${nameSuffix}', '-', '')
var acaEnvName    = 'zava-aca-env-${nameSuffix}'
var acaDabName    = 'zava-dab-${nameSuffix}'
var swaName       = 'zava-web-${nameSuffix}'

// --- Container Registry -----------------------------------------------------
// Basic SKU is the cheapest registry tier; image is small (DAB upstream + a
// 6 KB config). AdminUser enabled so the initial ACA revision can pull the
// image during the same bicep deployment that creates the role assignment
// (MI-based pull would deadlock on principalId-not-yet-granted-AcrPull).
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// --- Container Apps environment ---------------------------------------------
// Consumption-only, no Log Analytics workspace (we don't need analytics for
// the demo; an attendee can add `appLogsConfiguration` later).
resource acaEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: acaEnvName
  location: location
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// --- DAB container app ------------------------------------------------------
// System-assigned MI is used both to pull from ACR (AcrPull role granted
// below) AND to authenticate to Azure SQL (granted via T-SQL post-deploy
// in hosting/sql/grant_aca_mi.sql — Bicep cannot CREATE USER FROM EXTERNAL
// PROVIDER).
//
// The connection string is parameterized via secretRef rather than env var
// so it doesn't leak in revision listings.
//
// Ingress is external on port 5000 (DAB's default). targetPort 5000 maps
// to the public HTTPS endpoint provided by the ACA environment, so the
// SWA-hosted Blazor app can reach it cross-origin.
resource acaDab 'Microsoft.App/containerApps@2024-03-01' = {
  name: acaDabName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    environmentId: acaEnv.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: true
        targetPort: 5000
        transport: 'auto'
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: dabAllowedOrigins
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
          allowCredentials: false
        }
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          // Authentication=Active Directory Default → SqlClient uses
          // DefaultAzureCredential, which inside ACA resolves to the
          // system-assigned MI. No password, no key, no SQL login.
          name: 'mssql-connection-string'
          value: 'Server=${sqlServerFqdn};Database=${sqlDatabaseName};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Command Timeout=180'
        }
        {
          // ACR admin password — used only to pull the image. SQL still
          // authenticates via the ACA system MI (passwordless).
          name: 'acr-password'
          value: acr.listCredentials().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'dab'
          image: dabImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'MSSQL_CONNECTION_STRING'
              secretRef: 'mssql-connection-string'
            }
            {
              // DAB honors ASPNETCORE_URLS to bind to all interfaces.
              name: 'ASPNETCORE_URLS'
              value: 'http://0.0.0.0:5000'
            }
          ]
          probes: [
            {
              type: 'Readiness'
              httpGet: {
                path: '/api/Incident?$first=1'
                port: 5000
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        // Single replica is plenty for a demo. Min 1 keeps cold-starts off
        // the stage (~30 s warm-up vs ~5 ms hot).
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// --- ACR pull role for the ACA MI -------------------------------------------
// Built-in role: AcrPull (7f951dda-4ed3-4680-a7ca-43fe172d538d)
resource acrPullOnAca 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, acaDab.id, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: acaDab.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// --- Static Web App (Free SKU) ---------------------------------------------
// Free SKU is fine for a demo: 100 GB bandwidth/month, custom domains, free
// SSL. No GitHub repository binding — we deploy the Blazor WASM wwwroot
// directly via `swa deploy` in the orchestrator.
resource swa 'Microsoft.Web/staticSites@2023-12-01' = {
  name: swaName
  location: 'eastus2'           // SWA Free is region-restricted; eastus2 is supported.
  sku: { name: 'Free', tier: 'Free' }
  properties: {
    // No repo linkage. We will publish content via `az staticwebapp` /
    // `swa deploy`. Builds happen on the developer / orchestrator machine.
    provider: 'Custom'
  }
}

// --- Outputs ----------------------------------------------------------------
output acrName            string = acr.name
output acrLoginServer     string = acr.properties.loginServer
output acaEnvName         string = acaEnv.name
output acaDabName         string = acaDab.name
output acaDabFqdn         string = acaDab.properties.configuration.ingress.fqdn
output acaDabPrincipalId  string = acaDab.identity.principalId
output swaName            string = swa.name
output swaDefaultHostname string = swa.properties.defaultHostname
