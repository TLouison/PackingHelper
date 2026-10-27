#!/usr/bin/env bash
#
# Build, install, and launch PackingHelper in an iOS Simulator.
#
# On a Mac it builds locally. Anywhere else (e.g. a Linux dev server) it
# rsyncs the working tree, including the gitignored Config.xcconfig, to a Mac
# over SSH and runs itself there, so the app shows up in that Mac's Simulator
# (and in T3 Code's Device panel when the Mac is a device host).
#
# Usage:
#   scripts/run-on-simulator.sh                # pick from a list; Enter or 5s takes the most recent
#   scripts/run-on-simulator.sh "iPhone 17"    # by name or UDID
#   MAC_HOST=user@my-mac scripts/run-on-simulator.sh # SSH destination when not on a Mac (default: ios-mac, an alias in ~/.ssh/config)
#   CONFIGURATION=Release scripts/run-on-simulator.sh
#   CONSOLE=1 scripts/run-on-simulator.sh      # stream app stdout/stderr after launch

# If sourced, re-run in a child bash instead so a failure's `exit` and
# `set -euo pipefail` don't kill the caller's shell.
if (return 0 2>/dev/null); then
  if [ -n "${BASH_SOURCE:-}" ]; then __ros_self="${BASH_SOURCE[0]}"; else __ros_self="$0"; fi
  bash "$__ros_self" "$@"
  __ros_status=$?
  unset __ros_self
  return "$__ros_status"
fi

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Not on a Mac: sync to one and run there ------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  MAC_HOST="${MAC_HOST:-ios-mac}"
  REMOTE_DIR="${REMOTE_DIR:-PackingHelperiOS}"  # relative to the Mac user's home

  log "Syncing to $MAC_HOST:$REMOTE_DIR"
  rsync -az --delete \
    --exclude .git/ --exclude build/ --exclude DerivedData/ --exclude .claude/ \
    "$ROOT/" "$MAC_HOST:$REMOTE_DIR/"

  args=""
  for arg in "$@"; do args+=" $(printf '%q' "$arg")"; done
  exec ssh -t "$MAC_HOST" \
    "cd $(printf '%q' "$REMOTE_DIR") && CONFIGURATION=$(printf '%q' "${CONFIGURATION:-Debug}") CONSOLE=$(printf '%q' "${CONSOLE:-0}") bash scripts/run-on-simulator.sh$args"
fi

# --- On the Mac ---------------------------------------------------------------
# Non-interactive SSH sessions skip the shell profile, so Homebrew tools
# (jq, xcbeautify) aren't on PATH by default.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT="$ROOT/PackingHelper.xcodeproj"
SCHEME="PackingHelper"
BUNDLE_ID="com.toddlouison.PackingHelper"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT/build/simulator"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/$SCHEME.app"
SIM_QUERY="${1:-${SIMULATOR:-}}"

[[ -f "$ROOT/Config.xcconfig" ]] || die "Config.xcconfig is missing. Copy Config.xcconfig.example and fill it in."

# --- Resolve simulator ----------------------------------------------------------
# Most recently opened first: booted, then by lastUsedAt, then iPhones on the
# newest runtime. Runtimes below the deployment target (iOS 26) are skipped.
SIMS="$(xcrun simctl list devices available --json | jq -r --arg q "$SIM_QUERY" '
  [ .devices
    | to_entries[]
    | select(.key | test("\\.iOS-[0-9]"))
    | (.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber)) as $ver
    | select($ver[0] >= 26)
    | .value[]
    | select($q == "" or .name == $q or .udid == $q)
    | { udid, name, state, ver: $ver,
        used: (.lastUsedAt // ""),
        phone: (.name | startswith("iPhone")) } ]
  | to_entries
  | map(.value + { idx: .key })
  | sort_by([.used, .phone, .ver, -.idx])
  | reverse
  | sort_by(.state != "Booted")
  | .[]
  | [ .udid, .name, .state, "iOS \(.ver | map(tostring) | join("."))" ]
  | @tsv
')"

[[ -n "$SIMS" ]] || die "No matching simulator found${SIM_QUERY:+ for \"$SIM_QUERY\"}. Run 'xcrun simctl list devices available' to see what's installed."

# Bash 3.2 (macOS /bin/bash) has no mapfile. Only the 5 most recent are offered.
SIM_LINES=()
while IFS= read -r line; do SIM_LINES+=("$line"); done <<<"$(head -n 5 <<<"$SIMS")"
LAST=$((${#SIM_LINES[@]} - 1))

CHOICE=0
# Ask only when no simulator was named and someone is at the terminal; Enter or
# a 5-second timeout takes the most recent one.
if [[ -z "$SIM_QUERY" && -t 0 && $LAST -gt 0 ]]; then
  printf '\nSimulators (most recent first):\n'
  for i in "${!SIM_LINES[@]}"; do
    IFS=$'\t' read -r _ name state runtime <<<"${SIM_LINES[$i]}"
    printf '  %d) %s (%s)%s\n' "$i" "$name" "$runtime" "$([[ "$state" == "Booted" ]] && echo ', booted')"
  done
  timeout=5
  while true; do
    reply=""
    if [[ -n "$timeout" ]]; then
      read -r -t "$timeout" -p "Simulator [0, default in ${timeout}s]: " reply || echo
    else
      read -r -p "Simulator [0]: " reply || echo
    fi
    [[ -z "$reply" ]] && break
    if [[ "$reply" =~ ^[0-9]$ ]] && (( reply <= LAST )); then
      CHOICE="$reply"
      break
    fi
    echo "Enter a number from 0 to $LAST."
    timeout=""  # they're typing, so stop the countdown
  done
fi

IFS=$'\t' read -r UDID SIM_NAME SIM_STATE SIM_RUNTIME <<<"${SIM_LINES[$CHOICE]}"
log "Using $SIM_NAME ($SIM_RUNTIME, $UDID, $SIM_STATE)"

if [[ "$SIM_STATE" != "Booted" ]]; then
  log "Booting $SIM_NAME"
  xcrun simctl boot "$UDID"
fi

# --- Build --------------------------------------------------------------------
log "Building $SCHEME ($CONFIGURATION)"
BUILD_CMD=(
  xcodebuild
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "id=$UDID"
  -derivedDataPath "$DERIVED_DATA"
  build
)
if command -v xcbeautify >/dev/null; then
  "${BUILD_CMD[@]}" | xcbeautify
else
  "${BUILD_CMD[@]}" -quiet
fi

[[ -d "$APP_PATH" ]] || die "Build succeeded but app not found at $APP_PATH"

# --- Install & launch ---------------------------------------------------------
log "Installing on $SIM_NAME"
xcrun simctl install "$UDID" "$APP_PATH"

log "Launching $BUNDLE_ID"
LAUNCH_CMD=(xcrun simctl launch --terminate-running-process)
if [[ "${CONSOLE:-0}" == "1" ]]; then
  LAUNCH_CMD+=(--console-pty)
fi
"${LAUNCH_CMD[@]}" "$UDID" "$BUNDLE_ID"

log "Done"
