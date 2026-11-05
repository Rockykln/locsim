# Roadmap

Planned and proposed work. Only items marked *Approved* are scheduled.

Effort: S = up to a day, M = a few days, L = a week or more.

| # | Item | Effort | Status |
| --- | --- | --- | --- |
| 1 | Live Activity while simulating | M | Done |
| 2 | Home Screen widget | M | Done, build 5 |
| 3 | Shortcuts and Siri (App Intents) | M | Done |
| 4 | Control Center control | S | Done, build 5 |
| 5 | Route simulation | L | Proposed |
| 6 | GPX import and export | M | Proposed |
| 7 | Recent locations | S | Done |
| 8 | Long press to drop a pin | S | Done |
| 9 | Degrees, minutes, seconds | S | Done |
| 10 | Pairing file check | S | Done |
| 11 | Unit tests in CI | M | Done |
| 12 | Accessibility pass | M | Done |
| 13 | iPad layout | M | Approved, build 6 |
| 14 | Privacy policy page | S | Done |
| 15 | More languages | S each | Approved |
| 16 | Welcome screen with setup steps | S | Done |
| 17 | Landscape on iPhone | M | Done, build 5 |
| 18 | iPhone Duo layout (before the iPad layout) | M | Layout done, build 5; screenshots open |
| 19 | Lock Screen widgets | S | Done, build 5 |
| 20 | Quick actions on the app icon | S | Done, build 5 |
| 21 | Shortcuts action Set Location to Place | S | Done, build 5 |
| 22 | Resend when iOS resets the location | S | Done, build 5 |
| 23 | Siri AI tools | M | On branch, after build 5 |

## Features

### 1. Live Activity while simulating

Lock Screen and Dynamic Island show the simulated place, since when it is active
(a running timer in the expanded Dynamic Island) and a Clear button. Makes it obvious that the location is not real.

Note: a Live Activity cannot keep the connection alive; the app keeps doing that.

### 2. Home Screen widget

Shows whether a location is simulated and where. The medium size also lists the three
most used favorites; tapping one opens LocSim and sets it. When LocSim may have ended
without saying so, the widget asks to open LocSim and check.

Note: widgets cannot open the device tunnel themselves, so every action goes
through the app.

### 3. Shortcuts and Siri (App Intents)

Actions such as *Set location to favorite*, *Set coordinates* and *Clear
location*, usable in Shortcuts automations and with Siri. Setting a location opens the app;
clearing runs in the background.

### 4. Control Center control

Two controls (iOS 18+): Set Last Location opens LocSim and sets the last location,
Clear Location ends it without opening LocSim.

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

### 16. Welcome screen with setup steps

Shown on launch until a pairing file is imported, and from Settings: the setup steps
with a link to the setup guide, the pairing file import and a way to try the app without
a device.

### 19. Lock Screen widgets

Inline, rectangular and circular, from the same data as the Home Screen widget (2).

### 20. Quick actions on the app icon

Clear Location while a location is simulated, otherwise Set Last Location; the two
most used favorites; Search. They always open LocSim.

Most used, here and in the widget: most runs of 30 minutes or more, then the longest
total time. Counted only on the device.

### 21. Shortcuts action Set Location to Place

Takes a place name, an address, coordinates or a map link and uses the same search as
the map. No Siri phrase; it is a Shortcuts action like Set Coordinates.

### 22. Resend when iOS resets the location

iOS can drop the simulation while LocSim runs. The keep-alive's coarse fixes are compared
with the simulated location (never stored); one far from it sends the location again
right away instead of at the next interval. Needs location access.

### 23. Siri AI tools

Tool intents and a skill for Siri. They need the iOS 27.3 SDK, so they are kept on the
branch `feature/siri-ai` and come after build 5.

## Quality

### 11. Unit tests in CI

Tests for coordinate parsing, error mapping and port selection; run on every push.

### 12. Accessibility pass

VoiceOver labels and order, Dynamic Type up to the largest sizes, contrast of the
glass panels.

## Layout

### 13. iPad layout

Use the larger screen, e.g. favorites and settings in a sidebar next to the map.
Planned for build 6, on top of the iPhone Duo sidebar (18).

### 17. Landscape on iPhone

Map in landscape with the panel at the side instead of below, so it covers less of the
map. Upside-down portrait stays off: iOS does not offer it on iPhones with Face ID.
Done in build 5: search across the top, the panel at the bottom right and the map
buttons at the bottom left; only the Dynamic Island's side keeps its inset.

### 18. iPhone Duo layout

Optimized for the foldable iPhone Duo before the iPad: it is an iPhone, runs the
iPhone's iOS and is more likely to be used with a SIM card on the go, where a simulated
location matters most.

Done in build 5: unfolded, search and panel form a sidebar column next to the map; on
the cover screen the panel and map buttons reach under the side status bar. Builds need
Xcode 27.1 or later, whose iOS 27.1 SDK lets LocSim use the whole inner screen.

Still missing: a Duo size in `tools/screenshots.sh` and the mockups. To be confirmed:
whether App Store submissions need iPhone Duo screenshots from April 2027.

## Distribution

### 14. Privacy policy page

Required by App Store Connect for external TestFlight testing. A short page stating
that LocSim collects no data.

### 15. More languages

Only languages whose translation can be verified. German, French, Spanish and Italian
are done.
