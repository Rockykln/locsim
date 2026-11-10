# Roadmap

Planned and proposed work. Only items marked *Approved* are scheduled. Finished work is
listed in [CHANGELOG.md](../CHANGELOG.md).

Effort: S = up to a day, M = a few days, L = a week or more.

| # | Item | Effort | Status |
| --- | --- | --- | --- |
| 5 | Route simulation | L | Proposed |
| 6 | GPX import and export | M | Proposed |
| 13 | iPad layout | M | Approved |
| 15 | More languages | S each | Approved |
| 18 | iPhone Duo screenshots | S | Approved |
| 23 | Siri AI tools | M | On branch, waiting for the SDK |
| 24 | Favorites synced through iCloud | M | Approved |
| 25 | Widget with chosen favorites | S | Approved |
| 26 | Shortcuts actions to read the state | S | Approved |
| 27 | Warning when the time zone follows the simulated place | M | Approved |

## Features

### 5. Route simulation

Move along a path at a chosen speed instead of jumping to one point, for testing
navigation and geofencing. The route is drawn on the map or imported (see 6).

Note: the location service only takes latitude and longitude, so movement is
simulated by sending points in short intervals.

### 6. GPX import and export

Import waypoints and tracks as favorites or routes; export favorites to share them.

### 23. Siri AI tools

Tool intents and a skill for Siri. They need the iOS 27.3 SDK, so they are kept on the
branch `feature/siri-ai` until that SDK is final.

## Layout

### 13. iPad layout

Use the larger screen, e.g. favorites and settings in a sidebar next to the map, on top
of the sidebar layout the iPhone Duo already has.

### 18. iPhone Duo screenshots

The Duo layout is done. Missing are a Duo size in `tools/screenshots.sh` and in the
mockups: 1398 x 2034 for the cover screen and 2853 x 2007 for the inner screen in
landscape. App Store submissions built with the iOS 27.1 SDK need them from April 2027.

## Distribution

### 15. More languages

Only languages whose translation can be verified. English, German, French, Spanish,
Italian, Portuguese (Brazil) and Dutch are done.
