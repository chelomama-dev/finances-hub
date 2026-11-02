using 'main.bicep'

// Immutable tags (sha-xxxxxxx): the deployment always says exactly which commit is running.
// The pipeline sets IMAGE_TAG to the commit it just built; by hand, see infra/README.md.
var imageTag = readEnvironmentVariable('IMAGE_TAG')
param apiImage = 'ghcr.io/chelomama-dev/finances-hub-api:${imageTag}'
param syncImage = 'ghcr.io/chelomama-dev/finances-hub-sync:${imageTag}'

// The values come from the environment, so no IDs are in the (public) repo. The bootstrap script stores them as
// variables of the GitHub environment; by hand, see infra/README.md
param sqlAdminLogin = readEnvironmentVariable('SQL_ADMIN_LOGIN')
param sqlAdminObjectId = readEnvironmentVariable('SQL_ADMIN_OBJECT_ID')
param sqlAdminPrincipalType = readEnvironmentVariable('SQL_ADMIN_PRINCIPAL_TYPE', 'Group')
param clientIpAddress = readEnvironmentVariable('CLIENT_IP', '')
param enableBankingApplicationId = readEnvironmentVariable('ENABLE_BANKING_APPLICATION_ID')
param authApiClientId = readEnvironmentVariable('AUTH_API_CLIENT_ID')
