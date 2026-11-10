#!/usr/bin/env bash
# Create an RPPairing file over USB (Linux needs usbmuxd, macOS works as is).
# Usage: tools/make-pairing.sh [-u UDID] [hostname] [output]

# Started with sh, dash or zsh: run again with bash.
if [ -z "${BASH_VERSION:-}" ]; then
  if ! command -v bash >/dev/null 2>&1; then
    echo "This script needs bash." >&2
    exit 1
  fi
  if [ ! -f "$0" ]; then
    echo "Save the script to a file and run: bash make-pairing.sh" >&2
    exit 1
  fi
  exec bash "$0" "$@"
fi
# macOS sh is bash in POSIX mode.
set +o posix
set -euo pipefail
umask 077
# idevice-tools is written in Rust; its RUST_LOG output on stderr would count as an error below.
unset RUST_LOG

VERSION="v0.1.68"
UDID=""
HOSTNAME_ARG=""
OUT=""
npos=0
usage() { echo "Usage: bash $0 [-u UDID] [hostname] [output]"; }
add_pos() {
  npos=$((npos + 1))
  case "$npos" in
    1) HOSTNAME_ARG="$1" ;;
    2) OUT="$1" ;;
    *) echo "Too many arguments: $1" >&2; usage >&2; exit 2 ;;
  esac
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--udid)
      [[ $# -ge 2 ]] || { echo "$1 needs a UDID" >&2; exit 2; }
      UDID="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do add_pos "$1"; shift; done ;;
    -?*)
      echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) add_pos "$1"; shift ;;
  esac
done
HOSTNAME_ARG="${HOSTNAME_ARG:-locsim}"
OUT="${OUT:-rppairing.plist}"
if [[ -d "$OUT" ]]; then
  echo "The output must be a file name, not a folder: $OUT" >&2
  exit 2
elif [[ ! -d "$(dirname "$OUT")" ]]; then
  echo "Folder for the output file does not exist: $(dirname "$OUT")" >&2
  exit 2
fi

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

if [[ "$ASSET" == linux ]] && grep -qi microsoft /proc/version 2>/dev/null; then
  echo "This is WSL, which cannot reach an iPhone or iPad over USB." >&2
  echo "Run make-pairing.ps1 in Windows PowerShell instead (see the setup guide)." >&2
  exit 1
fi

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
  URL="https://github.com/jkcoxson/idevice/releases/download/$VERSION/idevice-tools-$ASSET-$VERSION.zip"
  if ! curl -fL --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 15 -o "$ZIP" "$URL"; then
    rm -rf "$DIR"
    echo "Download failed: $URL" >&2
    exit 1
  fi
  if command -v sha256sum >/dev/null; then
    actual="$(sha256sum "$ZIP" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  fi
  if [[ "$actual" != "$SHA" ]]; then
    rm -rf "$DIR"
    {
      echo "Checksum mismatch for $(basename "$ZIP"), the file was deleted."
      echo "  expected: $SHA"
      echo "  actual:   $actual"
    } >&2
    exit 1
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
  echo "  - the iPhone or iPad is unlocked and connected by USB" >&2
  echo "  - \"Trust This Computer\" was accepted on the device" >&2
  echo "  - Developer Mode is on (Settings > Privacy & Security)" >&2
  echo "  - only one device is connected, or pass --udid" >&2
  if [[ "$ASSET" == linux ]]; then
    echo "  - usbmuxd is running (systemctl status usbmuxd)" >&2
  fi
}

UDID_ARGS=()
if [[ -n "$UDID" ]]; then
  UDID_ARGS=(--udid "$UDID")
else
  # Without the list the tool would pick a device itself, a guess when several are connected.
  if ! devices="$("$LIST" 2>/dev/null)"; then
    # Run again for the message only: stderr in the list could be read as a device.
    list_err="$("$LIST" 2>&1 >/dev/null || true)"
    echo "Could not list the connected devices:" >&2
    printf '%s\n' "${list_err:-no output from idevice_id}" | sed 's/^/  /' >&2
    echo >&2
    checklist
    exit 1
  fi
  usb="$(printf '%s\n' "$devices" | awk '
    /connection_type:/ { usb = ($0 ~ /connection_type: Usb,/) }
    /udid:/ && usb { gsub(/[ ",]/, ""); sub(/^udid:/, ""); print }' | sort -u)"
  count="$(printf '%s' "$usb" | grep -c . || true)"
  if [[ "$count" -gt 1 ]]; then
    echo "More than one iPhone or iPad is connected over USB:" >&2
    printf '%s\n' "$usb" | sed 's/^/  /' >&2
    echo "Connect only one, or pick one with: bash $0 --udid <UDID>" >&2
    exit 1
  elif [[ "$count" -eq 1 ]]; then
    # Explicit, so a device that usbmuxd only sees over the network is not picked instead.
    UDID_ARGS=(--udid "$usb")
  else
    echo "No iPhone or iPad is connected over USB." >&2
    echo >&2
    checklist
    exit 1
  fi
fi

# The file holds a private key: keep it out of the current folder, which may be synced.
WORK=""
trap '[[ -z "$WORK" ]] || rm -rf "$WORK"' EXIT
# Without an explicit exit, bash would run the trap and carry on after Ctrl+C.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
WORK="$(mktemp -d)"
TMP="$WORK/rppairing.plist"

echo "Unlock the iPhone or iPad. If it asks, tap Trust and enter the passcode."
if ! pair_log="$("$BIN" ${UDID_ARGS[@]+"${UDID_ARGS[@]}"} remotepairing_lockdown pair "$HOSTNAME_ARG" "$TMP" 2>&1)" || [[ ! -s "$TMP" ]]; then
  echo "Pairing failed:" >&2
  printf '%s\n' "${pair_log:-no output from idevice-tools}" >&2
  echo >&2
  checklist
  exit 1
fi
chmod 600 "$TMP"
echo
echo "Hostname: $HOSTNAME_ARG (must match LocSim > Settings > Hostname)"
# LocSim picks the file up from its Documents folder and removes it there.
# The tool can report errors on stderr with exit code 0, so stderr counts as failure.
if afc_err="$("$BIN" ${UDID_ARGS[@]+"${UDID_ARGS[@]}"} afc --documents com.rockykln.locsim upload "$TMP" /Documents/rppairing.plist 2>&1 >/dev/null)" && [[ -z "$afc_err" ]]; then
  echo "Copied into LocSim and removed here. Open LocSim to finish."
else
  {
    echo "Could not copy the file into LocSim:"
    printf '%s\n' "${afc_err:-idevice-tools exited with an error}"
    echo "Is LocSim installed and the device unlocked?"
    echo
  } >&2
  # Kept for a manual import.
  if mv -f "$TMP" "$OUT"; then
    OUT_ABS="$(CDPATH= cd -- "$(dirname "$OUT")" >/dev/null && pwd)/$(basename "$OUT")"
  else
    WORK=""
    OUT_ABS="$TMP"
  fi
  {
    echo "The pairing file is at: $OUT_ABS"
    echo "It contains a private key."
    if [[ "$ASSET" == linux ]]; then
      echo "Move it to the device, for example with AirDrop from another device, and import it in LocSim."
    else
      echo "Move it to the device with AirDrop, or drag it into LocSim in Finder's Files tab."
    fi
    echo "Avoid cloud storage: the file grants access to the device. Delete it here afterwards."
  } >&2
  exit 3
fi
