#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Shot.xcodeproj/project.pbxproj"
PLIST="$ROOT/Support/Info.plist"

if [[ ! -f "$PROJECT" ]]; then
  echo "Missing generated Xcode project. Run: make generate" >&2
  exit 1
fi

if grep -Eq 'RegionEditorController|WindowEditorController' "$PROJECT"; then
  echo "Generated Xcode project contains stale editor source references." >&2
  exit 1
fi

for required in "ShotApp.swift" "CaptureService.swift" "AnnotationDocument.swift" "Localizable.xcstrings" "PrivacyInfo.xcprivacy" "Assets.xcassets" "Shot.icns"; do
  if ! grep -q "$required" "$PROJECT"; then
    echo "Generated Xcode project is missing $required." >&2
    exit 1
  fi
done

if ! grep -q 'PBXResourcesBuildPhase' "$PROJECT"; then
  echo "Generated Xcode project has no resources build phase." >&2
  exit 1
fi

if ! plutil -lint "$PLIST" >/dev/null; then
  echo "Support/Info.plist is invalid." >&2
  exit 1
fi

for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion LSUIElement LSMinimumSystemVersion; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null
done

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")" == '$(EXECUTABLE_NAME)' ]] \
  || { echo "Support/Info.plist must keep CFBundleExecutable as an Xcode template value." >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == '$(PRODUCT_BUNDLE_IDENTIFIER)' ]] \
  || { echo "Support/Info.plist must keep CFBundleIdentifier as an Xcode template value." >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")" == '$(PRODUCT_NAME)' ]] \
  || { echo "Support/Info.plist must keep CFBundleName as an Xcode template value." >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == '$(MARKETING_VERSION)' ]] \
  || { echo "Support/Info.plist must keep CFBundleShortVersionString as an Xcode template value." >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" == '$(CURRENT_PROJECT_VERSION)' ]] \
  || { echo "Support/Info.plist must keep CFBundleVersion as an Xcode template value." >&2; exit 1; }

echo "Xcode project and source plist are valid."
