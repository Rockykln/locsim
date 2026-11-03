#!/usr/bin/env bash
# Create an RPPairing file over USB (Linux needs usbmuxd, macOS works as is).
# Usage: tools/make-pairing.sh [hostname] [output]
set -euo pipefail
umask 077

VERSION="v0.1.68"
HOSTNAME_ARG="${1:-locsim}"
OUT="${2:-rppairing.plist}"
DIR="$(cd "$(dirname "$0")" && pwd)/bin"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ASSET="linux";       SHA="87132c556db29b4fbaab8315f17fd0aa4eda0eee7c887ee80dad59ded68ce87f" ;;
  Darwin-arm64) ASSET="macos-arm";   SHA="fc4c2a74a3d2899bc33a7c2ed42d367e843b9dd6854bb3b1b257274b1ce712fa" ;;
  Darwin-x86_64) ASSET="macos-intel"; SHA="ba27ffd646a06ac411e185607343a8e8da437d1fa52a24a2d7c6411d4d8d1447" ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

BIN="$DIR/$ASSET-$VERSION/idevice-tools"
if [[ ! -x "$BIN" ]]; then
  mkdir -p "$DIR/$ASSET-$VERSION"
  ZIP="$DIR/idevice-tools-$ASSET-$VERSION.zip"
  curl -fL -o "$ZIP" "https://github.com/jkcoxson/idevice/releases/download/$VERSION/idevice-tools-$ASSET-$VERSION.zip"
  if command -v sha256sum >/dev/null; then
    echo "$SHA  $ZIP" | sha256sum -c -
  else
    echo "$SHA  $ZIP" | shasum -a 256 -c -
  fi
  unzip -q -o "$ZIP" -d "$DIR/$ASSET-$VERSION"
  found="$(find "$DIR/$ASSET-$VERSION" -type f -name idevice-tools | head -1)"
  [[ "$found" != "$BIN" ]] && mv "$found" "$BIN"
  chmod +x "$BIN"
  [[ "$ASSET" != linux ]] && xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
fi

echo "iPhone: connected via USB, unlocked, trusted."
"$BIN" remotepairing_lockdown pair "$HOSTNAME_ARG" "$OUT"
chmod 600 "$OUT"
echo
echo "Hostname: $HOSTNAME_ARG (must match LocSim > Settings > Hostname)"
# LocSim picks the file up from its Documents folder and removes it there.
if "$BIN" afc --documents com.rockykln.locsim upload "$OUT" /Documents/rppairing.plist >/dev/null 2>&1; then
  rm -f "$OUT"
  echo "Copied into LocSim and removed here. Open LocSim to finish."
else
  echo "Could not copy the file into LocSim. Is it installed on this iPhone?"
  echo "Move $OUT to the device with AirDrop, or drag it into LocSim in Finder's Files tab."
  echo "Avoid cloud storage: the file grants access to the device. Delete it here afterwards."
fi
