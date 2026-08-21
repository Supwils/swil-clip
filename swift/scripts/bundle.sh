#!/usr/bin/env bash
#
# bundle.sh — Build the .app from the SPM package.
#
# There is no .xcodeproj in this repository on purpose (see the spec, §4.1): the
# build has to be reproducible from a clean checkout with no IDE state, so the
# bundle is assembled here rather than by Xcode.
#
# ── Renaming the product ────────────────────────────────────────────────────
# PRODUCT_NAME below is the only place the user-visible name is written. It
# becomes CFBundleName, the .app in Finder, the DMG, and — read back at runtime
# through `Brand` — every name the interface says out loud. Change that one
# line, rebuild, and the rename is done.
#
# BUNDLE_ID and the Application Support directory (SwilClipSwift, set in
# StorageLocations) must NOT follow it. macOS keys the Keychain ACL for the
# encryption key, the UserDefaults domain and the SMAppService login-item
# registration off the bundle id; changing it orphans the key, and without the
# key every encrypted row is unreadable. Neither identifier is ever shown to a
# user, so a rename does not need them to move.
#
# TARGET_NAME is the SPM product and is not user-visible either — it only has
# to match Package.swift.
#
# Usage:
#   bash scripts/bundle.sh              debug, arm64, unsigned  (fast iteration)
#   bash scripts/bundle.sh --release    release, universal, signed with Developer ID
#
set -euo pipefail

SWIFT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SWIFT_ROOT/.." && pwd)"
cd "$SWIFT_ROOT"

log()  { printf '\033[1;34m›\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

PRODUCT_NAME="SwilClip"        # user-visible; the one line a rename touches
TARGET_NAME="SwilClip"         # SPM product name; must match Package.swift
BUNDLE_ID="com.supwilsoft.swilclip.swift"   # frozen — see the header
VERSION="2.0.0"
MIN_MACOS="14.0"

RELEASE=0
[[ "${1:-}" == "--release" ]] && RELEASE=1

# ---------------------------------------------------------------- build -----
if (( RELEASE )); then
  log "Building release (universal: arm64 + x86_64)…"
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$TARGET_NAME"
else
  log "Building debug (host arch)…"
  swift build
  BIN="$(swift build --show-bin-path)/$TARGET_NAME"
fi
[[ -f "$BIN" ]] || fail "no executable at $BIN"

# --------------------------------------------------------------- assemble ---
APP="$SWIFT_ROOT/build/$PRODUCT_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$PRODUCT_NAME"

# LSUIElement is what makes this menu-bar-only: no Dock icon, no ⌘Tab entry.
# The app also calls setActivationPolicy(.accessory) so a bundle-less debug run
# behaves identically.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$PRODUCT_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$PRODUCT_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleExecutable</key>            <string>$PRODUCT_NAME</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>        <string>$MIN_MACOS</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
    <key>NSHumanReadableCopyright</key>      <string>© 2026 SUPWILSOFT LLC. MIT licensed.</string>
</dict>
</plist>
PLIST

# Reuse the v1 icon: same product, same identity.
ICON_SRC="$REPO_ROOT/tauri/src-tauri/icons/icon.icns"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
else
  log "no icon.icns found — bundling without an icon"
fi

printf 'APPL????' > "$APP/Contents/PkgInfo"

# ------------------------------------------------------------------ sign ----
# Entitlements: the hardened runtime blocks Apple Events by default, and
# Auto Paste's synthetic ⌘V needs them. Everything else stays off — a clipboard
# manager has no business asking for more.
ENTITLEMENTS="$SWIFT_ROOT/build/$TARGET_NAME.entitlements"
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENT

IDENTITY="${MACOS_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 \
    | sed -E 's/.*"(.+)"$/\1/')" || true
fi

if (( RELEASE )); then
  [[ -n "$IDENTITY" ]] || fail "release build needs a Developer ID Application certificate"
  log "Signing with: $IDENTITY"
  codesign --force --deep --options runtime --timestamp \
           --entitlements "$ENTITLEMENTS" \
           --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  ok "signed and verified"
else
  # An ad-hoc signature is enough for local runs and — importantly — keeps the
  # Keychain ACL stable between builds. Leaving it unsigned makes macOS treat
  # every rebuild as a different app and re-prompt for key access.
  log "Ad-hoc signing (debug)…"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP" 2>/dev/null \
    || log "ad-hoc signing failed — the app will still run, but may re-prompt for Keychain access"
fi

ok "built $APP"
echo "$APP"
