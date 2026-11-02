// Container Apps environment, the API (public, scales to zero) and the sync (a scheduled job that runs and exits)
param location string
param appName string
param tags object
param workspaceName string
param apiImage string
param syncImage string
param apiIdentityId string
param apiIdentityClientId string
param syncIdentityId string
param syncIdentityClientId string
param sqlServerFqdn string
param databaseName string
@description('Where the API and the sync send OpenTelemetry data (Application Insights, keyless).')
param appInsightsConnectionString string
@description('e.g. https://kv-fh-xxx.vault.azure.net/')
param keyVaultUri string
@description('The application ID from Enable Banking\'s control panel.')
param enableBankingApplicationId string
@description('When the sync runs, as a cron expression in UTC.')
param syncSchedule string
@description('Entra ID tenant whose tokens the API accepts.')
param authTenantId string
@description('The API\'s app registration (client) ID: the audience of the tokens it accepts.')
param authApiClientId string
@description('The owner\'s object ID in the tenant: the only person whose tokens the API accepts.')
param authOwnerObjectId string

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: workspaceName
}

resource environment 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: 'cae-${appName}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        // Read at deploy time, never stored in the template or its outputs
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    // Consumption profile only: pay per second of use, scale to zero, monthly free grant
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// No password: SqlClient asks the managed identity (selected by its client ID) for an Entra ID token.
// Connect Timeout covers the serverless database resuming from auto-pause (up to about a minute).
func sqlConnectionString(server string, database string, identityClientId string) string =>
  'Server=tcp:${server},1433;Database=${database};Authentication=Active Directory Managed Identity;User Id=${identityClientId};Encrypt=True;Connect Timeout=60'

// Container Apps reads them from Key Vault with the app's identity, and picks up a new version within 30 minutes
// (no version in the URL). The values never appear in the template, the deployment or the app's configuration
func keyVaultSecret(vaultUri string, name string, identityId string) object => {
  name: name
  keyVaultUrl: '${vaultUri}secrets/${name}'
  identity: identityId
}

// Built from the environment, not read from the app, so the API can be given its own callback URL
var apiHost = 'ca-${appName}-api.${environment.properties.defaultDomain}'

// Settings both the API and the sync need
func commonEnv(connectionString string, identityClientId string, appInsights string, enableBankingAppId string) array => [
  // Same key the Aspire AppHost injects locally (ConnectionStrings:financesdb)
  {
    name: 'ConnectionStrings__financesdb'
    value: connectionString
  }
  {
    name: 'EnableBanking__ApplicationId'
    value: enableBankingAppId
  }
  {
    name: 'EnableBanking__PrivateKey'
    secretRef: 'enablebanking-private-key'
  }
  // The container app could have several user-assigned identities: this says which one to use
  {
    name: 'AZURE_CLIENT_ID'
    value: identityClientId
  }
  // Go straight to the managed identity instead of trying the whole DefaultAzureCredential chain
  {
    name: 'AZURE_TOKEN_CREDENTIALS'
    value: 'ManagedIdentityCredential'
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsights
  }
]

resource api 'Microsoft.App/containerApps@2026-01-01' = {
  name: 'ca-${appName}-api'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${apiIdentityId}': {}
    }
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: [
        keyVaultSecret(keyVaultUri, 'enablebanking-private-key', apiIdentityId)
        keyVaultSecret(keyVaultUri, 'bank-linking-allowed-ibans', apiIdentityId)
      ]
      // Public: the Android app calls it from anywhere, and the bank sends the browser back to it. Every endpoint
      // but the health checks and the bank's callback requires an Entra ID token
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        // HTTP is redirected to HTTPS
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: concat(
            commonEnv(
              sqlConnectionString(sqlServerFqdn, databaseName, apiIdentityClientId),
              apiIdentityClientId,
              appInsightsConnectionString,
              enableBankingApplicationId
            ),
            [
              // Must be one of the redirect URLs registered in Enable Banking's control panel (infra/README.md)
              {
                name: 'EnableBanking__RedirectUrl'
                value: 'https://${apiHost}/api/connections/callback'
              }
              {
                name: 'BankLinking__AllowedIbans'
                secretRef: 'bank-linking-allowed-ibans'
              }
              {
                name: 'Authentication__TenantId'
                value: authTenantId
              }
              {
                name: 'Authentication__ClientId'
                value: authApiClientId
              }
              {
                name: 'Authentication__OwnerObjectId'
                value: authOwnerObjectId
              }
            ]
          )
          probes: [
            // Restart only if the process itself is stuck
            {
              type: 'Liveness'
              httpGet: {
                path: '/alive'
                port: 8080
              }
              periodSeconds: 10
            }
            // Stop sending traffic while the database is unreachable (includes the SQL health check). Generous
            // timeout: the first connection needs a managed identity token, and the database may be resuming
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              timeoutSeconds: 10
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http'
            http: {
              metadata: {
                concurrentRequests: '20'
              }
            }
          }
        ]
      }
    }
  }
}

// The sync: a job that runs on a schedule, reads the banks, saves and exits. It costs only while it runs, and has no
// ingress. A run that ends with exit code 1 (an account failed) shows as Failed in the job's history
resource sync 'Microsoft.App/jobs@2026-01-01' = {
  name: 'caj-${appName}-sync'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${syncIdentityId}': {}
    }
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        cronExpression: syncSchedule
        parallelism: 1
        replicaCompletionCount: 1
      }
      // A run takes seconds; ten minutes covers the database resuming from auto-pause and slow banks
      replicaTimeout: 600
      // No retry: banks allow a few background requests a day, and the next run picks up what this one missed
      replicaRetryLimit: 0
      secrets: [
        keyVaultSecret(keyVaultUri, 'enablebanking-private-key', syncIdentityId)
      ]
    }
    template: {
      containers: [
        {
          name: 'sync'
          image: syncImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: commonEnv(
            sqlConnectionString(sqlServerFqdn, databaseName, syncIdentityClientId),
            syncIdentityClientId,
            appInsightsConnectionString,
            enableBankingApplicationId
          )
        }
      ]
    }
  }
}

output apiFqdn string = api.properties.configuration.ingress.fqdn
output apiId string = api.id
output syncJobName string = sync.name
