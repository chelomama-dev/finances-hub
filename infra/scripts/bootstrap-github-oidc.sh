#!/usr/bin/env bash
# One-off setup so GitHub Actions can deploy Finances Hub to Azure without any stored secret (OIDC workload identity
# federation). Idempotent: run it again after deleting rg-financeshub, because that also deletes the role assignments.
#
# Usage: infra/scripts/bootstrap-github-oidc.sh
# Needs: az logged in as a subscription Owner (to assign roles) who can create Entra groups, and gh logged in as a
# repo admin (to create the environment and its variables).
set -euo pipefail

# Asked to GitHub, not hardcoded: renaming the account changes it, and with it the OIDC subject Azure trusts
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
ENVIRONMENT=production
LOCATION=francecentral
APP_RG=rg-financeshub                  # what the pipeline deploys into (deleted and recreated freely)
CICD_RG=rg-financeshub-cicd            # the pipeline's own identity: lives apart so deleting rg-financeshub keeps it
DEPLOY_IDENTITY=id-financeshub-github
SQL_ADMIN_GROUP=sg-financeshub-sql-admins  # the pipeline only: people join it just for the task that needs it
READERS_GROUP=sg-financeshub-readers       # people, day to day: read the data in SQL

# A subscription must register a resource provider before it can create that kind of resource. That is a
# subscription-wide action the pipeline can't do (it only has rights on rg-financeshub), so do it here, once.
# Keep this list in step with the resource types in infra/
PROVIDERS=(Microsoft.App Microsoft.Insights Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights
  Microsoft.Sql)
echo "==> Resource providers"
for provider in "${PROVIDERS[@]}"; do
  if [[ $(az provider show --namespace "$provider" --query registrationState -o tsv) != Registered ]]; then
    echo "    registering $provider (can take a few minutes)"
    az provider register --namespace "$provider" --wait --output none
  fi
done

echo "==> Resource groups"
az group create --name "$APP_RG" --location "$LOCATION" --tags app=financeshub --output none
az group create --name "$CICD_RG" --location "$LOCATION" --tags app=financeshub purpose=cicd --output none

echo "==> Deployment identity ($DEPLOY_IDENTITY)"
az identity create --name "$DEPLOY_IDENTITY" --resource-group "$CICD_RG" --location "$LOCATION" --output none
CLIENT_ID=$(az identity show -n "$DEPLOY_IDENTITY" -g "$CICD_RG" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -n "$DEPLOY_IDENTITY" -g "$CICD_RG" --query principalId -o tsv)

# Trust GitHub's tokens, but only for jobs that run in the 'production' environment of this repo. The environment
# only accepts deployments from main, so a PR branch can never get an Azure token. The subject prefix is asked to
# GitHub, not guessed: it may use the immutable format repo:owner@ownerId/repo@repoId
SUBJECT="$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq .sub_claim_prefix):environment:$ENVIRONMENT"
echo "==> Federated credential ($SUBJECT)"
az identity federated-credential create \
  --name github-$ENVIRONMENT \
  --identity-name "$DEPLOY_IDENTITY" \
  --resource-group "$CICD_RG" \
  --issuer https://token.actions.githubusercontent.com \
  --subject "$SUBJECT" \
  --audiences api://AzureADTokenExchange \
  --output none

APP_RG_ID=$(az group show -n "$APP_RG" --query id -o tsv)

# Contributor on the app resource group only: it can create and change resources there, but not grant permissions
# or touch anything else in the subscription
echo "==> Contributor on $APP_RG"
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope "$APP_RG_ID" \
  --output none

# Bicep gives the apps' managed identities the roles they need (role assignments), which Contributor can't do.
# Role Based Access Control Administrator can, and the condition narrows it to these roles, for service principals
# only: without it the pipeline could make itself Owner. Add a role's GUID when the infra needs another one, and
# run this script again
MONITORING_METRICS_PUBLISHER=3913510d-42f4-4e42-8a64-420c390055eb  # sends telemetry to Application Insights
KEY_VAULT_SECRETS_USER=4633458b-17de-408a-b874-0445c86b69e6        # reads secret values
DATA_ROLES="$MONITORING_METRICS_PUBLISHER, $KEY_VAULT_SECRETS_USER"
RBAC_CONDITION="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR \
(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$DATA_ROLES} \
AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'})) \
AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR \
(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$DATA_ROLES}))"
echo "==> Role Based Access Control Administrator on $APP_RG (only for the apps' roles)"
# One assignment per principal, role and scope: an existing one (maybe with an older condition) is replaced
EXISTING=$(az role assignment list --assignee "$PRINCIPAL_ID" --role "Role Based Access Control Administrator" \
  --scope "$APP_RG_ID" --query "[].id" -o tsv)
if [[ -n "$EXISTING" ]]; then
  az role assignment delete --ids $EXISTING --output none
fi
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" \
  --scope "$APP_RG_ID" \
  --condition "$RBAC_CONDITION" \
  --condition-version 2.0 \
  --output none

# Prints the group's object ID, creating the group first if needed (the ID comes from the create itself: a
# just-created group may not be visible to a lookup yet)
ensure_group() {
  az ad group show --group "$1" --query id -o tsv 2>/dev/null ||
    az ad group create --display-name "$1" --mail-nickname "$1" --query id -o tsv
}

# A just-created managed identity or group takes a while to replicate in Entra ID, so retry instead of failing on
# the first run. Usage: add_member <group id> <member object id>
add_member() {
  for attempt in {1..12}; do
    if [[ $(az ad group member check --group "$1" --member-id "$2" --query value -o tsv 2>/dev/null) == "true" ]] ||
       az ad group member add --group "$1" --member-id "$2" 2>/dev/null; then
      return 0
    fi
    echo "    $2 not visible in Entra ID yet, retrying in 10 s ($attempt/12)"
    sleep 10
  done
  echo "    $2 could not be added to group $1" >&2
  return 1
}

ME=$(az ad signed-in-user show --query id -o tsv)

# A SQL server has a single Entra admin, so it is a group. Only the pipeline is a permanent member: it applies the
# migrations and creates the database users. You join it only for a task that needs it (infra/README.md)
echo "==> SQL admin group ($SQL_ADMIN_GROUP)"
GROUP_ID=$(ensure_group "$SQL_ADMIN_GROUP")
add_member "$GROUP_ID" "$PRINCIPAL_ID"
if [[ $(az ad group member check --group "$GROUP_ID" --member-id "$ME" --query value -o tsv) == "true" ]]; then
  echo "    WARNING: you are a SQL admin. Leave the group when you are done:"
  echo "    az ad group member remove --group $SQL_ADMIN_GROUP --member-id $ME"
fi

# Day-to-day access for people: the pipeline makes the group db_datareader in the database (grant-sql-access.cs)
echo "==> Readers group ($READERS_GROUP)"
READERS_ID=$(ensure_group "$READERS_GROUP")
add_member "$READERS_ID" "$ME"

echo "==> GitHub environment '$ENVIRONMENT' (deployments from main only)"
gh api --method PUT "repos/$REPO/environments/$ENVIRONMENT" \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true' \
  --silent
if ! gh api "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" \
     --jq '.branch_policies[].name' | grep -qx main; then
  gh api --method POST "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" \
    -f name=main -f type=branch --silent
fi

# Variables, not secrets: identifiers, useless without a token that only GitHub can issue
echo "==> Environment variables"
gh variable set AZURE_CLIENT_ID       --env "$ENVIRONMENT" --repo "$REPO" --body "$CLIENT_ID"
gh variable set AZURE_TENANT_ID       --env "$ENVIRONMENT" --repo "$REPO" --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --env "$ENVIRONMENT" --repo "$REPO" --body "$(az account show --query id -o tsv)"
gh variable set SQL_ADMIN_GROUP_NAME  --env "$ENVIRONMENT" --repo "$REPO" --body "$SQL_ADMIN_GROUP"
gh variable set SQL_ADMIN_GROUP_ID    --env "$ENVIRONMENT" --repo "$REPO" --body "$GROUP_ID"
gh variable set SQL_READER_GROUP_NAME --env "$ENVIRONMENT" --repo "$REPO" --body "$READERS_GROUP"
gh variable set SQL_READER_GROUP_ID   --env "$ENVIRONMENT" --repo "$REPO" --body "$READERS_ID"

echo "Done. Deploy identity client ID: $CLIENT_ID"
