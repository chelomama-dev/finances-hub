#!/usr/bin/env bash
# One-off setup of the Android app's registration in the tenant: a public client that signs in through the browser
# and may ask for the API's scope. Then it writes mobile/config/azure.json (ignored by git), the --dart-define file
# that points the app at the API in Azure. Idempotent: run it again when a signing key changes.
#
# Usage: infra/scripts/bootstrap-entra-app.sh
# Needs: az logged in as an admin of the tenant (to consent to the scope), bootstrap-entra-api.sh already run, the
# API deployed, keytool (a JDK, or Android Studio's) and openssl.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONFIG_FILE="$REPO_ROOT/mobile/config/azure.json"
API_APP_NAME="Finances Hub API"
APP_NAME="Finances Hub Android"
PACKAGE_NAME=dev.chelomama.financeshub
SCOPE=access_as_user
RESOURCE_GROUP=rg-financeshub
API_CONTAINER_APP=ca-financeshub-api

# keytool from the PATH, the JDK, or the JDK bundled with Android Studio
KEYTOOL=$(command -v keytool || true)
[[ -z "$KEYTOOL" && -n "${JAVA_HOME:-}" ]] && KEYTOOL="$JAVA_HOME/bin/keytool"
[[ -z "$KEYTOOL" ]] && KEYTOOL=$(ls /snap/android-studio/current/jbr/bin/keytool /opt/android-studio/jbr/bin/keytool \
  "$HOME"/android-studio/jbr/bin/keytool 2>/dev/null | head -1 || true)
if [[ -z "$KEYTOOL" || ! -x "$KEYTOOL" ]]; then
  echo "keytool not found: install a JDK or set JAVA_HOME (Android Studio's is in <android-studio>/jbr)" >&2
  exit 1
fi

# The signature hash Android gives MSAL: base64 of the SHA-1 of the signing certificate. Public (anyone can read it
# from the APK), but each key has its own, and Entra ID only sends the login back to a registered one
signature_hash() { # keystore alias storepass
  "$KEYTOOL" -exportcert -keystore "$1" -alias "$2" -storepass "$3" | openssl sha1 -binary | openssl base64
}

echo "==> Signature hashes"
DEBUG_HASH=$(signature_hash "$HOME/.android/debug.keystore" androiddebugkey android)
# Release builds are signed with the debug key until the app has a release key of its own
RELEASE_HASH=$DEBUG_HASH
echo "debug:   $DEBUG_HASH"
echo "release: $RELEASE_HASH"

# The redirect URI carries the hash URL-encoded; the manifest and MSAL's config carry it as is
redirect_uri() { echo "msauth://$PACKAGE_NAME/$(jq -rn --arg h "$1" '$h | @uri')"; }
REDIRECT_URIS=$(printf '%s\n' "$(redirect_uri "$DEBUG_HASH")" "$(redirect_uri "$RELEASE_HASH")" | sort -u)

echo "==> The API ($API_APP_NAME)"
API_APP_ID=$(az ad app list --display-name "$API_APP_NAME" --query "[0].appId" -o tsv)
if [[ -z "$API_APP_ID" ]]; then
  echo "No app registration named '$API_APP_NAME': run bootstrap-entra-api.sh first" >&2
  exit 1
fi
SCOPE_ID=$(az ad app show --id "$API_APP_ID" --query "api.oauth2PermissionScopes[?value=='$SCOPE'].id | [0]" -o tsv)

echo "==> App registration ($APP_NAME)"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [[ -z "$APP_ID" ]]; then
  # Single tenant, like the API. A public client: a phone can't keep a secret, so it has none
  APP_ID=$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg \
    --is-fallback-public-client true --query appId -o tsv)
fi
# shellcheck disable=SC2086 # one argument per redirect URI
az ad app update --id "$APP_ID" --is-fallback-public-client true --public-client-redirect-uris $REDIRECT_URIS

# The delegated scope it asks for, consented once for the tenant so the login never shows a consent screen
if [[ -z $(az ad app permission list --id "$APP_ID" \
     --query "[?resourceAppId=='$API_APP_ID'].resourceAccess[] | [?id=='$SCOPE_ID'].id | [0]" -o tsv) ]]; then
  az ad app permission add --id "$APP_ID" --api "$API_APP_ID" --api-permissions "$SCOPE_ID=Scope" --only-show-errors
fi
az ad sp show --id "$APP_ID" --query id -o tsv >/dev/null 2>&1 || az ad sp create --id "$APP_ID" --output none
API_SP_ID=$(az ad sp show --id "$API_APP_ID" --query id -o tsv)
if [[ -z $(az ad app permission list-grants --id "$APP_ID" \
     --query "[?resourceId=='$API_SP_ID' && consentType=='AllPrincipals'].id | [0]" -o tsv) ]]; then
  az ad app permission grant --id "$APP_ID" --api "$API_APP_ID" --scope "$SCOPE" --output none
fi

echo "==> $CONFIG_FILE"
TENANT_ID=$(az account show --query tenantId -o tsv)
API_FQDN=$(az containerapp show --resource-group "$RESOURCE_GROUP" --name "$API_CONTAINER_APP" \
  --query properties.configuration.ingress.fqdn -o tsv)
mkdir -p "$(dirname "$CONFIG_FILE")"
jq -n \
  --arg url "https://$API_FQDN" \
  --arg tenant "$TENANT_ID" \
  --arg client "$APP_ID" \
  --arg scope "api://$API_APP_ID/$SCOPE" \
  --arg debug "$DEBUG_HASH" \
  --arg release "$RELEASE_HASH" \
  '{
    API_BASE_URL: $url,
    AUTH_TENANT_ID: $tenant,
    AUTH_CLIENT_ID: $client,
    AUTH_API_SCOPE: $scope,
    AUTH_DEBUG_SIGNATURE_HASH: $debug,
    AUTH_RELEASE_SIGNATURE_HASH: $release
  }' >"$CONFIG_FILE"

echo "Done. From mobile/: flutter run --dart-define-from-file=config/azure.json"
