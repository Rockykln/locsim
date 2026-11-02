#!/bin/sh
# Takes the App Store screenshots in the iOS Simulator with the demo mode (macOS, Xcode).
# Usage: tools/screenshots.sh   (DEVICE="iPhone 17" by default)
# Output: design/screenshots/<lang>/<theme>/<name>.png, then run design/mockups/render.py.
set -eu

DEVICE=${DEVICE:-"iPhone 17"}
BUNDLE=com.rockykln.locsim
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/design/screenshots"
BUILD="$ROOT/build/screenshots"

cd "$ROOT"
[ -d LocSim.xcodeproj ] || { echo "Run xcodegen generate first."; exit 1; }

UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "No simulator named \"$DEVICE\". Add one in Xcode > Window > Devices and Simulators."; exit 1; }

echo "Building for $DEVICE"
xcodebuild -project LocSim.xcodeproj -scheme LocSim -configuration Debug \
    -destination "id=$UDID" -derivedDataPath "$BUILD" \
    CODE_SIGNING_ALLOWED=NO build -quiet
APP="$BUILD/Build/Products/Debug-iphonesimulator/LocSim.app"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time 9:41 \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100
trap 'xcrun simctl status_bar "$UDID" clear; xcrun simctl ui "$UDID" appearance light' EXIT

# screen:file:seconds to wait for map tiles and search results
SHOTS="map:1-map:8 search:2-search:8 favorites:3-favorites:5"

for lang in en de; do
    case $lang in
        de) locale=de_DE ;;
        *) locale=en_US ;;
    esac
    for theme in light dark; do
        xcrun simctl ui "$UDID" appearance "$theme"
        mkdir -p "$OUT/$lang/$theme"
        for shot in $SHOTS; do
            screen=${shot%%:*}
            rest=${shot#*:}
            name=${rest%%:*}
            wait=${rest#*:}
            xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
                -demo "$screen" -AppleLanguages "($lang)" -AppleLocale "$locale" >/dev/null ||
                { echo "Launch failed at $lang/$theme/$name" >&2; exit 1; }
            sleep "$wait"
            # simctl may not replace a file another process wrote (e.g. git); it can create a new one.
            rm -f "$OUT/$lang/$theme/$name.png"
            # simctl sometimes fails while an animation runs; try again before giving up.
            tries=0
            until xcrun simctl io "$UDID" screenshot --type=png "$OUT/$lang/$theme/$name.png" >/dev/null; do
                tries=$((tries + 1))
                [ "$tries" -lt 3 ] || { echo "Screenshot failed at $lang/$theme/$name" >&2; exit 1; }
                sleep 2
            done
            echo "$lang/$theme/$name.png"
        done
    done
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
