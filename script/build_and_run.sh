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
  /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
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

- Ad-hoc signed for local distribution and testing
- Not notarized yet
- Planned GitHub Releases / Sparkle distribution path
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
    "signing": "ad-hoc",
    "notarized": false,
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

  stage_dir="$(mktemp -d)"
  cp -R "$APP_BUNDLE" "$stage_dir/$APP_NAME.app"
  ln -s /Applications "$stage_dir/Applications"
  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$stage_dir" \
    -format UDZO \
    "$dmg_path" >/dev/null
  rm -rf "$stage_dir"

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
