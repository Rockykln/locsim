#!/usr/bin/env bash
# Point the setup guide's script links at one commit on main.
# Usage: tools/pin-setup.sh [-n] [commit]   (-n: dry run)
# Default: the last commit on origin/main that changed a setup script, so a run with no
# script changes since the last pin reports "Already pinned".
set -euo pipefail

usage() { echo "usage: tools/pin-setup.sh [-n] [commit]" >&2; exit 2; }
die() { echo "pin-setup: $*" >&2; exit 1; }

dry=0
while getopts n opt; do
  case $opt in
    n) dry=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || usage

cd "$(git rev-parse --show-toplevel)"

pages="site/public/setup/index.html site/public/de/setup/index.html site/public/fr/setup/index.html site/public/es/setup/index.html site/public/it/setup/index.html"
scripts="tools/make-pairing.sh tools/make-pairing.ps1"
raw_re='raw\.githubusercontent\.com/Rockykln/locsim/[^/"<[:space:]]+/tools/make-pairing\.(sh|ps1)'
tree_re='github\.com/Rockykln/locsim/tree/(main|[0-9a-f]{40})/tools"'

git fetch -q origin main || die "git fetch origin main failed"
if [ $# -eq 1 ]; then
  commit="$(git rev-parse -q --verify "$1^{commit}")" || die "unknown commit: $1"
else
  commit="$(git log -1 --format=%H origin/main -- $scripts)"
  [ -n "$commit" ] || die "no commit on origin/main changes the setup scripts"
fi
short="$(git rev-parse --short=7 "$commit")"

# Only commits on main stay reachable; other branches may be deleted.
git merge-base --is-ancestor "$commit" origin/main ||
  die "$short is not on origin/main. Merge and push it first, then pin."

for page in $pages; do
  [ -f "$page" ] || die "$page not found"
done
dirty="$(git status --porcelain -- $pages)"
[ -z "$dirty" ] || die "setup pages have uncommitted changes:
$dirty"

for script in $scripts; do
  git cat-file -e "$commit:$script" 2>/dev/null || die "$script missing in $short"
done

tmps=""
trap 'rm -f $tmps' EXIT

old=""
changed=0
for page in $pages; do
  links="$(grep -oE "$raw_re" "$page" || true)"
  n="$(printf '%s' "$links" | grep -c . || true)"
  [ "$n" -eq 2 ] || die "$page: expected 2 script links, found $n"
  for pin in $(printf '%s\n' "$links" | sed -E 's#^raw\.githubusercontent\.com/Rockykln/locsim/([^/]+)/.*#\1#'); do
    [ -z "$old" ] && old="$pin"
    [ "$pin" = "$old" ] || die "pages disagree on the current pin ($old vs $pin in $page)"
  done
  n="$(grep -oE "$tree_re" "$page" | grep -c . || true)"
  [ "$n" -eq 1 ] || die "$page: expected 1 'read the scripts' link, found $n"

  tmp="$(mktemp "$page.XXXXXX")"
  tmps="$tmps $tmp"
  cp -p "$page" "$tmp"
  sed -E \
    -e "s#(raw\.githubusercontent\.com/Rockykln/locsim/)[^/\"<[:space:]]+(/tools/make-pairing\.)#\1$commit\2#g" \
    -e "s#(github\.com/Rockykln/locsim/tree/)(main|[0-9a-f]{40})(/tools\")#\1$commit\3#g" \
    "$page" > "$tmp"
  n="$(grep -oE "Rockykln/locsim/(tree/)?$commit/tools(/make-pairing\.|\")" "$tmp" | grep -c . || true)"
  [ "$n" -eq 3 ] || die "$page: rewrite check failed"
  cmp -s "$page" "$tmp" || changed=1
done

if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum; }; else sha() { shasum -a 256; }; fi
echo "New pin: $commit"
for script in $scripts; do
  echo "  sha256 $(git show "$commit:$script" | sha | cut -d' ' -f1)  $script"
done

echo "Old pin: $old"
if [ "$old" = "$commit" ]; then
  :
elif git rev-parse -q --verify "$old^{commit}" >/dev/null; then
  if git merge-base --is-ancestor "$old" "$commit"; then
    echo "Script commits since the old pin:"
    log="$(git log --oneline "$old..$commit" -- $scripts)"
    printf '%s\n' "${log:-(none)}" | sed 's/^/  /'
  else
    echo "WARNING: the new pin is not newer than the old one." >&2
    echo "Script commits only in old (<) or new (>) pin:"
    git --no-pager log --oneline --left-right "$old...$commit" -- $scripts | sed 's/^/  /'
  fi
else
  echo "WARNING: old pin $old is not a known commit, cannot compare." >&2
fi

if [ "$changed" -eq 0 ]; then
  echo "Already pinned to $short, nothing to do."
  exit 0
fi

if [ "$dry" -eq 1 ]; then
  set -- $tmps
  for page in $pages; do
    diff -u -L "a/$page" -L "b/$page" "$page" "$1" || true
    shift
  done
  echo "Dry run, no files written."
  exit 0
fi

set -- $tmps
for page in $pages; do
  mv "$1" "$page"
  shift
done
echo "Setup guide now uses $short. Commit the pages and push to main; the site goes live with that push."
