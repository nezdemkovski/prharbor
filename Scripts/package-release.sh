#!/bin/bash
# Signs PR Harbor, packages it as a DMG and, for Developer ID builds, notarizes and staples
# both the app and the DMG.
#
#   SIGNING_IDENTITY  "Developer ID Application: …" for releases; "-" (default) signs ad hoc
#                     for local packaging only.
#   Notarization credentials, required for Developer ID builds unless NOTARIZE=0:
#     NOTARY_KEYCHAIN_PROFILE  a profile saved with `xcrun notarytool store-credentials`, or
#     NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID  an App Store Connect API key.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/PRHarbor.app /path/to/output-directory" >&2
    exit 64
fi

app_path="$1"
output_directory="$2"
script_directory="$(cd "$(dirname "$0")" && pwd)"
entitlements="$script_directory/../PRHarbor/PRHarbor.entitlements"
identity="${SIGNING_IDENTITY:--}"
[[ -f "$app_path/Contents/MacOS/PRHarbor" ]] || { echo "PRHarbor.app is missing" >&2; exit 1; }
mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/prharbor-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

notarize=0
if [[ "$identity" != "-" && "${NOTARIZE:-1}" != "0" ]]; then
    notarize=1
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        notary_credentials=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
        notary_credentials=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    else
        echo "Developer ID builds need notarization credentials (or NOTARIZE=0 for a local check)" >&2
        exit 1
    fi
fi

# Submits a file and fails unless Apple accepts it, printing the notary log on rejection.
notarize_file() {
    local result id status
    result="$(xcrun notarytool submit "$1" "${notary_credentials[@]}" --wait --output-format json)"
    id="$(plutil -extract id raw - <<< "$result")"
    status="$(plutil -extract status raw - <<< "$result")"
    if [[ "$status" != "Accepted" ]]; then
        echo "Notarization of $(basename "$1") finished with status $status" >&2
        xcrun notarytool log "$id" "${notary_credentials[@]}" >&2 || true
        exit 1
    fi
}

ditto "$app_path" "$staging/PRHarbor.app"
if [[ "$identity" == "-" ]]; then
    timestamp=(--timestamp=none)
else
    timestamp=(--timestamp)
fi
# The app's only executable is its main binary; the Defaults resource bundle holds no code.
codesign --force --sign "$identity" --options runtime "${timestamp[@]}" \
    --entitlements "$entitlements" "$staging/PRHarbor.app"
codesign --verify --deep --strict --verbose=2 "$staging/PRHarbor.app"

if [[ $notarize == 1 ]]; then
    ditto -c -k --keepParent "$staging/PRHarbor.app" "$staging/PRHarbor.zip"
    notarize_file "$staging/PRHarbor.zip"
    rm "$staging/PRHarbor.zip"
    xcrun stapler staple "$staging/PRHarbor.app"
    spctl --assess --type execute --verbose=2 "$staging/PRHarbor.app"
fi

mkdir "$staging/dmg"
mv "$staging/PRHarbor.app" "$staging/dmg/"
ln -s /Applications "$staging/dmg/Applications"
hdiutil create -volname "PR Harbor" -srcfolder "$staging/dmg" \
    -ov -format UDZO "$output_directory/PRHarbor.dmg"
hdiutil verify "$output_directory/PRHarbor.dmg"
if [[ "$identity" != "-" ]]; then
    codesign --force --sign "$identity" --timestamp "$output_directory/PRHarbor.dmg"
    codesign --verify --verbose=2 "$output_directory/PRHarbor.dmg"
fi
if [[ $notarize == 1 ]]; then
    notarize_file "$output_directory/PRHarbor.dmg"
    xcrun stapler staple "$output_directory/PRHarbor.dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$output_directory/PRHarbor.dmg"
fi
(cd "$output_directory" && shasum -a 256 PRHarbor.dmg > SHA256SUMS)
