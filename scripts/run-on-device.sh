#!/usr/bin/env bash
#
# Build, install, and launch PackingHelper on a physical iPhone —
# the command-line equivalent of pressing Run in Xcode.
#
# Usage:
#   scripts/run-on-device.sh                 # first connected/paired iPhone
#   scripts/run-on-device.sh "Todd's iPhone" # by name, UDID, or devicectl identifier
#   CONFIGURATION=Release scripts/run-on-device.sh
#   CONSOLE=1 scripts/run-on-device.sh       # stream app stdout/stderr after launch
#
# Works over Wi-Fi if the phone has been paired with "Connect via network"
# in Xcode's Devices window, so the Mac can be headless (e.g. over SSH).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/PackingHelper.xcodeproj"
SCHEME="PackingHelper"
BUNDLE_ID="com.toddlouison.PackingHelper"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT/build/device"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"
DEVICE_QUERY="${1:-${DEVICE:-}}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Codesigning over SSH fails with errSecInternalComponent unless the login
# keychain is unlocked for this session.
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  log "SSH session detected — unlocking login keychain for codesigning"
  security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"
fi

# --- Resolve device -----------------------------------------------------------
log "Looking for device${DEVICE_QUERY:+ matching \"$DEVICE_QUERY\"}"
DEVICES_JSON="$(mktemp)"
trap 'rm -f "$DEVICES_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null

DEVICE_LINE="$(jq -r --arg q "$DEVICE_QUERY" '
  .result.devices[]
  | select(.hardwareProperties.platform == "iOS")
  | select(.hardwareProperties.reality == "physical")
  | select($q == ""
      or .deviceProperties.name == $q
      or .hardwareProperties.udid == $q
      or .identifier == $q)
  | [ .hardwareProperties.udid,
      .deviceProperties.name,
      (.connectionProperties.tunnelState // "unknown") ]
  | @tsv
' "$DEVICES_JSON" | sort -t$'\t' -k3,3 | head -n1)"  # "connected" sorts before "disconnected"/"unavailable"

[[ -n "$DEVICE_LINE" ]] || die "No matching iOS device found. Run 'xcrun devicectl list devices' to see what's available."
IFS=$'\t' read -r UDID DEVICE_NAME TUNNEL_STATE <<<"$DEVICE_LINE"
log "Using $DEVICE_NAME ($UDID, tunnel: $TUNNEL_STATE)"

# --- Build --------------------------------------------------------------------
log "Building $SCHEME ($CONFIGURATION)"
BUILD_CMD=(
  xcodebuild
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "id=$UDID"
  -derivedDataPath "$DERIVED_DATA"
  -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration
  build
)
if command -v xcbeautify >/dev/null; then
  "${BUILD_CMD[@]}" | xcbeautify
else
  "${BUILD_CMD[@]}" -quiet
fi

[[ -d "$APP_PATH" ]] || die "Build succeeded but app not found at $APP_PATH"

# --- Install & launch ---------------------------------------------------------
log "Installing on $DEVICE_NAME"
xcrun devicectl device install app --device "$UDID" "$APP_PATH"

log "Launching $BUNDLE_ID"
LAUNCH_CMD=(xcrun devicectl device process launch --device "$UDID" --terminate-existing)
if [[ "${CONSOLE:-0}" == "1" ]]; then
  LAUNCH_CMD+=(--console)
fi
"${LAUNCH_CMD[@]}" "$BUNDLE_ID"

log "Done"
