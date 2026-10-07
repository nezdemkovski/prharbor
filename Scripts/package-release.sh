#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/PRHarbor.app /path/to/output-directory" >&2
    exit 64
fi

app_path="$1"
output_directory="$2"
script_directory="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$app_path/Contents/MacOS/PRHarbor" ]] || { echo "PRHarbor.app is missing" >&2; exit 1; }
mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/prharbor-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

ditto "$app_path" "$staging/PRHarbor.app"
codesign --force --sign - --options runtime --timestamp=none \
    --entitlements "$script_directory/../PRHarbor/PRHarbor.entitlements" "$staging/PRHarbor.app"
codesign --verify --deep --strict --verbose=2 "$staging/PRHarbor.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "PR Harbor" -srcfolder "$staging" \
    -ov -format UDZO "$output_directory/PRHarbor.dmg"
hdiutil verify "$output_directory/PRHarbor.dmg"
(cd "$output_directory" && shasum -a 256 PRHarbor.dmg > SHA256SUMS)
