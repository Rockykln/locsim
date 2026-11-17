# Changelog

What changed in each version that testers received through TestFlight.

## 1.0 (8), 17 November 2026

Replaces the earlier builds, which Apple ended. Same features as build 6, plus:

- iCloud Sync for favorites: a new or restored device waits for the list from iCloud and
  only adds to it; favorites deleted before that stay deleted
- A Clear that did not finish is shown as such: Clear stays available, and the Shortcuts
  actions and the map no longer treat the location as real
- LocSim's local connection passes on TCP only, and stops trying ports after Clear
- Pasting: Google Maps links use the place instead of the map view; labeled coordinates,
  Wikipedia's coordinate block, Waze and OpenStreetMap links and degrees with decimal
  minutes followed by the letter are recognized; search terms like "7 11" stay names
- Widget taps and quick actions wait until an open sheet has closed
- Keep Alive in Background is now Keep Location in Background
- A warning when a copy of the pairing file is left in LocSim's folder in Files
- Setup scripts check their cached download on every run; the setup page shows their checksums

## 1.0 (6), 10 November 2026

- Portuguese (Brazil) and Dutch
- The medium widget lists your most used favorites or the ones you choose in its settings
- iCloud Sync for favorites, off unless turned on in Settings. Favorites that a change
  from another device removes can be restored in Settings
- A notice when the time zone follows the simulated place, with the setting that keeps
  the real one
- New Shortcuts actions: Is Location Simulated and Get Simulated Location
- The Live Activity's coordinates stay readable on dark wallpapers and in Always On
- A pairing file the device does not accept is reported as such (LS-203), not as an
  unreachable device
- Setup scripts: clearer messages for iPad and when no device can be listed

## 1.0 (5), 5 November 2026

- Widgets for the Home Screen and the Lock Screen: they show whether a location is
  simulated and where, and the medium widget sets one of your most used favorites with
  a tap
- Control Center on iOS 18 or later: set the last location again or clear it
- Quick actions: hold the LocSim icon to clear the location, set the last one, pick a
  favorite or search
- Landscape on iPhone, and a layout for the iPhone Duo, folded and unfolded
- New Shortcuts action Set Location to Place: a place name, an address, coordinates or
  a map link
- If iOS switches back to the real location while LocSim runs, LocSim sets the
  simulated one again right away
- The place name is kept after LocSim was closed
- VoiceOver reads coordinates in words
- Many smaller fixes for the connection, the setup steps and the layout

## 1.0 (4), 4 November 2026

- Recent locations: the last five places, one tap away
- Paste coordinates or Apple Maps and Google Maps links into the search field
- Live Activity on the Lock Screen and in the Dynamic Island, with a Clear button
- Shortcuts and Siri: set a favorite or coordinates, clear the location
- Download the Developer Disk Image in advance in Settings
- More reliable connection and clearer error messages
- French, Spanish and Italian
- Accessibility improvements

## 1.0 (3), 4 November 2026

The first public beta.

- Set any location by searching a place, entering coordinates or holding a finger on
  the map
- Favorites
- The location stays simulated in the background, also on cellular, until you clear it
- One-time setup with a script on a Mac, Windows or Linux computer, which copies the
  pairing file straight into LocSim
- No extra VPN app needed any more
- Try Without a Device: look around the app before the setup
- English and German
