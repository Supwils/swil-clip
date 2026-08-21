#!/usr/bin/env bash
#
# release.sh — Build, sign, notarize, staple and package the app for distribution.
#
# `bundle.sh --release` produces a signed .app, which runs fine on this machine.
# It will *not* open cleanly on anyone else's: Gatekeeper refuses a Developer ID
# binary it has never seen unless Apple has notarized it. This script closes that
# gap, so the artefact is one someone can download and double-click.
#
# Both the .app and the .dmg are notarized and stapled. Stapling the disk image
# alone would leave the app unverifiable once dragged out of it on a machine
# that happens to be offline — the ticket travels with whatever it is attached
# to, so attach it to both.
#
# Credentials come from .env.release at the repository root (gitignored), shared
# with the frozen Tauri build:
#   APPLE_SIGNING_IDENTITY   "Developer ID Application: Name (TEAMID)"
#   APPLE_API_ISSUER         App Store Connect issuer UUID
#   APPLE_API_KEY            App Store Connect key ID
#   APPLE_API_KEY_PATH       path to AuthKey_XXXX.p8
#
# An API key rather than an app-specific password: it needs no interaction and
# no password in the environment, so this runs unattended.
#
# Usage:  bash scripts/release.sh
#
set -euo pipefail

SWIFT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SWIFT_ROOT/.." && pwd)"
cd "$SWIFT_ROOT"

log()  { printf '\033[1;34m›\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# The product name is not written here: bundle.sh owns it (see its header) and
# prints the bundle it produced as its last line. Reconstructing the path from a
# second copy of the name is exactly how a rename half-lands.
BUILD="$SWIFT_ROOT/build"
DIST="$BUILD/dist"

# --- Credentials -----------------------------------------------------------
ENV_FILE="${RELEASE_ENV_FILE:-$REPO_ROOT/.env.release}"
if [[ -f "$ENV_FILE" ]]; then
  log "Loading release credentials from $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY}"
: "${APPLE_API_ISSUER:?Set APPLE_API_ISSUER (App Store Connect issuer UUID)}"
: "${APPLE_API_KEY:?Set APPLE_API_KEY (App Store Connect key ID)}"
: "${APPLE_API_KEY_PATH:?Set APPLE_API_KEY_PATH (path to AuthKey_XXXX.p8)}"
[[ -f "$APPLE_API_KEY_PATH" ]] || fail "API key not found: $APPLE_API_KEY_PATH"
security find-identity -v -p codesigning | grep -qF "$APPLE_SIGNING_IDENTITY" \
  || fail "Signing identity not in keychain: $APPLE_SIGNING_IDENTITY"

NOTARY=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")

# --- Gate ------------------------------------------------------------------
# A release that fails its own tests is not a release. Cheap here: the suite is
# headless and runs in a fraction of a second.
log "Running the test suite…"
swift test >/dev/null || fail "tests failed — refusing to release"
ok "tests pass"

# --- Build and sign --------------------------------------------------------
log "Building signed universal app…"
APP="$(MACOS_SIGN_IDENTITY="$APPLE_SIGNING_IDENTITY" \
       bash "$SWIFT_ROOT/scripts/bundle.sh" --release | tail -1)"
[[ -d "$APP" ]] || fail "no app bundle at ${APP:-<none>}"
APP_NAME="$(basename "$APP" .app)"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ok "built $APP_NAME $VERSION ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"

rm -rf "$DIST" && mkdir -p "$DIST"

# --- Notarize the app ------------------------------------------------------
# notarytool takes an archive, not a bundle. `ditto -c -k --keepParent` is the
# form Apple documents: it preserves symlinks, resource forks and the enclosing
# directory, none of which `zip` does correctly for a .app.
ZIP="$DIST/$APP_NAME-$VERSION.zip"
log "Archiving for notarization…"
ditto -c -k --keepParent "$APP" "$ZIP"

log "Submitting the app to Apple (this usually takes a few minutes)…"
xcrun notarytool submit "$ZIP" "${NOTARY[@]}" --wait \
  || fail "app notarization failed — run: xcrun notarytool log <id> ${NOTARY[*]}"

log "Stapling the ticket to the app…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP" || fail "stapled ticket did not validate"
ok "app notarized and stapled"

# --- Disk image ------------------------------------------------------------
# Built *after* stapling so the app inside already carries its ticket.
DMG="$DIST/${APP_NAME}_${VERSION}_universal.dmg"
STAGE="$DIST/stage"
log "Building disk image…"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format ULFO "$DMG" >/dev/null
rm -rf "$STAGE"

log "Signing the disk image…"
codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$DMG"

log "Submitting the disk image to Apple…"
xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait \
  || fail "dmg notarization failed"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG" || fail "stapled dmg ticket did not validate"
ok "disk image notarized and stapled"

# --- Verify the way a stranger's Mac will -----------------------------------
# `spctl --assess` is Gatekeeper's own check. If this passes, the app opens with
# no warning on a machine that has never seen it.
log "Verifying as Gatekeeper would…"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

rm -f "$ZIP"
echo
ok "release ready"
printf '    %s\n' "$DMG"
printf '    %s\n' "$(du -h "$DMG" | cut -f1) · universal · notarized · stapled"
