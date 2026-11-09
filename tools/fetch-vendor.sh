#!/usr/bin/env bash
# Mirrors every third-party download the build and the app rely on into vendor/
# (ignored by git), verified against the pinned SHA-256 sums. Run again to check
# an existing mirror; files that already match are not downloaded again.
# Usage: tools/fetch-vendor.sh
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null && pwd)"
VENDOR="$ROOT/vendor"
IDEVICE="v0.1.68"
XCODEGEN="2.46.0"
DDI_COMMIT="d2d3e18b695e0e0bec3051f13e7ca6e0a50241e9"
GH="https://github.com"
DDI_URL="https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/$DDI_COMMIT/PersonalizedImages"

# path in vendor/ | sha256 | url
FILES="
idevice/idevice-xcframework-$IDEVICE.zip|c9eccdd1942de756d746a2569d93302774ab0eff1cff314ec8118f768b3d8dc7|$GH/jkcoxson/idevice/releases/download/$IDEVICE/idevice-xcframework-$IDEVICE.zip
idevice/idevice-tools-linux-$IDEVICE.zip|87132c556db29b4fbaab8315f17fd0aa4eda0eee7c887ee80dad59ded68ce87f|$GH/jkcoxson/idevice/releases/download/$IDEVICE/idevice-tools-linux-$IDEVICE.zip
idevice/idevice-tools-macos-arm-$IDEVICE.zip|fc4c2a74a3d2899bc33a7c2ed42d367e843b9dd6854bb3b1b257274b1ce712fa|$GH/jkcoxson/idevice/releases/download/$IDEVICE/idevice-tools-macos-arm-$IDEVICE.zip
idevice/idevice-tools-macos-intel-$IDEVICE.zip|ba27ffd646a06ac411e185607343a8e8da437d1fa52a24a2d7c6411d4d8d1447|$GH/jkcoxson/idevice/releases/download/$IDEVICE/idevice-tools-macos-intel-$IDEVICE.zip
idevice/idevice-tools-windows-$IDEVICE.zip|1c15e627652db1bc7c68f3d32675be07238b75282b510cd5828e9f4bec692a2f|$GH/jkcoxson/idevice/releases/download/$IDEVICE/idevice-tools-windows-$IDEVICE.zip
xcodegen/xcodegen-$XCODEGEN.zip|4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806|$GH/yonaskolb/XcodeGen/releases/download/$XCODEGEN/xcodegen.zip
ddi/Xcode_iOS_DDI_Cryptex/BuildManifest.plist|27385d7582b03b36bb3104e22b520aee0c47d72fecb4e8ecfe12ef5d966c7012|$DDI_URL/Xcode_iOS_DDI_Cryptex/BuildManifest.plist
ddi/Xcode_iOS_DDI_Cryptex/Image.dmg|873097f695a8b9734e2abc54f795a8874d40ff6fd11208ecb01ef29534c7c176|$DDI_URL/Xcode_iOS_DDI_Cryptex/Image.dmg
ddi/Xcode_iOS_DDI_Cryptex/Image.dmg.trustcache|f7f21986074eee03a215aca16ecfc78d6bf183600d8a0d2fb691f9896782e6f0|$DDI_URL/Xcode_iOS_DDI_Cryptex/Image.dmg.trustcache
ddi/Xcode_iOS_DDI_Cryptex/Image.dmg.cryptex_info|edf49aef55aacc063d4d7be05b713bb545ce2993b3f62bcc15eccd75e610ee6c|$DDI_URL/Xcode_iOS_DDI_Cryptex/Image.dmg.cryptex_info
ddi/Xcode_iOS_DDI_Cryptex/Image.dmg.root_hash|3543fad2805b88119695c417e12679380b3b5a2742994bbcc839c8e2de5d7302|$DDI_URL/Xcode_iOS_DDI_Cryptex/Image.dmg.root_hash
ddi/Xcode_iOS_DDI_Personalized/BuildManifest.plist|8edd4a2f4f4ef1fbd7bfe49785d8badc673d1395d1d94d85b132ca8ab5ecaf54|$DDI_URL/Xcode_iOS_DDI_Personalized/BuildManifest.plist
ddi/Xcode_iOS_DDI_Personalized/Image.dmg|05fd807da5e19f030fa4941f24800c965c6c77982ab572dd5d1ef778fb69f9ca|$DDI_URL/Xcode_iOS_DDI_Personalized/Image.dmg
ddi/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache|36af60889ff5a737874a26daeb8e1a0139ebfebec6ec2e4d8f6a3c1bf1dce35c|$DDI_URL/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache
"

if command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  echo "error: need sha256sum or shasum" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "error: need curl" >&2
  exit 1
fi

tmp=""
trap 'rm -f "$tmp"' EXIT
trap 'exit 130' INT TERM

failed=0
while IFS='|' read -r path sum url; do
  [ -n "$path" ] || continue
  target="$VENDOR/$path"
  if [ -f "$target" ]; then
    actual="$(sha "$target")"
    if [ "$actual" = "$sum" ]; then
      echo "ok        $path"
      continue
    fi
    # Remove it first so a failed download cannot leave the bad file behind.
    echo "mismatch  $path (expected $sum, got $actual), fetching again" >&2
    rm -f "$target"
  fi
  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp "$(dirname "$target")/.fetch.XXXXXX")"
  if ! curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 --retry-connrefused \
      -o "$tmp" "$url"; then
    echo "FAILED    $path (download failed: $url)" >&2
    failed=1
  else
    actual="$(sha "$tmp")"
    if [ "$actual" = "$sum" ]; then
      # mktemp creates the file as 0600.
      chmod 644 "$tmp"
      mv "$tmp" "$target"
      echo "fetched   $path"
    else
      echo "FAILED    $path (checksum mismatch: expected $sum, got $actual)" >&2
      failed=1
    fi
  fi
  rm -f "$tmp"
  tmp=""
done <<< "$FILES"

# For checking a copy elsewhere: (cd vendor && sha256sum -c SHA256SUMS), or
# shasum -a 256 -c SHA256SUMS. Written from the pins, not from what is on disk,
# so a missing or wrong file fails the check.
mkdir -p "$VENDOR"
tmp="$(mktemp "$VENDOR/.SHA256SUMS.XXXXXX")"
while IFS='|' read -r path sum url; do
  [ -n "$path" ] || continue
  printf '%s  ./%s\n' "$sum" "$path"
done <<< "$FILES" > "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$VENDOR/SHA256SUMS"
tmp=""
exit "$failed"
