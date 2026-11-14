#!/usr/bin/env bash
# Deploy bark-server to Google Cloud Run in serverless mode (one device, no DB).
# Usage: server/cloudrun/deploy.sh
#   Locally it reads server/cloudrun/.env. In GitHub Actions the same values
#   come from the environment (APNS_KEY holds the .p8 contents) and
#   SKIP_SETUP=1 skips the one-time API/IAM steps.
# Secrets (APNs key, push key, device token) live in Secret Manager and are
# never printed by this script.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$(dirname "$HERE")"
if [ -f "$HERE/.env" ]; then
  # shellcheck disable=SC1091
  source "$HERE/.env"
fi

: "${GCP_PROJECT:?set GCP_PROJECT in .env}"
: "${APNS_KEY_ID:?set APNS_KEY_ID in .env}"
: "${APNS_TEAM_ID:?set APNS_TEAM_ID in .env}"
: "${APNS_TOPIC:?set APNS_TOPIC in .env}"
REGION=${REGION:-asia-northeast3}
SERVICE=${SERVICE:-homepush}
APNS_SANDBOX=${APNS_SANDBOX:-true}
APNS_KEY_FILE=${APNS_KEY_FILE:-}
APNS_KEY_FILE=${APNS_KEY_FILE/#\~/$HOME}
SKIP_SETUP=${SKIP_SETUP:-0}

g() { gcloud --project "$GCP_PROJECT" --quiet "$@"; }

# Create the secret if needed and add a version from stdin when the value changed.
put_secret() { # name value
  local name=$1 value=$2 current
  if ! g secrets describe "$name" >/dev/null 2>&1; then
    g secrets create "$name" --replication-policy=automatic >/dev/null
  fi
  current=$(g secrets versions access latest --secret "$name" 2>/dev/null || true)
  if [ "$current" != "$value" ]; then
    printf '%s' "$value" | g secrets versions add "$name" --data-file=- >/dev/null
    echo "  secret $name: updated"
  else
    echo "  secret $name: unchanged"
  fi
}

if [ "$SKIP_SETUP" != 1 ]; then
  echo "==> Enabling APIs"
  g services enable run.googleapis.com cloudbuild.googleapis.com \
    artifactregistry.googleapis.com secretmanager.googleapis.com
fi

echo "==> Secrets"
if [ -z "${APNS_KEY:-}" ]; then
  [ -f "$APNS_KEY_FILE" ] || { echo "Set APNS_KEY or APNS_KEY_FILE (not found: $APNS_KEY_FILE)"; exit 1; }
  APNS_KEY=$(cat "$APNS_KEY_FILE")
fi
put_secret apns-key "$APNS_KEY"

# Push key: generated once, kept in Secret Manager.
if ! BARK_KEY=$(g secrets versions access latest --secret bark-key 2>/dev/null); then
  BARK_KEY=$(openssl rand -hex 11)
fi
put_secret bark-key "$BARK_KEY"
put_secret bark-device-token "${DEVICE_TOKEN:-pending}"

if [ "$SKIP_SETUP" != 1 ]; then
  echo "==> Service account permissions"
  PROJECT_NUMBER=$(g projects describe "$GCP_PROJECT" --format='value(projectNumber)')
  SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
  for role in roles/secretmanager.secretAccessor roles/run.builder; do
    g projects add-iam-policy-binding "$GCP_PROJECT" \
      --member "serviceAccount:$SA" --role "$role" --condition=None >/dev/null
  done
fi

echo "==> Deploying $SERVICE to $REGION (Cloud Build, takes a few minutes)"
g run deploy "$SERVICE" \
  --source "$SERVER_DIR" \
  --region "$REGION" \
  --allow-unauthenticated \
  --min-instances 0 --max-instances 1 \
  --memory 256Mi --cpu 1 \
  --set-env-vars "BARK_APNS_KEY_ID=$APNS_KEY_ID,BARK_APNS_TEAM_ID=$APNS_TEAM_ID,BARK_APNS_TOPIC=$APNS_TOPIC,BARK_APNS_SANDBOX=$APNS_SANDBOX" \
  --set-secrets "BARK_APNS_KEY=apns-key:latest,BARK_KEY=bark-key:latest,BARK_DEVICE_TOKEN=bark-device-token:latest"

URL=$(g run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')
echo
echo "Server URL: $URL"
echo "Health:     $(curl -fsS "$URL/ping" || echo 'ping failed')"
if [ "${DEVICE_TOKEN:-}" = "" ]; then
  echo "Next: copy the device token from the app (Settings > Device Token) into DEVICE_TOKEN"
  echo "      (.env locally, or the DEVICE_TOKEN repository secret for GitHub Actions) and deploy again."
fi
echo "Show your push key (do not share it):"
echo "  gcloud secrets versions access latest --secret bark-key --project $GCP_PROJECT"
