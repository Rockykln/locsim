#!/usr/bin/env bash
# Create an RPPairing file over USB (Linux needs usbmuxd, macOS works as is).
# Usage: tools/make-pairing.sh [-u UDID] [hostname] [output]
set -euo pipefail
umask 077
# idevice-tools is written in Rust; its RUST_LOG output on stderr would count as an error below.
unset RUST_LOG

VERSION="v0.1.68"
UDID=""
POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--udid)
      [[ $# -ge 2 ]] || { echo "$1 needs a UDID" >&2; exit 2; }
      UDID="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [-u UDID] [hostname] [output]"; exit 0 ;;
    *) POS+=("$1"); shift ;;
  esac
done
HOSTNAME_ARG="${POS[0]:-locsim}"
OUT="${POS[1]:-rppairing.plist}"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ASSET="linux";       SHA="87132c556db29b4fbaab8315f17fd0aa4eda0eee7c887ee80dad59ded68ce87f" ;;
  Darwin-arm64) ASSET="macos-arm";   SHA="fc4c2a74a3d2899bc33a7c2ed42d367e843b9dd6854bb3b1b257274b1ce712fa" ;;
  Darwin-x86_64) ASSET="macos-intel"; SHA="ba27ffd646a06ac411e185607343a8e8da437d1fa52a24a2d7c6411d4d8d1447" ;;
  Linux-aarch64|Linux-arm64)
    echo "Linux on ARM is not supported: idevice-tools $VERSION has no build for it." >&2
    echo "Use a computer with x86_64 Linux, macOS or Windows." >&2
    exit 1 ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

# Checked before the download, so nothing fails halfway with an unclear message.
for tool in curl unzip; do
  command -v "$tool" >/dev/null || { echo "This script needs $tool (for example: sudo apt install $tool)." >&2; exit 1; }
done
command -v sha256sum >/dev/null || command -v shasum >/dev/null \
  || { echo "This script needs sha256sum or shasum." >&2; exit 1; }
if [[ "$ASSET" == linux ]]; then
  # The Linux build of idevice-tools is linked against glibc 2.38.
  # getconf fails on musl; "|| true" keeps set -e from ending the script without a message.
  glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
  # awk instead of sort -V, which BusyBox does not have.
  if [[ -z "$glibc" ]] || ! awk -v v="$glibc" 'BEGIN { split(v, p, "."); exit !(p[1] + 0 > 2 || (p[1] + 0 == 2 && p[2] + 0 >= 38)) }'; then
    echo "idevice-tools $VERSION needs glibc 2.38 or newer (found: ${glibc:-none, e.g. musl})." >&2
    echo "That is Debian 13, Ubuntu 24.04, Fedora 39 or newer. Or use macOS or Windows." >&2
    exit 1
  fi
fi

if [[ "$ASSET" == linux ]]; then
  CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/locsim"
else
  CACHE="$HOME/Library/Caches/locsim"
fi
DIR="$CACHE/idevice-tools-$ASSET-$VERSION"
BIN="$DIR/idevice-tools"
LIST="$DIR/idevice_id"

if [[ "$(cat "$DIR/.verified" 2>/dev/null)" != "$VERSION $SHA" || ! -x "$BIN" || ! -x "$LIST" ]]; then
  rm -rf "$DIR"
  mkdir -p "$DIR"
  ZIP="$DIR/idevice-tools-$ASSET-$VERSION.zip"
  curl -fL -o "$ZIP" "https://github.com/jkcoxson/idevice/releases/download/$VERSION/idevice-tools-$ASSET-$VERSION.zip"
  if command -v sha256sum >/dev/null; then
    echo "$SHA  $ZIP" | sha256sum -c -
  else
    echo "$SHA  $ZIP" | shasum -a 256 -c -
  fi
  unzip -q -o "$ZIP" idevice-tools idevice_id -d "$DIR"
  rm -f "$ZIP"
  chmod +x "$BIN" "$LIST"
  if [[ "$ASSET" != linux ]]; then
    xattr -d com.apple.quarantine "$BIN" "$LIST" 2>/dev/null || true
  fi
  echo "$VERSION $SHA" > "$DIR/.verified"
fi

checklist() {
  echo "Check:" >&2
  echo "  - the iPhone is unlocked and connected by USB" >&2
  echo "  - \"Trust This Computer\" was accepted on the iPhone" >&2
  echo "  - Developer Mode is on (Settings > Privacy & Security)" >&2
  echo "  - only one iPhone is connected, or pass --udid" >&2
  if [[ "$ASSET" == linux ]]; then
    echo "  - usbmuxd is running (systemctl status usbmuxd)" >&2
  fi
}

UDID_ARGS=()
if [[ -n "$UDID" ]]; then
  UDID_ARGS=(--udid "$UDID")
elif devices="$("$LIST" 2>/dev/null)"; then
  usb="$(printf '%s\n' "$devices" | awk '
    /connection_type:/ { usb = ($0 ~ /connection_type: Usb,/) }
    /udid:/ && usb { gsub(/[ ",]/, ""); sub(/^udid:/, ""); print }' | sort -u)"
  count="$(printf '%s' "$usb" | grep -c . || true)"
  if [[ "$count" -gt 1 ]]; then
    echo "More than one iPhone is connected over USB:" >&2
    printf '%s\n' "$usb" | sed 's/^/  /' >&2
    echo "Connect only one, or pick one with: bash $0 --udid <UDID>" >&2
    exit 1
  elif [[ "$count" -eq 1 ]]; then
    # Explicit, so a device that usbmuxd only sees over the network is not picked instead.
    UDID_ARGS=(--udid "$usb")
  else
    echo "No iPhone is connected over USB." >&2
    echo >&2
    checklist
    exit 1
  fi
fi

echo "Make sure the iPhone is connected by USB, unlocked and trusts this computer."
rm -f "$OUT"
# A pairing file left behind by a failed or interrupted run must not stay on the disk.
trap 'rm -f "$OUT"' EXIT
# Without an explicit exit, bash would run the trap and carry on after Ctrl+C.
trap 'exit 130' INT
trap 'exit 143' TERM
if ! pair_log="$("$BIN" ${UDID_ARGS[@]+"${UDID_ARGS[@]}"} remotepairing_lockdown pair "$HOSTNAME_ARG" "$OUT" 2>&1)" || [[ ! -s "$OUT" ]]; then
  echo "Pairing failed:" >&2
  printf '%s\n' "${pair_log:-no output from idevice-tools}" >&2
  echo >&2
  checklist
  exit 1
fi
chmod 600 "$OUT"
OUT_ABS="$(CDPATH= cd -- "$(dirname "$OUT")" >/dev/null && pwd)/$(basename "$OUT")"
echo
echo "Hostname: $HOSTNAME_ARG (must match LocSim > Settings > Hostname)"
# LocSim picks the file up from its Documents folder and removes it there.
# The tool can report errors on stderr with exit code 0, so stderr counts as failure.
if afc_err="$("$BIN" ${UDID_ARGS[@]+"${UDID_ARGS[@]}"} afc --documents com.rockykln.locsim upload "$OUT" /Documents/rppairing.plist 2>&1 >/dev/null)" && [[ -z "$afc_err" ]]; then
  echo "Copied into LocSim and removed here. Open LocSim to finish."
else
  # The file is kept for a manual import.
  trap - EXIT
  {
    echo "Could not copy the file into LocSim:"
    printf '%s\n' "${afc_err:-idevice-tools exited with an error}"
    echo "Is LocSim installed and the iPhone unlocked?"
    echo
    echo "The pairing file is at: $OUT_ABS"
    if [[ "$ASSET" == linux ]]; then
      echo "Move it to the device, for example with AirDrop from another device, and import it in LocSim."
    else
      echo "Move it to the device with AirDrop, or drag it into LocSim in Finder's Files tab."
    fi
    echo "Avoid cloud storage: the file grants access to the device. Delete it here afterwards."
  } >&2
  exit 3
fi
