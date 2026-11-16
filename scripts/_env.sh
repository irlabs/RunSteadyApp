# Shared settings for the device scripts. Override any of these in your shell or in
# scripts/local.env (gitignored), e.g. PHONE_ID=... WATCH_ID=...
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/scripts/local.env" ] && . "$ROOT/scripts/local.env"

PHONE_ID="${PHONE_ID:-FAF9C334-6075-4E91-A1A6-62EB85744B55}"
WATCH_ID="${WATCH_ID:-74659849-1754-483A-BCFE-98E921357CE0}"
BUNDLE_ID="com.runsteady.app"
DERIVED="$ROOT/build/device"
PHONE_APP="$DERIVED/Build/Products/Debug-iphoneos/RunSteady.app"
WATCH_APP="$PHONE_APP/Watch/RunSteadyWatch.app"

version_of() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Info.plist" 2>/dev/null; }
build_of()   { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Info.plist" 2>/dev/null; }
