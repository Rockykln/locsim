#!/bin/sh
# Takes the App Store screenshots in the iOS Simulator with the demo mode (macOS, Xcode).
# Usage: tools/screenshots.sh [lang ...]                all languages by default
#        SCREENS="live" tools/screenshots.sh           only the Lock Screen shots
#        DEVICE="iPhone 17" or UDID=<id>               which simulator (default: a booted
#                                                      "iPhone 17", else the first one listed)
# Output: design/screenshots/<lang>/<theme>/<name>.png, then run design/mockups/render.py.
#
# Each language gets one Simulator restart and all its screens, light and dark, plus one light
# Lock Screen shot with the Live Activity. Locking goes through the Simulator app (see
# lock_screen); the wallpaper has to be set by hand once, simctl cannot set it.
#        LOCK=manual          lock and wake the Simulator by hand
#        WALLPAPER=ok         skip the wallpaper question
#        WAKE_DELAY=12        minimum seconds between locking and waking, if the dimmed
#                             Live Activity is not recognized
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
    # A blank carrier: the lit Lock Screen would show "Carrier".
    xcrun simctl status_bar "$UDID" override --time 9:41 --operatorName " " \
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
# The app that shows the simulators: DeviceHub since Xcode 27, Simulator before.
if pgrep -xq DeviceHub; then
    SIM_APP=com.apple.dt.Devices
elif pgrep -xq Simulator; then
    SIM_APP=com.apple.iphonesimulator
elif [ -d "$(xcode-select -p)/../Applications/DeviceHub.app" ]; then
    SIM_APP=com.apple.dt.Devices
else
    SIM_APP=com.apple.iphonesimulator
fi
open -b "$SIM_APP" --args -CurrentDeviceUDID "$UDID" 2>/dev/null || true

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

# Locks the Simulator and wakes the Lock Screen, which a locked Simulator dims into Always On.
# simctl cannot do either, so it goes through the app that shows the simulators ($SIM_APP) like
# by hand: Cmd-L locks, and once it has dimmed the space bar wakes the Lock Screen without
# unlocking (DeviceHub ignores synthetic clicks, a second Cmd-L unlocks). Needs Accessibility
# access for the terminal app (System Settings > Privacy & Security > Accessibility); on the first
# run macOS also asks whether the terminal may control System Events.
press_key() {
    # $1: AppleScript keystroke command, run with $SIM_APP in front
    osascript - "$SIM_APP" "$1" 2>"$BUILD/lock.log" <<'APPLESCRIPT'
on run argv
    set appID to item 1 of argv
    tell application id appID to activate
    delay 1
    tell application "System Events"
        set frontmost of (first process whose bundle identifier is appID) to true
        delay 0.3
        if item 2 of argv is "lock" then
            keystroke "l" using command down
        else
            keystroke space
        end if
    end tell
end run
APPLESCRIPT
}

# Screenshot of the Lock Screen, judged by tools/live-check.py: prints "<state> <level>".
# $1: the level from the previous call, to tell whether the activity is still changing.
# Fails, with the reason in $BUILD/live.log, when either step does not work.
live_state() {
    xcrun simctl io "$UDID" screenshot --type=bmp "$BUILD/live.bmp" >"$BUILD/live.log" 2>&1 &&
        python3 "$ROOT/tools/live-check.py" "$BUILD/live.bmp" ${1:+"$1"} 2>"$BUILD/live.log"
}

lock_screen() {
    if [ "${LOCK:-auto}" = manual ]; then
        printf '%s: press Cmd-L in the Simulator, click its screen once so it is lit, then press Enter here. ' "$lang"
        read -r _
        return
    fi
    if ! press_key lock; then
        echo "Could not lock the Simulator automatically: $(head -1 "$BUILD/lock.log")" >&2
        echo "Allow the terminal app under System Settings > Privacy & Security > Accessibility" >&2
        echo "and under Automation for System Events, or run with LOCK=manual." >&2
        LOCK=manual
        lock_screen
        return
    fi
    # Wake only once the Live Activity has been on the Lock Screen for over a second and the
    # screen has dimmed into Always On: woken earlier, iOS keeps an unfinished activity.
    # If the dimmed activity is not recognized, WAKE_DELAY seconds with the activity shown do.
    shown=0 dimmed=0 i=0
    while [ "$i" -lt 40 ]; do
        sleep 1
        i=$((i + 1))
        if ! state=$(live_state); then
            # Without a working check, fall back to waiting WAKE_DELAY seconds.
            echo "  Lock Screen check failed: $(tail -1 "$BUILD/live.log")" >&2
            sleep $((${WAKE_DELAY:-12} - i > 0 ? ${WAKE_DELAY:-12} - i : 0))
            break
        fi
        echo "  ${i}s: ${state% *}"
        case "$state" in
            none*) shown=0 dimmed=0 ;;
            dim*) shown=$((shown + 1)) dimmed=$((dimmed + 1)) ;;
            *) shown=$((shown + 1)) dimmed=0 ;;
        esac
        [ "$dimmed" -ge 2 ] && break
        [ "$shown" -ge 2 ] && [ "$i" -ge "${WAKE_DELAY:-12}" ] && break
    done
    [ "$shown" -ge 2 ] || echo "  no Live Activity on the Lock Screen after ${i}s" >&2
    press_key wake || true
    echo "  locked with Cmd-L, woken with the space bar after ${i}s"
}

# Waits until the Live Activity is lit and finished drawing. After waking, iOS sometimes keeps
# the Always On version; another press of the space bar helps then. "Swipe up to open" fades
# after a few seconds; if it stays, the shot is taken with it.
wait_lit() {
    [ "${LOCK:-auto}" = manual ] && { sleep 3.5; return 0; }
    level=
    i=0
    while [ "$i" -lt 25 ]; do
        sleep 1
        i=$((i + 1))
        state=$(live_state "$level") || { echo "  Lock Screen check failed: $(tail -1 "$BUILD/live.log")" >&2; sleep 3.5; return 1; }
        level=${state#* }
        echo "  ${i}s: ${state% *}"
        case "$state" in
            lit*) echo "  Live Activity lit after ${i}s"; return 0 ;;
            hint*) [ "$i" -ge 15 ] && { echo "  Live Activity lit, \"Swipe up to open\" still shown"; return 0; } ;;
            dim*) case "$i" in 6 | 12 | 18) echo "  still Always On, pressing the space bar again"; press_key wake || true ;; esac ;;
        esac
    done
    echo "  The Live Activity did not light up; check $lang/4-live.png." >&2
    return 1
}

dim=
if wants live && [ "${WALLPAPER:-ask}" != ok ]; then
    say "The Lock Screen shots need a light stock wallpaper (Settings > Wallpaper in the Simulator).
It stays set; skip this question next time with WALLPAPER=ok. Press Enter to start."
    read -r _
fi

# One restart per language for all its screens: the Lock Screen's date and the Live Activity
# follow the system language, not the app's.
for lang in $LANGS; do
    system_language "$lang"
    first=1
    for theme in light dark; do
        xcrun simctl ui "$UDID" appearance "$theme"
        mkdir -p "$OUT/$lang/$theme"
        if [ "$first" = 1 ]; then
            # After a restart the first map takes longer to load its tiles, and iOS starts no
            # Live Activity yet.
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
    if wants live; then
        # One light shot, saved as <lang>/4-live.png; render.py uses it for both themes.
        # The restart for the next language unlocks the Simulator again.
        xcrun simctl ui "$UDID" appearance light
        echo "$lang: Lock Screen with the Live Activity"
        launch live
        # The demo starts the Live Activity after a second, and iOS takes a while to draw it.
        sleep 23
        lock_screen
        wait_lit || dim="$dim $lang"
        shoot "$OUT/$lang/4-live.png"
        # Older per-theme shots would win over this one in render.py.
        rm -f "$OUT/$lang/light/4-live.png" "$OUT/$lang/dark/4-live.png"
    fi
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
if [ -n "$dim" ]; then
    say "The Live Activity stayed in Always On for:$dim. Take these again with
  SCREENS=live WALLPAPER=ok tools/screenshots.sh$dim"
    exit 1
fi
say "Done. Next: design/mockups/render.py"
