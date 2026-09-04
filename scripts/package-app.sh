#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
BIN_PATH="$(cd "$ROOT" && swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_PATH/Shot"
APP="$ROOT/Shot.app"
PLIST="$ROOT/Support/Info.plist"
ICON="$ROOT/Support/Shot.icns"
PRIVACY="$ROOT/Sources/Shot/PrivacyInfo.xcprivacy"
if [[ ! -f "$PRIVACY" ]]; then
  PRIVACY="$ROOT/Support/PrivacyInfo.xcprivacy"
fi
CONFIG_FILE="$ROOT/Support/Shot.xcconfig"
RESOURCE_BUNDLE="$BIN_PATH/Shot_Shot.bundle"
ENTITLEMENTS="$ROOT/Shot.entitlements"

read_config_value() {
  local key="$1"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$CONFIG_FILE" \
    | sed 's/[[:space:]]*\/\/.*$//' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | head -n 1
}

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing shared build config at $CONFIG_FILE." >&2
  exit 1
fi

BUNDLE_ID="$(read_config_value PRODUCT_BUNDLE_IDENTIFIER)"
MARKETING_VERSION="$(read_config_value MARKETING_VERSION)"
BUILD_VERSION="$(read_config_value CURRENT_PROJECT_VERSION)"
if [[ -z "$BUNDLE_ID" || -z "$MARKETING_VERSION" || -z "$BUILD_VERSION" ]]; then
  echo "Support/Shot.xcconfig must define PRODUCT_BUNDLE_IDENTIFIER, MARKETING_VERSION, and CURRENT_PROJECT_VERSION." >&2
  exit 1
fi

if [[ ! -x "$BIN" ]]; then
  echo "Missing binary at $BIN. Run: swift build -c $CONFIG" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SwiftPM resource bundle at $RESOURCE_BUNDLE. Run: swift build -c $CONFIG" >&2
  exit 1
fi

resolve_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return
  fi
  local identities identity
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  identity="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return
  fi
  identity="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -n 1)"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return
  fi
  printf '%s\n' "-"
}

IDENTITY="$(resolve_identity)"
if [[ "$CONFIG" == "release" && "$IDENTITY" != "Developer ID Application:"* ]]; then
  echo "Release packaging requires a Developer ID Application signing identity." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shot"
cp "$PLIST" "$APP/Contents/Info.plist"

# Support/Info.plist is also consumed by Xcode, so expand its build settings
# explicitly for the SPM-created app before signing it.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Shot" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Shot" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP/Contents/Resources/Shot.icns"
fi
if [[ -f "$PRIVACY" ]]; then
  cp "$PRIVACY" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
fi
# A macOS application can only seal resources under Contents. Keep the
# generated SwiftPM bundle there so the final app remains codesign-valid.
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

SIGN_ARGS=(
  --force
  --sign "$IDENTITY"
  --identifier "$BUNDLE_ID"
  --options runtime
)
if [[ -f "$ENTITLEMENTS" ]]; then
  SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
fi
if [[ "$IDENTITY" != "-" && "$CONFIG" == "release" ]]; then
  SIGN_ARGS+=(--timestamp)
fi

codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

if grep -q '\$(' "$APP/Contents/Info.plist"; then
  echo "Packaged Info.plist contains unexpanded macros." >&2
  exit 1
fi

SIGNED_ID="$(codesign -d --verbose=2 "$APP" 2>&1 | sed -n 's/^Identifier=//p')"
if [[ "$SIGNED_ID" != "$BUNDLE_ID" ]]; then
  echo "codesign identifier must be $BUNDLE_ID (got ${SIGNED_ID:-empty})." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^.*designated => //p')"
echo "Created $APP ($BUNDLE_ID $VERSION ($BUILD))"
echo "Signed with $IDENTITY"
echo "TCC requirement: $REQUIREMENT"
if [[ "$IDENTITY" == "-" ]]; then
  echo "warning: ad-hoc signature changes every build; Screen Recording permission will reset." >&2
fi
