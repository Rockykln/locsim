#!/bin/sh
# Takes the App Store screenshots in the iOS Simulator with the demo mode (macOS, Xcode).
# Usage: tools/screenshots.sh [lang ...]   (all languages by default; DEVICE="iPhone 17")
#        SCREENS="live favorites" tools/screenshots.sh it   retakes only those screens.
# Output: design/screenshots/<lang>/<theme>/<name>.png, then run design/mockups/render.py.
#
# The Lock Screen with the Live Activity needs the Simulator locked; simctl cannot do that,
# so the script waits until you have locked it.
set -eu

DEVICE=${DEVICE:-"iPhone 17"}
BUNDLE=com.rockykln.locsim
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null && pwd)
OUT="$ROOT/design/screenshots"
BUILD="$ROOT/build/screenshots"
LANGS=${*:-"en de fr es it"}
SCREENS=${SCREENS:-"map search recents live favorites"}
wants() { case " $SCREENS " in *" $1 "*) return 0 ;; esac; return 1; }

cd "$ROOT"
[ -d LocSim.xcodeproj ] || { echo "Run xcodegen generate first."; exit 1; }

UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "No simulator named \"$DEVICE\". Add one in Xcode > Window > Devices and Simulators."; exit 1; }

echo "Building for $DEVICE"
mkdir -p "$BUILD"
# The full output, with idevice's harmless simulator linker warnings, goes to a log.
xcodebuild -project LocSim.xcodeproj -scheme LocSim -configuration Debug \
    -destination "id=$UDID" -derivedDataPath "$BUILD" \
    CODE_SIGNING_ALLOWED=NO build -quiet > "$BUILD/build.log" 2>&1 ||
    { grep -E "error:" "$BUILD/build.log" >&2 || true; echo "Build failed, see $BUILD/build.log" >&2; exit 1; }
APP="$BUILD/Build/Products/Debug-iphonesimulator/LocSim.app"

boot() {
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null
    xcrun simctl status_bar "$UDID" override --time 9:41 \
        --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 \
        --batteryState discharging --batteryLevel 100
}

# Every step on its own: under set -e the first failure (e.g. a shut-down Simulator)
# would skip the rest.
restore() {
    xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
    case $ORIG_APPEARANCE in
        light|dark) xcrun simctl ui "$UDID" appearance "$ORIG_APPEARANCE" 2>/dev/null || true ;;
    esac
    if [ -n "$ORIG_LANGS" ]; then
        # Unquoted on purpose: one argument per language.
        # shellcheck disable=SC2086
        if xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array $ORIG_LANGS 2>/dev/null &&
            { [ -z "$ORIG_LOCALE" ] || xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string "$ORIG_LOCALE" 2>/dev/null; }; then
            echo "Simulator language set back to" $ORIG_LANGS"; it applies after the next restart."
        else
            echo "Could not set the Simulator language back to" $ORIG_LANGS "(${ORIG_LOCALE:-no locale}); set it in the Simulator's Settings." >&2
        fi
    fi
}

ORIG_LANGS=""
ORIG_LOCALE=""
ORIG_APPEARANCE=""
# Set before the first boot, so a failure from here on still clears the status bar.
trap restore EXIT
boot
# The Live Activity runs in its own process, which follows the Simulator's system language,
# not the app's launch arguments; each language therefore restarts the Simulator in it.
# The whole list, one language per line without the parentheses and quotes.
ORIG_LANGS=$(xcrun simctl spawn "$UDID" defaults read -g AppleLanguages 2>/dev/null | sed -e '1d' -e '$d' -e 's/[ ",]//g' || true)
ORIG_LOCALE=$(xcrun simctl spawn "$UDID" defaults read -g AppleLocale 2>/dev/null || true)
ORIG_APPEARANCE=$(xcrun simctl ui "$UDID" appearance 2>/dev/null || true)

system_language() {
    xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array "$1"
    xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string "$2"
    xcrun simctl shutdown "$UDID"
    boot
}

xcrun simctl install "$UDID" "$APP"

shoot() {
    # simctl may not replace a file another process wrote (e.g. git); it can create a new one.
    rm -f "$1"
    # simctl sometimes fails while an animation runs; try again before giving up.
    tries=0
    until xcrun simctl io "$UDID" screenshot --type=png "$1" >/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -lt 3 ] || { echo "Screenshot failed: $1" >&2; exit 1; }
        sleep 2
    done
    echo "${1#"$OUT"/}"
}

launch() {
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
        -demo "$1" -AppleLanguages "($lang)" -AppleLocale "$locale" >/dev/null ||
        { echo "Launch failed: $lang $1" >&2; exit 1; }
}

lock() {
    # simctl cannot set the wallpaper; the Lock Screen only looks light on a light one.
    if [ "$1" = light ]; then
        printf 'Light run: the Lock Screen needs a light wallpaper (Settings > Wallpaper in the Simulator). '
    else
        printf 'Dark run: the Lock Screen needs a dark wallpaper. '
    fi
    # After a restart the Live Activity can take a while to appear.
    printf 'When the Live Activity shows, lock the Simulator (Cmd-L), wait until it is on the Lock Screen, then press Enter. '
    read -r _
}

# screen:file:seconds to wait for map tiles and search results
SHOTS="map:1-map:8 search:2-search:8 recents:3-recents:6 favorites:5-favorites:8"

for lang in $LANGS; do
    case $lang in
        de) locale=de_DE ;;
        fr) locale=fr_FR ;;
        es) locale=es_ES ;;
        it) locale=it_IT ;;
        *) locale=en_US ;;
    esac
    system_language "$lang" "$locale"
    restarted=1
    for theme in light dark; do
        xcrun simctl ui "$UDID" appearance "$theme"
        if [ "$restarted" = 1 ]; then
            # After a restart the first map takes longer to load its tiles.
            launch map
            sleep 15
            restarted=0
        fi
        mkdir -p "$OUT/$lang/$theme"
        for shot in $SHOTS; do
            screen=${shot%%:*}
            wants "$screen" || continue
            rest=${shot#*:}
            name=${rest%%:*}
            wait=${rest#*:}
            launch "$screen"
            sleep "$wait"
            shoot "$OUT/$lang/$theme/$name.png"
        done

        wants live || continue
        # Lock Screen with the Live Activity. A restart unlocks the Simulator again.
        launch live
        sleep 8
        lock "$theme"
        sleep 4
        shoot "$OUT/$lang/$theme/4-live.png"
        # Only the next theme needs it; the next language restarts the Simulator anyway.
        if [ "$theme" = light ]; then
            xcrun simctl shutdown "$UDID"
            boot
            restarted=1
        fi
    done
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
