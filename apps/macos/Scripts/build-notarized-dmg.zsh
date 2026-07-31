#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
macos_root=${script_dir:h}
repo_root=${macos_root:h:h}
output_dir=${OUTPUT_DIR:-"$repo_root/dist"}
signing_identity=${SIGNING_IDENTITY:-}
development_team=${DEVELOPMENT_TEAM:-}
notary_profile=${NOTARY_PROFILE:-}
source_packages_dir=${SOURCE_PACKAGES_DIR:-}

if [[ -z "$signing_identity" ||
      -z "$development_team" ||
      -z "$notary_profile" ]]; then
    print -u2 "SIGNING_IDENTITY, DEVELOPMENT_TEAM, NOTARY_PROFILE이 필요합니다."
    exit 1
fi

for tool in git xcodebuild security codesign hdiutil xcrun shasum ditto; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print -u2 "필요한 명령을 찾을 수 없습니다: $tool"
        exit 1
    fi
done

if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    print -u2 "배포 DMG는 깨끗한 작업 트리에서만 생성합니다."
    exit 1
fi

if ! security find-identity -v -p codesigning |
    grep -F -- "$signing_identity" >/dev/null; then
    print -u2 "키체인에서 서명 인증서를 찾을 수 없습니다: $signing_identity"
    exit 1
fi

if ! xcrun notarytool history \
    --keychain-profile "$notary_profile" >/dev/null; then
    print -u2 "notarytool 키체인 프로필을 사용할 수 없습니다: $notary_profile"
    exit 1
fi

work_dir=$(mktemp -d "${TMPDIR%/}/MonglePetDMG.XXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

archive_path="$work_dir/MonglePet.xcarchive"
package_arguments=()
if [[ -n "$source_packages_dir" ]]; then
    package_arguments=(
        -clonedSourcePackagesDirPath "${source_packages_dir:A}"
        -disableAutomaticPackageResolution
    )
fi

xcodebuild \
    -project "$macos_root/MonglePet.xcodeproj" \
    -scheme MonglePet \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    "${package_arguments[@]}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$signing_identity" \
    DEVELOPMENT_TEAM="$development_team" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    clean archive

app_path="$archive_path/Products/Applications/MonglePet.app"
info_plist="$app_path/Contents/Info.plist"

if [[ ! -d "$app_path" || ! -f "$info_plist" ]]; then
    print -u2 "서명된 Archive 앱을 찾을 수 없습니다: $app_path"
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

signature_details=$(codesign -dvvv "$app_path" 2>&1)
if [[ "$signature_details" != *"runtime"* ]]; then
    print -u2 "Hardened Runtime 서명 플래그를 확인할 수 없습니다."
    exit 1
fi

entitlements=$(codesign -d --entitlements :- "$app_path" 2>&1)
if [[ "$entitlements" != *"com.apple.security.app-sandbox"* ]]; then
    print -u2 "App Sandbox entitlement를 확인할 수 없습니다."
    exit 1
fi
if [[ "$entitlements" == *"com.apple.security.get-task-allow"* ]]; then
    print -u2 "배포 앱에 get-task-allow entitlement가 포함되어 있습니다."
    exit 1
fi

version=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
commit=$(git -C "$repo_root" rev-parse HEAD)
artifact_base="MonglePet-${version}-build.${build}"

mkdir -p "$output_dir"
output_dir=${output_dir:A}
dmg_path="$output_dir/${artifact_base}.dmg"
checksum_path="$dmg_path.sha256"
notary_output="$output_dir/${artifact_base}.notary.txt"
entitlements_path="$output_dir/${artifact_base}.entitlements.plist"
manifest_path="$output_dir/${artifact_base}.manifest.txt"

for output_path in \
    "$dmg_path" \
    "$checksum_path" \
    "$notary_output" \
    "$entitlements_path" \
    "$manifest_path"; do
    if [[ -e "$output_path" ]]; then
        print -u2 "기존 파일을 덮어쓰지 않습니다: $output_path"
        exit 1
    fi
done

print -r -- "$entitlements" > "$entitlements_path"

staging_dir="$work_dir/dmg-root"
mkdir -p "$staging_dir"
ditto "$app_path" "$staging_dir/MonglePet.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "MonglePet ${version}" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    "$dmg_path"

codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait | tee "$notary_output"

xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
hdiutil verify "$dmg_path"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$dmg_path"

(
    cd "$output_dir"
    shasum -a 256 "${artifact_base}.dmg"
) > "$checksum_path"
(
    cd "$output_dir"
    shasum -a 256 -c "${artifact_base}.dmg.sha256"
)

{
    print "product=MonglePet"
    print "channel=developer-id"
    print "signed=yes"
    print "notarized=yes"
    print "version=$version"
    print "build=$build"
    print "commit=$commit"
    print "identity=$signing_identity"
    print "team=$development_team"
    print "xcode=$(xcodebuild -version | tr '\n' ' ')"
    print "macos=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
} > "$manifest_path"

print "공증된 DMG 생성 완료:"
print "  $dmg_path"
print "  $checksum_path"
print "  $notary_output"
print "  $entitlements_path"
print "  $manifest_path"
