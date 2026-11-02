# Roadmap

Planned and proposed work. Only items marked *Approved* are scheduled.

Effort: S = up to a day, M = a few days, L = a week or more.

| # | Item | Effort | Status |
| --- | --- | --- | --- |
| 1 | Live Activity while simulating | M | Approved |
| 2 | Home Screen widget | M | Approved |
| 3 | Shortcuts and Siri (App Intents) | M | Approved |
| 4 | Control Center control | S | Approved |
| 5 | Route simulation | L | Proposed |
| 6 | GPX import and export | M | Proposed |
| 7 | Recent locations | S | Proposed |
| 8 | Long press to drop a pin | S | Done |
| 9 | Degrees, minutes, seconds | S | Done |
| 10 | Pairing file check | S | Approved |
| 11 | Unit tests in CI | M | Proposed |
| 12 | Accessibility pass | M | Approved |
| 13 | iPad layout | M | Approved |
| 14 | Privacy policy page | S | Approved, before release |
| 15 | More languages | S each | Approved |

## Features

### 1. Live Activity while simulating

Lock Screen and Dynamic Island show the simulated place, how long it has been
active and a Stop button. Makes it obvious that the location is not real.

Note: a Live Activity cannot keep the connection alive; the app keeps doing that.

### 2. Home Screen widget

Shows whether a location is simulated and where. Tapping a favorite in the widget
opens LocSim and sets it.

Note: widgets cannot open the device tunnel themselves, so every action goes
through the app.

### 3. Shortcuts and Siri (App Intents)

Actions such as *Set location to favorite*, *Set coordinates* and *Clear
location*, usable in Shortcuts automations and with Siri. Opens the app to run.

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

The last ten simulated places, available from the search field.

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

## Distribution

### 14. Privacy policy page

Required by App Store Connect for external TestFlight testing. A short page stating
that LocSim collects no data.

### 15. More languages

Only languages whose translation can be verified. German is done.
