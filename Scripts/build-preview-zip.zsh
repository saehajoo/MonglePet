#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
output_dir=${OUTPUT_DIR:-"$repo_root/dist"}
source_packages_dir=${SOURCE_PACKAGES_DIR:-}

for tool in git xcodebuild ditto shasum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print -u2 "필요한 명령을 찾을 수 없습니다: $tool"
        exit 1
    fi
done

if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    print -u2 "작업 트리가 깨끗하지 않습니다. 먼저 변경을 검토하고 커밋하세요."
    exit 1
fi

work_dir=$(mktemp -d "${TMPDIR%/}/MonglePetPreview.XXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

derived_data="$work_dir/DerivedData"
package_arguments=()
if [[ -n "$source_packages_dir" ]]; then
    package_arguments=(
        -clonedSourcePackagesDirPath "${source_packages_dir:A}"
        -disableAutomaticPackageResolution
    )
fi

xcodebuild \
    -project "$repo_root/MonglePet.xcodeproj" \
    -scheme MonglePet \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    "${package_arguments[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    build

app_path="$derived_data/Build/Products/Release/MonglePet.app"
info_plist="$app_path/Contents/Info.plist"

if [[ ! -d "$app_path" || ! -f "$info_plist" ]]; then
    print -u2 "Release 앱을 찾을 수 없습니다: $app_path"
    exit 1
fi

version=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
commit=$(git -C "$repo_root" rev-parse HEAD)
artifact_base="MonglePet-${version}-build.${build}-preview"

mkdir -p "$output_dir"
output_dir=${output_dir:A}
zip_path="$output_dir/${artifact_base}.zip"
checksum_path="$zip_path.sha256"
manifest_path="$output_dir/${artifact_base}.manifest.txt"

for output_path in "$zip_path" "$checksum_path" "$manifest_path"; do
    if [[ -e "$output_path" ]]; then
        print -u2 "기존 파일을 덮어쓰지 않습니다: $output_path"
        exit 1
    fi
done

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
(
    cd "$output_dir"
    shasum -a 256 "${artifact_base}.zip"
) > "$checksum_path"

{
    print "product=MonglePet"
    print "channel=preview"
    print "signed=no"
    print "notarized=no"
    print "version=$version"
    print "build=$build"
    print "commit=$commit"
    print "xcode=$(xcodebuild -version | tr '\n' ' ')"
    print "macos=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
} > "$manifest_path"

(
    cd "$output_dir"
    shasum -a 256 -c "${artifact_base}.zip.sha256"
)

print "Preview ZIP 생성 완료:"
print "  $zip_path"
print "  $checksum_path"
print "  $manifest_path"
