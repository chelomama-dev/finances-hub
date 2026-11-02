#!/usr/bin/env bash
# One-off setup of the API's app registration in the tenant: the audience and scope of the tokens the API accepts,
# and who may get them (only you). Idempotent.
#
# Usage: infra/scripts/bootstrap-entra-api.sh <Enable Banking application ID>
# Needs: az logged in as someone who can create app registrations in the tenant, and gh logged in as a repo admin.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <Enable Banking application ID>" >&2
  exit 1
fi
ENABLE_BANKING_APPLICATION_ID=$1

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
ENVIRONMENT=production
API_APP_NAME="Finances Hub API"
SCOPE=access_as_user

echo "==> App registration ($API_APP_NAME)"
APP_ID=$(az ad app list --display-name "$API_APP_NAME" --query "[0].appId" -o tsv)
if [[ -z "$APP_ID" ]]; then
  # Single tenant: only accounts of this directory can even ask for a token
  APP_ID=$(az ad app create --display-name "$API_APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)
fi
APP_OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

# v2 access tokens (issuer login.microsoftonline.com/{tenant}/v2.0, aud = the client ID), which is what the API
# validates, and the delegated scope the Android app asks for. The scope's ID is kept if it already exists
SCOPE_ID=$(az ad app show --id "$APP_ID" --query "api.oauth2PermissionScopes[?value=='$SCOPE'].id | [0]" -o tsv)
SCOPE_ID=${SCOPE_ID:-$(cat /proc/sys/kernel/random/uuid)}
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
  --headers Content-Type=application/json \
  --body "$(cat <<JSON
{
  "identifierUris": ["api://$APP_ID"],
  "api": {
    "requestedAccessTokenVersion": 2,
    "oauth2PermissionScopes": [{
      "id": "$SCOPE_ID",
      "value": "$SCOPE",
      "type": "User",
      "isEnabled": true,
      "adminConsentDisplayName": "Read your finances",
      "adminConsentDescription": "Lets the Finances Hub app read your balances and transactions.",
      "userConsentDisplayName": "Read your finances",
      "userConsentDescription": "Lets the Finances Hub app read your balances and transactions."
    }]
  }
}
JSON
)"

# Assignment required: Entra ID issues tokens for the API only to users assigned to it. With only you assigned,
# nobody else in the tenant can get a token at all; the API's own owner check is the second lock
echo "==> Enterprise application (assignment required, only you)"
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || az ad sp create --id "$APP_ID" --query id -o tsv)
az ad sp update --id "$SP_ID" --set appRoleAssignmentRequired=true
ME=$(az ad signed-in-user show --query id -o tsv)
if [[ -z $(az rest --method GET \
     --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_ID/appRoleAssignedTo" \
     --query "value[?principalId=='$ME'].id | [0]" -o tsv) ]]; then
  # The default access role (all zeros): the app defines no roles of its own
  az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_ID/appRoleAssignedTo" \
    --headers Content-Type=application/json \
    --body "{\"principalId\": \"$ME\", \"resourceId\": \"$SP_ID\", \"appRoleId\": \"00000000-0000-0000-0000-000000000000\"}" \
    --output none
fi

# Identifiers, not secrets. They stay out of the public repo anyway (the owner's object ID identifies you)
echo "==> Environment variables"
gh variable set AUTH_API_CLIENT_ID            --env "$ENVIRONMENT" --repo "$REPO" --body "$APP_ID"
gh variable set AUTH_OWNER_OBJECT_ID          --env "$ENVIRONMENT" --repo "$REPO" --body "$ME"
gh variable set ENABLE_BANKING_APPLICATION_ID --env "$ENVIRONMENT" --repo "$REPO" --body "$ENABLE_BANKING_APPLICATION_ID"

echo "Done. API client ID: $APP_ID (scope api://$APP_ID/$SCOPE)"
