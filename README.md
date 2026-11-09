# LocSim

[![Build](https://github.com/Rockykln/locsim/actions/workflows/build.yml/badge.svg)](https://github.com/Rockykln/locsim/actions/workflows/build.yml)
![iOS](https://img.shields.io/badge/iOS-17.4%2B-lightgrey)
[![TestFlight](https://img.shields.io/badge/TestFlight-public%20beta-0a84ff)](#testflight)
![Languages](https://img.shields.io/badge/languages-en%20%7C%20de%20%7C%20fr%20%7C%20es%20%7C%20it-lightgrey)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Simulate the location of an iPhone on the iPhone itself, without a computer attached.
A developer tool for testing location-based apps.

<p align="center">
  <picture>
    <source media="(max-width: 600px) and (prefers-color-scheme: dark)" srcset="docs/images/screenshots-dark-narrow.webp">
    <source media="(max-width: 600px)" srcset="docs/images/screenshots-light-narrow.webp">
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/screenshots-dark.webp">
    <img src="docs/images/screenshots-light.webp" alt="LocSim: map with an active simulated location, recent locations and the Live Activity on the Lock Screen" width="800">
  </picture>
</p>

<p align="center">
  <a href="#testflight">Beta on TestFlight</a> ·
  <a href="https://locsim.rockykln.com/setup/">Setup guide</a> ·
  <a href="https://locsim.rockykln.com/support/">Support</a> ·
  <a href="https://locsim.rockykln.com">Website</a>
</p>

LocSim uses the same location simulation service as Xcode. It reaches the iPhone's own
developer services through a small local tunnel, after a one-time pairing with a
computer.

## Features

**Setting a location**

- Long-press the map, search for a place or enter coordinates
  (`48.8566, 2.3522`, `48,8566 2,3522`, `48°51'23.8"N 2°21'07.9"E`)
- Paste coordinates, Apple Maps or Google Maps links
- Favorites and the last five locations
- From outside the app: the Home Screen widget (medium size: the three most used
  favorites, a tap opens LocSim and sets one), quick actions on the app icon (Set Last
  Location, the two most used favorites, Search) and, on iOS 18 and later, a Control
  Center control for the last location
- Most used: most runs of 30 minutes or more, then the longest total time; counted
  only on the device

**While a location is simulated**

- Live Activity on the Lock Screen (since when, with a Clear button) and in the Dynamic
  Island (status icon; expanded, a running timer and the Clear button); can be turned off
  in Settings
- Home Screen and Lock Screen widgets (inline, rectangular, circular) show the place;
  when LocSim may have ended, they say to open LocSim and check
- Clear Location from Control Center (iOS 18 and later) or as a quick action on the app
  icon
- Keeps the location while LocSim is in the background, also on cellular
- Sends the location again right away when iOS resets it while LocSim runs (needs
  location access)
- Siri phrases: set a favorite, clear the location. Shortcuts actions: Set Location
  to Favorite, Set Coordinates, Set Location to Place (name, address, coordinates or
  map link), Clear Location
- Clear, or closing LocSim, restores the real location

**Under the hood**

- Its own local tunnel; no other app is needed
- Installs the Developer Disk Image when iOS has not mounted it, after asking before the
  download (about 16 MB); it can also be downloaded in advance in Settings
- Reconnects on its own after network changes
- Portrait and landscape on iPhone; on the iPhone Duo a layout for the cover screen and,
  unfolded, search and panel in a sidebar next to the map
- English, German, French, Spanish, Italian, Portuguese (Brazil) and Dutch; the language follows
  *Settings > Apps > LocSim > Language* (iOS 18 and later) or *Settings > LocSim >
  Language* (iOS 17)

## Requirements

- iPhone on iOS 17.4 or later with Developer Mode on
- iPad: runs as an iPhone app; not tested extensively
- Wi-Fi only while the connection is established (any network, no internet
  required). Once connected, locations can be changed on cellular.
- A Mac, Windows or Linux computer once, for Developer Mode and the pairing file

## TestFlight

- **Public Beta**: stable test builds. [Join on TestFlight](https://testflight.apple.com/join/vyrbctky).
- **Early Access**: new features land here first. Request a personal invite on the
  [website](https://locsim.rockykln.com/#beta); it prepares the email for you.
- **Development builds**: change often and can break. Also on request through the website.

## Installation

Join the [TestFlight beta](#testflight), or build and install LocSim with Xcode,
see [Building](#building). Building for a
device needs a paid Apple Developer membership, because free accounts cannot use
Network Extensions.

## Setup

Follow the [setup guide](https://locsim.rockykln.com/setup/): enable Developer Mode,
allow connections over Wi-Fi, create a pairing file and import it into LocSim. From a
clone of this repository, create the file with `tools/make-pairing.sh` or, on Windows,
`tools\make-pairing.ps1`. If LocSim is installed, the script copies the file into the
app over USB and deletes it from the computer.

## Usage

1. Join any Wi-Fi network.
2. Open LocSim, allow the VPN configuration when iOS asks (once) and allow Local
   Network access, which is needed to find the pairing port. Location access is
   optional and only used for the background keep-alive, for noticing when iOS resets
   the simulated location and for showing your real position.
3. Long-press the map, search for a place or enter coordinates, then
   *Set Location*.
4. *Clear* restores the real location and closes the connection.

Wi-Fi is only needed for step 3 the first time, when the connection is built.
While it stays open, new locations can be set without Wi-Fi. After *Clear* or
closing the app, the next connection needs Wi-Fi again.

After a restart, nothing has to be set up again. A new pairing file is
needed after an iOS update, a device reset or after clearing trusted computers.

## How it works

<details>
<summary>Tunnel, pairing and location service</summary>

```
LocSim ──TCP──▶ 10.7.0.1:<port> ──LocSimTunnel──▶ remotepairingd (same iPhone)
                                                    │ RPPairing + RemoteXPC tunnel
                                                    ▼
                                      com.apple.instruments.dtservicehub
                                      (DVT LocationSimulation)
```

1. LocSim starts its packet tunnel extension, which only routes the host
   `10.7.0.1`. It swaps the source and destination of each packet, so the traffic
   reaches this iPhone's own services. It has no server and no settings, and stops
   with LocSim, or by itself about two minutes after LocSim was closed.
2. The tunnel is opened on the default RPPairing port 49152. If that fails, the
   port is discovered via Bonjour (`_remotepairing._tcp`), as it can differ on
   some devices.
3. [idevice](https://github.com/jkcoxson/idevice) performs pair-verify with the
   imported RPPairing file and builds the tunnel.
4. If the Developer Disk Image is missing it is installed (cryptex on iOS 26.4+,
   personalized image before).
5. The location is sent over DVT and resent periodically. iOS resets it as soon
   as the connection closes. While LocSim runs, the coarse location updates of the
   background keep-alive are compared with the simulated location; a fix clearly more
   than 200 m away means iOS reset it, and LocSim sends it again.

</details>

## Troubleshooting

Errors show a code in the status line, for example LS-202. Tap it for details and
*Copy Details* for a support request; the technical log is under *Settings > Log*.
All codes and what to do are on the [support page](https://locsim.rockykln.com/support/).

## Privacy

No account, no analytics, no ads. The pairing file, favorites and recent locations stay
on the device, and the local tunnel sends nothing off it. Location fixes are only
compared with the simulated location and never stored. For the widgets, the app writes
the simulated place and up to three favorites into its App Group container on the
device. How often each favorite was used is counted on the device only. LocSim only
talks to Apple Maps for map tiles and search, to GitHub when the Developer Disk Image
has to be downloaded, and to Apple's signing server when it is installed. Details:
[privacy policy](https://locsim.rockykln.com/privacy/).

## Building

Requires Xcode 27.1 or later (its iOS 27.1 SDK lets LocSim use the whole inner screen of the iPhone Duo) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
curl -fLO https://github.com/jkcoxson/idevice/releases/download/v0.1.68/idevice-xcframework-v0.1.68.zip
echo "c9eccdd1942de756d746a2569d93302774ab0eff1cff314ec8118f768b3d8dc7  idevice-xcframework-v0.1.68.zip" | shasum -a 256 -c -
unzip -q idevice-xcframework-v0.1.68.zip
mkdir -p Frameworks && mv swift/IDevice.xcframework Frameworks/ && rm -rf swift idevice-xcframework-v0.1.68.zip
echo "DEVELOPMENT_TEAM = <your team id>" > Config/Local.xcconfig
xcodegen generate
open LocSim.xcodeproj
```

The team ID is the 10-character value after `OU=` in
`security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`.
`Config/Local.xcconfig` is ignored by git. Run `xcodegen generate` again after
pulling changes. The build commit is stamped into the app by a scheme pre-action
and shown under *Settings > About*.

GitHub Actions builds every push to `main` and every pull request. The TestFlight
workflow only runs when started by hand; see [docs/RELEASING.md](docs/RELEASING.md).

## Tests

The logic without UIKit or the device library lives in `Packages/LocSimCore` and
builds on macOS and Linux:

```
swift test --package-path Packages/LocSimCore
```

CI runs these tests on Linux; the iOS build only starts when they pass.

## Project layout

```
LocSim/
  App/        App entry and lifecycle
  Intents/    Shortcuts actions and Siri phrases
  Device/     idevice bridge, port discovery, pairing and DDI storage
  Session/    Simulation state, keep-alive, search, settings, widget sync,
              quick actions, favorite use counts
  Views/      SwiftUI screens
LocSimTunnel/ Packet tunnel extension
LocSimWidgets/ Live Activity, widgets and Control Center controls (extension)
LiveActivity/ Code shared by the app and the extension: activity attributes,
              intents, widget snapshot
Packages/     LocSimCore: parser, tunnel packets, ports, error codes, with unit tests
Config/       Shared xcconfig, local overrides are git-ignored
docs/         Release process, roadmap, TestFlight notes, README images
CHANGELOG.md  What changed in each TestFlight build
design/       App icon, mockups, screenshots, social images
site/         Website locsim.rockykln.com (Cloudflare Worker, static files in public/)
tools/        Pairing file creation (macOS, Linux, Windows), screenshots,
              fetch-vendor.sh to mirror all pinned downloads into vendor/,
              pin-setup.sh to point the setup guide at a build's commit
```

## Disclaimer

LocSim is a development tool. Using a simulated location may violate the terms of
other apps and services; you are responsible for how you use it. This project is
not affiliated with or endorsed by Apple.

## Acknowledgements

- [idevice](https://github.com/jkcoxson/idevice) by Jackson Coxson, MIT
- [DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage) by doronz88
- [StosVPN](https://github.com/SideStore/StosVPN) by the SideStore Team; the local
  tunnel is based on it
- [StikDebug](https://github.com/StikDebug/StikDebug), which showed the on-device
  approach

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and, for the Rust crates inside
idevice, [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## License

[MIT](LICENSE)
