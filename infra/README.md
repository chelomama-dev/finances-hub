# Infrastructure (Bicep)

Everything Finances Hub needs in Azure, declared in `main.bicep`. Built on the same patterns as
[Plumy's](https://github.com/chelomama-dev/plumy/tree/main/infra): Entra ID everywhere, no passwords, secrets only in
Key Vault, and nothing that costs money while idle.

| Resource | Name | Notes |
|---|---|---|
| Log Analytics workspace | `log-financeshub` | Container logs, 30-day retention, 0.1 GB/day cap |
| Application Insights | `appi-financeshub` | Traces, metrics and logs from the API and the sync (OpenTelemetry). Local auth disabled: both identities are *Monitoring Metrics Publisher* on it |
| User-assigned managed identities | `id-financeshub-api`, `id-financeshub-sync` | Each app's identity for Azure SQL, Key Vault and Application Insights |
| Azure SQL server + database | `sql-financeshub-<unique>` / `financesdb` | Serverless free offer, Entra ID auth only, pauses when idle and when the free limit runs out |
| Key Vault | `kv-fh-<unique>` | Enable Banking's private key and the allowed IBANs. Azure RBAC, 7-day soft delete; both identities are *Key Vault Secrets User*. The secrets are set by hand: see [Secrets](#secrets) |
| Container Apps environment | `cae-financeshub` | Consumption profile, scale to zero |
| Container App (API) | `ca-financeshub-api` | Public ingress (HTTPS only), 0–1 replicas, liveness `/alive`, readiness `/health` |
| Container Apps job (sync) | `caj-financeshub-sync` | Runs on a schedule (`syncSchedule`, 4 times a day), reads the banks, saves and exits. No ingress |

The images come from GHCR (public packages, so no registry credentials). Always deploy an immutable `sha-xxxxxxx` tag.

## Why these choices

- **France Central.** The Azure SQL free offer allows 10 databases per subscription, but all in one region, and the
  subscription's first one (Plumy's) is in France Central. Everything stays in that region.
- **The API is public, the data is not.** The Android app calls the API from anywhere, and the bank sends the
  browser back to it after a login, so its ingress is external. Every endpoint except the health checks and the
  bank's callback requires an Entra ID access token with the API's scope **and the owner's object ID**: anyone else
  signed in to the tenant gets a 403. Outside Development the API refuses to start without that configuration.
- **A job, not an app, for the sync.** A Container Apps job runs, exits and costs only while it runs. Banks allow
  about four background requests a day, so it runs four times (`0 6,12,18,22 * * *` in UTC: 7, 13, 19 and 23 in Spain
  in winter) and never retries a failed run: the next run picks up what this one missed
  ([ADR 0001](../docs/adr/0001-sync-replaces-a-recent-window-of-transactions.md)).
- **Secrets in Key Vault, referenced by Container Apps.** The values never appear in the template, a deployment or the
  apps' configuration; Container Apps reads them with each app's identity and picks up a new version within 30
  minutes.

## Manual deployment

Prerequisites: Azure CLI logged in (`az login`), Bicep (`az bicep install`), the .NET SDK and `dotnet tool restore`.

### 1. Resource group

```bash
az group create --name rg-financeshub --location francecentral --tags app=financeshub
```

### 2. Parameters

`main.bicepparam` reads them from the environment, so no IDs are in this public repo:

```bash
export IMAGE_TAG=sha-$(git rev-parse --short=7 origin/main)   # an image the CI already published
export SQL_ADMIN_LOGIN=sg-financeshub-sql-admins
export SQL_ADMIN_OBJECT_ID=$(az ad group show --group sg-financeshub-sql-admins --query id -o tsv)
export CLIENT_IP=$(curl -s https://api.ipify.org)               # opens the SQL firewall to your machine only
export ENABLE_BANKING_APPLICATION_ID=<application id from Enable Banking's control panel>
export AUTH_API_CLIENT_ID=<client id of the API's app registration>
export AUTH_OWNER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)   # the only person the API lets in
```

### 3. Preview, then deploy

```bash
az deployment group what-if --name main --resource-group rg-financeshub --parameters infra/main.bicepparam
az deployment group create  --name main --resource-group rg-financeshub --parameters infra/main.bicepparam
```

Deployments are idempotent: running `create` again only changes what differs from the template.

## Secrets

Two secrets, set once by a person with a role that can write secrets (*Key Vault Secrets Officer* on the vault).
Until both exist, no revision of the API or execution of the sync can start.

```bash
VAULT=$(az deployment group show -g rg-financeshub -n main --query properties.outputs.keyVaultName.value -o tsv)

# Enable Banking's private key, straight from the file: it never goes through the terminal or the shell history
az keyvault secret set --vault-name "$VAULT" --name enablebanking-private-key \
  --file ~/.secrets/enablebanking/<application id>.pem

# The IBANs the app may store, comma-separated (BankLinkingOptions). read -s keeps them out of the history
read -rs IBANS && az keyvault secret set --vault-name "$VAULT" --name bank-linking-allowed-ibans --value "$IBANS"; unset IBANS
```

## Enable Banking

The bank sends the browser back to the API after a login, to a URL that must be registered for the application in
Enable Banking's control panel. After the first deployment, add the output `bankCallbackUrl`:

```bash
az deployment group show -g rg-financeshub -n main --query properties.outputs.bankCallbackUrl.value -o tsv
```

The database in Azure starts empty: link the banks again through the deployed API. A fresh consent also brings back
each bank's full history.
