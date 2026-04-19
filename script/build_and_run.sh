#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SmartControl"
BUNDLE_ID="com.codex.SmartControl"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
ICON_FILE="$APP_RESOURCES/AppIcon.icns"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_FILE="$ROOT_DIR/BUILD_NUMBER"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(tr -d '[:space:]' < "$BUILD_FILE")}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-1}"
NOTARIZE="${NOTARIZE:-0}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

build_binary() {
  python3 "$ROOT_DIR/script/generate_app_icon.py"
  swift build >&2
  swift build --show-bin-path
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

sign_app_bundle() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    local args=(
      --force
      --deep
      --sign "$SIGNING_IDENTITY"
    )

    if [[ "$ENABLE_HARDENED_RUNTIME" == "1" ]]; then
      args+=(--options runtime)
    fi

    /usr/bin/codesign "${args[@]}" "$APP_BUNDLE"
  else
    /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
  fi
}

notarization_requested() {
  [[ "$NOTARIZE" == "1" ]]
}

require_notarization_credentials() {
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "NOTARIZE=1 requires SIGNING_IDENTITY to be set to a Developer ID Application certificate." >&2
    exit 1
  fi

  if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_APP_SPECIFIC_PASSWORD" ]]; then
    echo "NOTARIZE=1 requires APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD." >&2
    exit 1
  fi
}

notarize_artifact() {
  local artifact_path="$1"
  require_notarization_credentials

  xcrun notarytool submit \
    "$artifact_path" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
}

staple_artifact() {
  local artifact_path="$1"
  xcrun stapler staple "$artifact_path" >/dev/null
}

create_app_bundle() {
  local build_bin_path
  build_bin_path="$(build_binary)"
  local source_binary="$build_bin_path/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$source_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
  write_info_plist
  sign_app_bundle
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

write_release_notes_template() {
  local target_dir="$1"
  cat >"$target_dir/RELEASE_NOTES_TEMPLATE.md" <<EOF
# SmartControl $APP_VERSION

## Highlights

- 

## Notes

- Signing: ${SIGNING_IDENTITY:-ad-hoc}
- Notarized: $(notarization_requested && printf 'yes' || printf 'no')
- GitHub Releases artifact set produced by \`./script/build_and_run.sh --package\`
EOF
}

write_release_manifest() {
  local target_dir="$1"
  local zip_name="$2"
  local dmg_name="$3"
  cat >"$target_dir/release-manifest.json" <<EOF
{
  "appName": "$APP_NAME",
  "bundleIdentifier": "$BUNDLE_ID",
  "version": "$APP_VERSION",
  "buildNumber": "$BUILD_NUMBER",
  "artifacts": {
    "zip": "$zip_name",
    "dmg": "$dmg_name"
  },
  "distributionNotes": {
    "signing": "${SIGNING_IDENTITY:-ad-hoc}",
    "notarized": $(notarization_requested && printf 'true' || printf 'false'),
    "sparkleReady": false
  }
}
EOF
}

package_release() {
  create_app_bundle

  local release_path="$RELEASE_DIR/$APP_VERSION"
  local zip_name="$APP_NAME-$APP_VERSION.zip"
  local dmg_name="$APP_NAME-$APP_VERSION.dmg"
  local zip_path="$release_path/$zip_name"
  local dmg_path="$release_path/$dmg_name"
  local stage_dir

  rm -rf "$release_path"
  mkdir -p "$release_path"

  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$zip_path"

  if notarization_requested; then
    notarize_artifact "$zip_path"
    staple_artifact "$APP_BUNDLE"
    rm -f "$zip_path"
    /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$zip_path"
  fi

  stage_dir="$(mktemp -d)"
  cp -R "$APP_BUNDLE" "$stage_dir/$APP_NAME.app"
  ln -s /Applications "$stage_dir/Applications"
  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$stage_dir" \
    -format UDZO \
    "$dmg_path" >/dev/null
  rm -rf "$stage_dir"

  if notarization_requested; then
    notarize_artifact "$dmg_path"
    staple_artifact "$dmg_path"
  fi

  /usr/bin/shasum -a 256 "$zip_path" > "$zip_path.sha256"
  /usr/bin/shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
  write_release_notes_template "$release_path"
  write_release_manifest "$release_path" "$zip_name" "$dmg_name"

  echo "Created release artifacts:"
  echo "  $zip_path"
  echo "  $dmg_path"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

case "$MODE" in
  run)
    create_app_bundle
    open_app
    ;;
  --debug|debug)
    create_app_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    create_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    create_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    create_app_bundle
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package|--release|release)
    package_release
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
