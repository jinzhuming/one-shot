#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
PROJECT="$ROOT/Shot.xcodeproj/project.pbxproj"
PROJECT_YML="$ROOT/project.yml"
CONFIG_FILE="$ROOT/Support/Shot.xcconfig"
SOURCE_PLIST="$ROOT/Support/Info.plist"
APP="$ROOT/Shot.app"
APP_INFO="$APP/Contents/Info.plist"
BUNDLE_ID="com.jinzhuming.shot"

fail() {
  echo "verify failed: $*" >&2
  exit 1
}

for required in "$PROJECT" "$PROJECT_YML" "$CONFIG_FILE" "$SOURCE_PLIST" "$APP_INFO"; do
  [[ -f "$required" ]] || fail "missing required file: $required"
done
[[ -d "$APP" ]] || fail "missing packaged app: $APP"

grep -q 'RegionEditorController\|WindowEditorController' "$PROJECT" \
  && fail "generated Xcode project contains removed source references" || true
grep -q 'configFiles:' "$PROJECT_YML" \
  || fail "project.yml does not declare the shared build configuration"
grep -q 'Support/Shot.xcconfig' "$PROJECT_YML" \
  || fail "project.yml does not use Support/Shot.xcconfig"

CONFIG_ID="$(sed -nE 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$CONFIG_FILE" | head -n 1)"
MARKETING_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$CONFIG_FILE" | head -n 1)"
BUILD_VERSION="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$CONFIG_FILE" | head -n 1)"
[[ "$CONFIG_ID" == "$BUNDLE_ID" ]] || fail "shared config bundle id is ${CONFIG_ID:-empty}"
[[ -n "$MARKETING_VERSION" && -n "$BUILD_VERSION" ]] \
  || fail "shared config must define marketing and build versions"
grep -q 'baseConfigurationReference .*Shot.xcconfig' "$PROJECT" \
  || fail "generated Xcode project is not linked to the shared build configuration"

plutil -lint "$SOURCE_PLIST" >/dev/null || fail "Support/Info.plist is invalid"
source_paths="$(sed -nE 's/.*path = "?([^";]+\.swift)"?;.*/\1/p' "$PROJECT" | sort -u)"
[[ -n "$source_paths" ]] || fail "generated Xcode project has no Swift source references"
source_files="$(rg --files "$ROOT/Sources" | sed "s#^$ROOT/##")"
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if [[ -f "$ROOT/$path" ]]; then
    continue
  fi
  basename="${path##*/}"
  matches="$(printf '%s\n' "$source_files" | awk -F/ -v name="$basename" '$NF == name { print }')"
  count="$(printf '%s\n' "$matches" | awk 'NF { count++ } END { print count + 0 }')"
  [[ "$count" == 1 ]] || fail "unresolved or ambiguous Xcode source reference: $path"
done <<< "$source_paths"

APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_INFO")"
APP_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_INFO")"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO")"
[[ "$APP_ID" == "$BUNDLE_ID" ]] || fail "packaged bundle id is $APP_ID"
[[ "$APP_EXECUTABLE" == "Shot" ]] || fail "packaged executable is $APP_EXECUTABLE"
[[ "$APP_VERSION" == "$MARKETING_VERSION" ]] \
  || fail "packaged version drift: $APP_VERSION != $MARKETING_VERSION"
[[ "$APP_BUILD" == "$BUILD_VERSION" ]] \
  || fail "packaged build drift: $APP_BUILD != $BUILD_VERSION"
grep -q '\$(' "$APP_INFO" && fail "packaged Info.plist contains unexpanded macros" || true

[[ -d "$APP/Contents/Resources/Shot_Shot.bundle" ]] \
  || fail "Shot_Shot.bundle is missing from the packaged app resources"
[[ -f "$APP/Contents/Resources/Shot_Shot.bundle/Localizable.xcstrings" ]] \
  || fail "packaged localization resource is missing"
[[ -f "$APP/Contents/Resources/Shot.icns" ]] || fail "packaged icon is missing"
[[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ]] || fail "packaged privacy manifest is missing"

codesign --verify --deep --strict "$APP" || fail "packaged signature verification failed"
SIGNED_ID="$(codesign -d --verbose=2 "$APP" 2>&1 | sed -n 's/^Identifier=//p')"
[[ "$SIGNED_ID" == "$BUNDLE_ID" ]] || fail "signed identifier is ${SIGNED_ID:-empty}"
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^.*designated => //p')"
[[ -n "$REQUIREMENT" ]] || fail "signed app has no designated requirement"

echo "Verified Shot ($BUNDLE_ID $APP_VERSION ($APP_BUILD), config=$CONFIG)."
echo "Xcode project, source references, versions, resources, and signature are valid."
