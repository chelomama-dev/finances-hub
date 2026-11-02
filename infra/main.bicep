// Finances Hub infrastructure: the API and the sync job on Container Apps, Azure SQL (free offer), Key Vault and
// Application Insights, in one resource group.
// Deploy with: az deployment group create -g <rg> -p infra/main.bicepparam (see infra/README.md)
targetScope = 'resourceGroup'

@description('Azure region for every resource. Defaults to the resource group region.')
param location string = resourceGroup().location

@description('Short name used to build resource names.')
param appName string = 'financeshub'

@description('Full API image reference, e.g. ghcr.io/owner/finances-hub-api:sha-abc1234. An immutable sha tag, not latest.')
param apiImage string

@description('Full sync image reference, e.g. ghcr.io/owner/finances-hub-sync:sha-abc1234.')
param syncImage string

@description('Entra ID principal that administers the SQL server: display name or UPN.')
param sqlAdminLogin string

@description('Object ID of that Entra ID principal.')
param sqlAdminObjectId string

@allowed(['User', 'Group', 'Application'])
param sqlAdminPrincipalType string = 'Group'

@description('Public IP allowed through the SQL firewall, to run migrations from your machine. Empty = no rule.')
param clientIpAddress string = ''

@description('The application ID from Enable Banking\'s control panel.')
param enableBankingApplicationId string

// Banks allow about four background requests a day. 6, 12, 18 and 22 UTC are 7, 13, 19 and 23 in Spain in winter
// (an hour later in summer). Container Apps jobs only take UTC
@description('When the sync runs, as a cron expression in UTC.')
param syncSchedule string = '0 6,12,18,22 * * *'

@description('The API\'s Entra ID app registration (client) ID: the audience of the tokens it accepts.')
param authApiClientId string

var tags = {
  app: appName
  managedBy: 'bicep'
}

// User-assigned (not system-assigned) so they exist before the apps: the SQL users can be created for them
// independently, and they survive an app being deleted and recreated
resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${appName}-api'
  location: location
  tags: tags
}

resource syncIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${appName}-sync'
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  params: {
    location: location
    name: 'log-${appName}'
    appInsightsName: 'appi-${appName}'
    tags: tags
    publisherPrincipalIds: [
      apiIdentity.properties.principalId
      syncIdentity.properties.principalId
    ]
  }
}

module sql 'modules/sql.bicep' = {
  params: {
    location: location
    // SQL server names are global DNS names, so they need a unique suffix
    serverName: 'sql-${appName}-${uniqueString(resourceGroup().id)}'
    databaseName: 'financesdb'
    tags: tags
    adminLogin: sqlAdminLogin
    adminObjectId: sqlAdminObjectId
    adminPrincipalType: sqlAdminPrincipalType
    clientIpAddress: clientIpAddress
  }
}

module keyVault 'modules/keyvault.bicep' = {
  params: {
    location: location
    // Global DNS name too, and 24 characters at most: kv-fh- plus the 13 of uniqueString
    vaultName: 'kv-fh-${uniqueString(resourceGroup().id)}'
    tags: tags
    readerPrincipalIds: [
      apiIdentity.properties.principalId
      syncIdentity.properties.principalId
    ]
  }
}

module apps 'modules/container-apps.bicep' = {
  params: {
    location: location
    appName: appName
    tags: tags
    workspaceName: monitoring.outputs.name
    apiImage: apiImage
    syncImage: syncImage
    apiIdentityId: apiIdentity.id
    apiIdentityClientId: apiIdentity.properties.clientId
    syncIdentityId: syncIdentity.id
    syncIdentityClientId: syncIdentity.properties.clientId
    sqlServerFqdn: sql.outputs.serverFqdn
    databaseName: sql.outputs.databaseName
    // A module output: the apps wait for Application Insights and their role on it
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    // A module output: the apps wait for the vault and their role on it
    keyVaultUri: keyVault.outputs.vaultUri
    enableBankingApplicationId: enableBankingApplicationId
    syncSchedule: syncSchedule
    authTenantId: tenant().tenantId
    authApiClientId: authApiClientId
  }
}

output apiUrl string = 'https://${apps.outputs.apiFqdn}'
output bankCallbackUrl string = 'https://${apps.outputs.apiFqdn}/api/connections/callback'
output syncJobName string = apps.outputs.syncJobName
output sqlServerFqdn string = sql.outputs.serverFqdn
output databaseName string = sql.outputs.databaseName
output keyVaultName string = keyVault.outputs.name
output apiIdentityName string = apiIdentity.name
output syncIdentityName string = syncIdentity.name
