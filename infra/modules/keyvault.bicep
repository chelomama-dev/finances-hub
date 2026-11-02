// Key Vault for what Entra ID can't replace: Enable Banking's private key, and the IBANs the app may store (personal
// data, so not in the public repo). Access by Azure RBAC only. Bicep creates the vault and who may read it; the
// secrets themselves are set by a person with az keyvault secret set, so their values never pass through the repo,
// the pipeline or a deployment's history (infra/README.md).
param location string
@description('Globally unique, 3-24 letters, digits and hyphens.')
@minLength(3)
@maxLength(24)
param vaultName string
param tags object
@description('Principals (the API\'s and the sync\'s managed identities) that read the secrets.')
param readerPrincipalIds array

resource vault 'Microsoft.KeyVault/vaults@2026-05-15' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      // Standard: secrets don't need HSM-backed keys (Premium)
      name: 'standard'
    }
    // Roles decide who reads what; access policies are the old model
    enableRbacAuthorization: true
    // A deleted secret, or the whole vault, can be recovered for a week
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Purge protection can never be turned off, and it would block reusing the vault's name for the retention
    // days after a delete. The key can be regenerated in Enable Banking's control panel, so not needed yet
    enablePurgeProtection: null
    // Public endpoint, Entra ID required: the Consumption environment has no virtual network for a private
    // endpoint. Nothing gets in without a role on the vault
    publicNetworkAccess: 'Enabled'
  }
}

// Built-in role "Key Vault Secrets User": read secret values, nothing else (no listing keys, no writing)
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource secretsAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in readerPrincipalIds: {
    scope: vault
    name: guid(vault.id, principalId, secretsUserRoleId)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]

output name string = vault.name
// e.g. https://kv-financeshub-xxx.vault.azure.net/
output vaultUri string = vault.properties.vaultUri
