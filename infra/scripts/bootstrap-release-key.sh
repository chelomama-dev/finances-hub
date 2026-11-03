#!/usr/bin/env bash
# One-off setup of the key that signs the app's release builds. It creates the keystore outside the repo, writes
# mobile/android/key.properties (ignored by git) so local release builds use it, and gives it to the Release
# workflow as secrets of the 'release' environment, which only tags v* can use.
#
# The keystore can't be replaced: Android only installs an update signed with the same key. Back up the keystore and
# key.properties (the password is there) somewhere safe, like a password manager.
#
# Usage: infra/scripts/bootstrap-release-key.sh
# Needs: keytool (a JDK, or Android Studio's), openssl and gh logged in as an admin of the repo. Idempotent: it never
# overwrites an existing keystore, it only uploads it again.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
KEY_PROPERTIES="$REPO_ROOT/mobile/android/key.properties"
KEYSTORE="${KEYSTORE:-$HOME/.android/financeshub-release.jks}"
KEY_ALIAS=release
ENVIRONMENT=release

# keytool from the PATH, the JDK, or the JDK bundled with Android Studio
KEYTOOL=$(command -v keytool || true)
[[ -z "$KEYTOOL" && -n "${JAVA_HOME:-}" ]] && KEYTOOL="$JAVA_HOME/bin/keytool"
[[ -z "$KEYTOOL" ]] && KEYTOOL=$(ls /snap/android-studio/current/jbr/bin/keytool /opt/android-studio/jbr/bin/keytool \
  "$HOME"/android-studio/jbr/bin/keytool 2>/dev/null | head -1 || true)
if [[ -z "$KEYTOOL" || ! -x "$KEYTOOL" ]]; then
  echo "keytool not found: install a JDK or set JAVA_HOME (Android Studio's is in <android-studio>/jbr)" >&2
  exit 1
fi

echo "==> Keystore ($KEYSTORE)"
if [[ -f "$KEYSTORE" ]]; then
  [[ -f "$KEY_PROPERTIES" ]] || { echo "$KEYSTORE exists but $KEY_PROPERTIES doesn't: restore it" >&2; exit 1; }
  PASSWORD=$(sed -n 's/^storePassword=//p' "$KEY_PROPERTIES")
  echo "Already there, kept"
else
  # PKCS12 keystores use one password for the store and the key. Hex, so it needs no escaping anywhere
  PASSWORD=$(openssl rand -hex 32)
  mkdir -p "$(dirname "$KEYSTORE")"
  # The certificate is public (anyone can read it from the APK), so it names the app, not a person
  "$KEYTOOL" -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 -storepass "$PASSWORD" -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Finances Hub" -noprompt
  chmod 600 "$KEYSTORE"
  cat >"$KEY_PROPERTIES" <<EOF
storeFile=$KEYSTORE
storePassword=$PASSWORD
keyAlias=$KEY_ALIAS
keyPassword=$PASSWORD
EOF
  chmod 600 "$KEY_PROPERTIES"
  echo "Created. Back up $KEYSTORE and $KEY_PROPERTIES now"
fi

echo "==> GitHub environment '$ENVIRONMENT'"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
# Only tags v* may deploy to it, so a branch or a pull request never sees the key
gh api --method PUT "repos/$REPO/environments/$ENVIRONMENT" --input - >/dev/null <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
if [[ -z $(gh api "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" \
     -q '.branch_policies[] | select(.type == "tag" and .name == "v*") | .id') ]]; then
  gh api --method POST "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" \
    -f name='v*' -f type=tag >/dev/null
fi
base64 -w0 "$KEYSTORE" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$REPO" --env "$ENVIRONMENT"
printf '%s' "$PASSWORD" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO" --env "$ENVIRONMENT"

echo "Done. Run bootstrap-entra-app.sh again so Entra ID accepts the release key's signature hash"
