#!/usr/bin/env bash
# Point the setup guide's script links at one commit, usually the one a build was made from.
# Usage: tools/pin-setup.sh [commit]   (default: HEAD)
set -euo pipefail
cd "$(dirname "$0")/.."

commit="$(git rev-parse --verify "${1:-HEAD}^{commit}")"
short="$(git rev-parse --short=7 "$commit")"
for script in tools/make-pairing.sh tools/make-pairing.ps1; do
  git cat-file -e "$commit:$script" || { echo "$script missing in $short" >&2; exit 1; }
done

for page in site/public/setup/index.html site/public/*/setup/index.html; do
  sed -i.bak -E "s#(raw\.githubusercontent\.com/Rockykln/locsim/)[^/]+(/tools/make-pairing\.)#\1$commit\2#g" "$page"
  rm -f "$page.bak"
done
echo "Setup guide now uses $short. Commit the pages; the links work once $short is pushed."
