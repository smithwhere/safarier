#!/bin/bash
# Sign an archive for registered devices using an Apple Distribution identity.
set -euo pipefail
umask 077

: "${IOS_CERTIFICATE_P12_BASE64:?Missing IOS_CERTIFICATE_P12_BASE64}"
: "${IOS_CERTIFICATE_PASSWORD:?Missing IOS_CERTIFICATE_PASSWORD}"
: "${IOS_PROVISIONING_PROFILE_BASE64:?Missing IOS_PROVISIONING_PROFILE_BASE64}"
: "${RUNNER_TEMP:?RUNNER_TEMP must point to a temporary directory}"

work_dir=$(mktemp -d "$RUNNER_TEMP/safarier-signing.XXXXXX")
keychain="$work_dir/signing.keychain-db"
keychain_password=$(openssl rand -hex 24)
profile_install=''
cleanup() {
  if [[ -n "$profile_install" ]]; then rm -f "$profile_install"; fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

printf '%s' "$IOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$work_dir/certificate.p12"
printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$work_dir/profile.mobileprovision"
security cms -D -i "$work_dir/profile.mobileprovision" > "$work_dir/profile.plist"

# Fail before using the signing identity if the profile is not a usable,
# explicit Ad Hoc profile. Do not print device IDs or the profile itself.
python3 - "$work_dir/profile.plist" "$work_dir/metadata" <<'PY'
import datetime, pathlib, plistlib, sys
with open(sys.argv[1], 'rb') as f:
    p = plistlib.load(f)
ent = p.get('Entitlements', {})
team = p.get('TeamIdentifier', [])
app_id = ent.get('application-identifier', '')
expiration = p.get('ExpirationDate')
if (len(team) != 1 or not app_id.startswith(team[0] + '.') or '*' in app_id
    or not p.get('ProvisionedDevices') or p.get('ProvisionsAllDevices')
    or ent.get('get-task-allow', False) or not expiration
    or expiration <= datetime.datetime.utcnow()):
    raise SystemExit('Expected an unexpired Ad Hoc profile with an explicit App ID and registered devices.')
bundle = app_id[len(team[0]) + 1:]
if not bundle or not p.get('UUID'):
    raise SystemExit('The provisioning profile is missing a bundle identifier or UUID.')
pathlib.Path(sys.argv[2]).write_text('\n'.join((team[0], bundle, p['UUID'])) + '\n')
PY
team_id=$(sed -n '1p' "$work_dir/metadata")
bundle_id=$(sed -n '2p' "$work_dir/metadata")
profile_uuid=$(sed -n '3p' "$work_dir/metadata")

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work_dir/certificate.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
if ! security find-identity -v -p codesigning "$keychain" | grep -q 'Apple Distribution:'; then
  echo 'No Apple Distribution signing identity with a private key was found.' >&2
  exit 1
fi

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
profile_install="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
if [[ -e "$profile_install" ]]; then
  echo 'A profile with the same UUID already exists; refusing to overwrite it.' >&2
  profile_install=''
  exit 1
fi
cp "$work_dir/profile.mobileprovision" "$profile_install"

python3 - "$work_dir/export.plist" "$team_id" "$bundle_id" "$profile_uuid" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'method': 'ad-hoc', 'signingStyle': 'manual', 'teamID': sys.argv[2],
                   'provisioningProfiles': {sys.argv[3]: sys.argv[4]}}, f)
PY

xcodegen generate --spec iOS/project.yml
mkdir -p build/ios-signed
xcodebuild -project iOS/SafarierIOS.xcodeproj -scheme SafarierIOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/ios-signed/SafarierIOS.xcarchive" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
  DEVELOPMENT_TEAM="$team_id" PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" archive
xcodebuild -exportArchive -archivePath "$PWD/build/ios-signed/SafarierIOS.xcarchive" \
  -exportOptionsPlist "$work_dir/export.plist" -exportPath "$PWD/build/ios-signed/export"

ipa="$PWD/build/ios-signed/export/SafarierIOS.ipa"
[[ -f "$ipa" ]] || { echo 'IPA export not found.' >&2; exit 1; }
mkdir -p "$work_dir/verify"
unzip -q "$ipa" -d "$work_dir/verify"
app="$work_dir/verify/Payload/SafarierIOS.app"
codesign --verify --deep --strict "$app"
actual_bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
[[ "$actual_bundle" == "$bundle_id" ]] || { echo 'Exported bundle identifier mismatch.' >&2; exit 1; }
security cms -D -i "$app/embedded.mobileprovision" > "$work_dir/exported-profile.plist"
actual_profile=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$work_dir/exported-profile.plist")
[[ "$actual_profile" == "$profile_uuid" ]] || { echo 'Exported provisioning profile mismatch.' >&2; exit 1; }
shasum -a 256 "$ipa" > "$PWD/build/ios-signed/export/SHA256SUMS.txt"
echo 'Signed IPA verified; eligible for devices registered in its Ad Hoc profile.'
