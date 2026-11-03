# Roadmap

Planned and proposed work. Only items marked *Approved* are scheduled.

Effort: S = up to a day, M = a few days, L = a week or more.

| # | Item | Effort | Status |
| --- | --- | --- | --- |
| 1 | Live Activity while simulating | M | Done |
| 2 | Home Screen widget | M | Approved |
| 3 | Shortcuts and Siri (App Intents) | M | Done |
| 4 | Control Center control | S | Approved |
| 5 | Route simulation | L | Proposed |
| 6 | GPX import and export | M | Proposed |
| 7 | Recent locations | S | Done |
| 8 | Long press to drop a pin | S | Done |
| 9 | Degrees, minutes, seconds | S | Done |
| 10 | Pairing file check | S | Done |
| 11 | Unit tests in CI | M | Done |
| 12 | Accessibility pass | M | Done |
| 13 | iPad layout | M | Approved |
| 14 | Privacy policy page | S | Done |
| 15 | More languages | S each | Approved |
| 16 | Welcome screen with setup steps | S | Done |
| 17 | Landscape on iPhone | M | Approved |
| 18 | iPhone Duo layout (before the iPad layout) | M | Approved |

## Features

### 1. Live Activity while simulating

Lock Screen and Dynamic Island show the simulated place, since when it is active
(a running timer in the expanded Dynamic Island) and a Clear button. Makes it obvious that the location is not real.

Note: a Live Activity cannot keep the connection alive; the app keeps doing that.

### 2. Home Screen widget

Shows whether a location is simulated and where. Tapping a favorite in the widget
opens LocSim and sets it.

Note: widgets cannot open the device tunnel themselves, so every action goes
through the app.

### 3. Shortcuts and Siri (App Intents)

Actions such as *Set location to favorite*, *Set coordinates* and *Clear
location*, usable in Shortcuts automations and with Siri. Setting a location opens the app;
clearing runs in the background.

### 4. Control Center control

A control (iOS 18+) that opens LocSim and sets the last location, or clears it.

### 5. Route simulation

Move along a path at a chosen speed instead of jumping to one point, for testing
navigation and geofencing. The route is drawn on the map or imported (see 6).

Note: the location service only takes latitude and longitude, so movement is
simulated by sending points in short intervals.

### 6. GPX import and export

Import waypoints and tracks as favorites or routes; export favorites to share them.

### 7. Recent locations

The last five simulated places, available from the search field; can be turned off.

### 8. Long press to drop a pin

Matches Apple Maps; a tap no longer moves the pin.

### 9. Degrees, minutes, seconds

Accept and optionally display `48°51'23.8"N 2°21'07.9"E`.

### 10. Pairing file check

Verify the imported file against the device on demand and show a clear result,
instead of only finding out on the next connection.

## Quality

### 11. Unit tests in CI

Tests for coordinate parsing, error mapping and port selection; run on every push.

### 12. Accessibility pass

VoiceOver labels and order, Dynamic Type up to the largest sizes, contrast of the
glass panels.

### 13. iPad layout

Use the larger screen, e.g. favorites and settings in a sidebar next to the map.
Comes after the iPhone Duo layout (18), which it can build on.

### 17. Landscape on iPhone

Map in landscape with the panel at the side instead of below, so it covers less of the
map. Upside-down portrait stays off: iOS does not offer it on iPhones with Face ID.
Fits together with the iPad layout (13).

### 18. iPhone Duo layout

Optimized for the foldable iPhone Duo before the iPad: it is an iPhone, runs the
iPhone's iOS and is far more likely to be used with a SIM card on the go, where a
simulated location matters most. Needs the iOS 27.1 SDK, which lets the app use the
whole inner screen instead of running with bars at the sides, and a layout for the
unfolded screen (map with the panel at the side, like landscape in 17) that also works
folded. Xcode's Device Hub can simulate both poses. From April 2027 App Store
submissions need iPhone Duo screenshots, so `tools/screenshots.sh` and the mockups need
a Duo size too.

## Distribution

### 14. Privacy policy page

Required by App Store Connect for external TestFlight testing. A short page stating
that LocSim collects no data.

### 15. More languages

Only languages whose translation can be verified. German, French, Spanish and Italian
are done.
