#!/bin/sh
# Takes the App Store screenshots in the iOS Simulator with the demo mode (macOS, Xcode).
# Usage: tools/screenshots.sh [lang ...]                all languages by default
#        SCREENS="live" tools/screenshots.sh           only the Lock Screen shots
#        DEVICE="iPhone 17" or UDID=<id>               which simulator (default: a booted
#                                                      "iPhone 17", else the first one listed)
# Output: design/screenshots/<lang>/<theme>/<name>.png, then run design/mockups/render.py.
#
# First every other screen is taken without help, light and dark. The Lock Screen shots with
# the Live Activity come last, one per language, because simctl can neither lock the
# Simulator nor set its wallpaper.
set -eu

DEVICE=${DEVICE:-"iPhone 17"}
BUNDLE=com.rockykln.locsim
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null && pwd)
OUT="$ROOT/design/screenshots"
BUILD="$ROOT/build/screenshots"
LANGS=${*:-"en de fr es it"}
SCREENS=${SCREENS:-"map search recents live favorites"}
# screen:file:seconds to wait for map tiles and search results
SHOTS="map:1-map:8 search:2-search:8 recents:3-recents:6 favorites:5-favorites:8"

wants() { case " $SCREENS " in *" $1 "*) return 0 ;; esac; return 1; }
say() { printf '\n%s\n' "$*"; }

for lang in $LANGS; do
    case $lang in en|de|fr|es|it) ;; *) echo "Unknown language: $lang (en de fr es it)" >&2; exit 1 ;; esac
done
for screen in $SCREENS; do
    case $screen in map|search|recents|live|favorites) ;; *) echo "Unknown screen: $screen (map search recents live favorites)" >&2; exit 1 ;; esac
done

cd "$ROOT"
[ -d LocSim.xcodeproj ] || { echo "Run xcodegen generate first."; exit 1; }

# A booted device with that name first, so the shots happen on the one on screen. Otherwise the
# first one listed: several devices can share a name, one per installed iOS version.
udid_of() { sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'; }
if [ -z "${UDID:-}" ]; then
    UDID=$(xcrun simctl list devices booted | grep -F "    $DEVICE (" | head -1 | udid_of || true)
fi
if [ -z "${UDID:-}" ]; then
    UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | head -1 | udid_of || true)
fi
[ -n "$UDID" ] || { echo "No simulator named \"$DEVICE\". Add one in Xcode > Window > Devices and Simulators." >&2; exit 1; }
RUNTIME=$(xcrun simctl list devices | awk -v id="$UDID" '/^-- / { rt = $0 } index($0, id) { print rt; exit }' | tr -d '-' | sed 's/^ *//; s/ *$//')
echo "Simulator: $DEVICE, $RUNTIME, $UDID"

echo "Building LocSim"
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

# Every step on its own: under set -e the first failure would skip the rest.
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
# dash skips the EXIT trap on Ctrl-C unless the signal ends the script through exit.
trap 'exit 130' INT TERM HUP

echo "Starting the Simulator"
boot
# Shows the device in the Simulator app; Cmd-L locks the device on screen.
open -b com.apple.iphonesimulator --args -CurrentDeviceUDID "$UDID" 2>/dev/null || true
ORIG_LANGS=$(xcrun simctl spawn "$UDID" defaults read -g AppleLanguages 2>/dev/null | sed -e '1d' -e '$d' -e 's/[ ",]//g' || true)
ORIG_LOCALE=$(xcrun simctl spawn "$UDID" defaults read -g AppleLocale 2>/dev/null || true)
ORIG_APPEARANCE=$(xcrun simctl ui "$UDID" appearance 2>/dev/null || true)
xcrun simctl install "$UDID" "$APP"

locale_for() {
    case $1 in
        de) echo de_DE ;;
        fr) echo fr_FR ;;
        es) echo es_ES ;;
        it) echo it_IT ;;
        *) echo en_US ;;
    esac
}

current_language() {
    xcrun simctl spawn "$UDID" defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",'
}

# The Live Activity runs in its own process, which follows the Simulator's system language,
# not the app's launch arguments; each language therefore restarts the Simulator in it.
# The restart also unlocks the Simulator again.
system_language() {
    echo "$1: restarting the Simulator in this language"
    tries=0
    while :; do
        xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array "$1"
        xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string "$(locale_for "$1")"
        xcrun simctl shutdown "$UDID" 2>/dev/null || true
        boot
        [ "$(current_language)" = "$1" ] && return 0
        tries=$((tries + 1))
        [ "$tries" -lt 2 ] || { echo "The Simulator did not switch to $1 (it reports \"$(current_language)\")." >&2; exit 1; }
    done
}

shoot() {
    # simctl may not replace a file another process wrote (e.g. git); it can create a new one.
    rm -f "$1"
    # simctl sometimes fails while an animation runs; try again before giving up.
    tries=0
    until xcrun simctl io "$UDID" screenshot --type=png "$1" >/dev/null 2>&1; do
        tries=$((tries + 1))
        [ "$tries" -lt 3 ] || { echo "Screenshot failed: $1" >&2; exit 1; }
        sleep 2
    done
    echo "  saved ${1#"$OUT"/}"
}

launch() {
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
        -demo "$1" -AppleLanguages "($lang)" -AppleLocale "$(locale_for "$lang")" >/dev/null ||
        { echo "Launch failed: $lang $1" >&2; exit 1; }
}

# Pass 1: everything but the Lock Screen, no help needed.
pass1=0
for shot in $SHOTS; do
    if wants "${shot%%:*}"; then pass1=1; fi
done
if [ "$pass1" = 1 ]; then
    for lang in $LANGS; do
        system_language "$lang"
        first=1
        for theme in light dark; do
            xcrun simctl ui "$UDID" appearance "$theme"
            mkdir -p "$OUT/$lang/$theme"
            if [ "$first" = 1 ]; then
                # After a restart the first map takes longer to load its tiles.
                echo "$lang: warming up the map"
                launch map
                sleep 15
                first=0
            fi
            for shot in $SHOTS; do
                screen=${shot%%:*}
                wants "$screen" || continue
                rest=${shot#*:}
                name=${rest%%:*}
                wait=${rest#*:}
                echo "$lang $theme: $screen"
                launch "$screen"
                sleep "$wait"
                shoot "$OUT/$lang/$theme/$name.png"
            done
        done
    done
fi

# Pass 2: the Lock Screen with the Live Activity, one shot per language in light mode. It is
# saved as <lang>/4-live.png, which render.py uses for the light and the dark images alike.
if wants live; then
    say "=== Lock Screen shots ===
In the Simulator, pick a light stock wallpaper (Settings > Wallpaper).
Then press Enter here. The script waits until you do."
    read -r _
    for lang in $LANGS; do
        system_language "$lang"
        xcrun simctl ui "$UDID" appearance light
        mkdir -p "$OUT/$lang"
        # Right after a restart iOS starts no Live Activity yet; the map warms it up.
        echo "$lang: starting LocSim, the Live Activity follows in about 25 seconds"
        launch map
        sleep 15
        launch live
        sleep 8
        # Locked, the Simulator dims into Always On; a click wakes the Lock Screen without unlocking.
        printf '%s: once the Live Activity shows, press Cmd-L in the Simulator, click its screen once so it is lit, then press Enter here. ' "$lang"
        read -r _
        # Right away, before the screen dims again.
        sleep 1
        shoot "$OUT/$lang/4-live.png"
        # Older per-theme shots would win over this one in render.py.
        rm -f "$OUT/$lang/light/4-live.png" "$OUT/$lang/dark/4-live.png"
    done
fi
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
say "Done. Next: design/mockups/render.py"
