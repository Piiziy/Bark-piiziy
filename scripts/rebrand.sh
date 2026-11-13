#!/usr/bin/env bash
# Re-points the iOS project at your own identifiers.
#
#   scripts/rebrand.sh --bundle-id com.you.homepush --team ABCDE12345 \
#                      --server https://push.you.com --name HomePush
#
# Any flag may be omitted to keep its current value. Current values live in
# scripts/rebrand.current (committed) so the script can be re-run any time.
set -euo pipefail
cd "$(dirname "$0")/.."

STATE=scripts/rebrand.current
# shellcheck disable=SC1090
source "$STATE"

NEW_BUNDLE_ID=$BUNDLE_ID NEW_TEAM=$TEAM_ID NEW_SERVER=$SERVER NEW_NAME=$DISPLAY_NAME NEW_GROUP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id) NEW_BUNDLE_ID=$2; shift 2 ;;
    --team)      NEW_TEAM=$2; shift 2 ;;
    --server)    NEW_SERVER=${2%/}; shift 2 ;;
    --name)      NEW_NAME=$2; shift 2 ;;
    --app-group) NEW_GROUP=$2; shift 2 ;;
    -h|--help)   sed -n 2,9p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
[[ -z $NEW_GROUP ]] && NEW_GROUP="group.$NEW_BUNDLE_ID"

PBX=Bark.xcodeproj/project.pbxproj
export OLD_B="$BUNDLE_ID" NEW_B="$NEW_BUNDLE_ID" OLD_G="$APP_GROUP" NEW_G="$NEW_GROUP" \
       OLD_S="$SERVER" NEW_S="$NEW_SERVER" NEW_T="$NEW_TEAM" OLD_N="$DISPLAY_NAME" NEW_N="$NEW_NAME"

# Bundle IDs (app, extensions, widget, watch) + watch companion ID
perl -pi -e 's/(PRODUCT_BUNDLE_IDENTIFIER = |WKCompanionAppBundleIdentifier = )\Q$ENV{OLD_B}\E(?=[.;])/$1$ENV{NEW_B}/g' "$PBX"
perl -pi -e 's/\Q$ENV{OLD_B}\E(?=[."])/$ENV{NEW_B}/g' fastlane/Appfile fastlane/Matchfile
perl -pi -e 's/(<string>)\Q$ENV{OLD_B}\E(<\/string>)/$1$ENV{NEW_B}$2/' Bark/Info.plist

# Signing team (empty string = pick it in Xcode > Signing & Capabilities)
TEAM_VALUE=${NEW_TEAM:-'""'}
export TEAM_VALUE
perl -pi -e 's/(DEVELOPMENT_TEAM(?:\[sdk=[a-z]+\*\])?"? = )[^;]*;/$1$ENV{TEAM_VALUE};/g' "$PBX"
perl -pi -e 's/team_id\("[^"]*"\)/team_id("$ENV{NEW_T}")/' fastlane/Appfile

# App Group (entitlements + every containerURL/UserDefaults(suiteName:) call)
grep -rlF "$APP_GROUP" --include=*.swift --include=*.entitlements . | grep -v '^./Pods/' | while read -r f; do
  perl -pi -e 's/([">])\Q$ENV{OLD_G}\E(["<])/$1$ENV{NEW_G}$2/g' "$f"
done

# Default server
perl -pi -e 's/^let defaultServer = "\Q$ENV{OLD_S}\E"/let defaultServer = "$ENV{NEW_S}"/' Common/ServerManager.swift

# Home-screen name of the iOS app
perl -pi -e 's/(INFOPLIST_KEY_CFBundleDisplayName = )"?\Q$ENV{OLD_N}\E"?;/$1"$ENV{NEW_N}";/' "$PBX"

cat > "$STATE" <<STATE_EOF
# Written by scripts/rebrand.sh - the identifiers the project currently uses.
BUNDLE_ID="$NEW_BUNDLE_ID"
APP_GROUP="$NEW_GROUP"
TEAM_ID="$NEW_TEAM"
SERVER="$NEW_SERVER"
DISPLAY_NAME="$NEW_NAME"
STATE_EOF

echo "bundle id : $NEW_BUNDLE_ID (+ .NotificationServiceExtension, .NotificationContent, .Widget, .watch, ...)"
echo "app group : $NEW_GROUP"
echo "team      : ${NEW_TEAM:-<set in Xcode>}"
echo "server    : $NEW_SERVER"
echo "name      : $NEW_NAME"
echo "Remember: BARK_APNS_TOPIC on the server must equal the bundle id."
