#!/usr/bin/env bash
#
# release-macos.sh — Build, sign, notarize & staple a Universal macOS release.
#
# Reads credentials from .env.release (gitignored). When the APPLE_* variables
# are present, `tauri build` signs with your Developer ID, submits the app to
# Apple's notary service, waits for the result and staples the ticket — so the
# resulting .dmg opens on any Mac with no Gatekeeper warning and no `xattr`.
#
# Usage:  bash scripts/release-macos.sh        (or: pnpm release:mac)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Signing credentials live at the repository root, shared with the Swift build.
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
cd "$ROOT"

log()  { printf '\033[1;34m›\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- Load credentials ------------------------------------------------------
ENV_FILE="${RELEASE_ENV_FILE:-$REPO_ROOT/.env.release}"
if [[ -f "$ENV_FILE" ]]; then
  log "Loading release credentials from $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  log "No $ENV_FILE found — relying on already-exported environment variables."
fi

# --- Required variables ----------------------------------------------------
: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY, e.g. \"Developer ID Application: Your Name (TEAMID)\"}"
: "${APPLE_API_ISSUER:?Set APPLE_API_ISSUER (App Store Connect issuer UUID)}"
: "${APPLE_API_KEY:?Set APPLE_API_KEY (App Store Connect key ID)}"
: "${APPLE_API_KEY_PATH:?Set APPLE_API_KEY_PATH (path to AuthKey_XXXX.p8)}"

# --- Preflight -------------------------------------------------------------
log "Preflight checks"

# 1. Signing identity must exist in the keychain (parens are literal → grep -F).
if ! security find-identity -v -p codesigning | grep -qF "$APPLE_SIGNING_IDENTITY"; then
  fail "Signing identity not found in keychain: $APPLE_SIGNING_IDENTITY
   Inspect with: security find-identity -v -p codesigning"
fi
ok "Signing identity present"

# 2. Notarization key file must exist.
[[ -f "$APPLE_API_KEY_PATH" ]] || fail "API key file not found: $APPLE_API_KEY_PATH"
ok "Notarization API key present"

# 3. Universal build needs the Intel Rust target.
if ! rustup target list --installed 2>/dev/null | grep -q '^x86_64-apple-darwin$'; then
  log "Adding x86_64-apple-darwin Rust target (required for Universal build)…"
  rustup target add x86_64-apple-darwin
fi
ok "Universal build targets ready"

# --- Build (auto signs + notarizes + staples) ------------------------------
BUNDLE_DIR="$ROOT/src-tauri/target/universal-apple-darwin/release/bundle"

# Clear leftovers from previous builds first: Tauri names DMGs with the
# version, so an old SwilClip_x.y.z_universal.dmg would survive next to the
# new one and the artifact lookup below could pick (and validate, and report)
# the wrong release.
rm -rf "$BUNDLE_DIR"

log "Building Universal release — this signs, notarizes and staples (takes a few minutes)…"
pnpm tauri build --target universal-apple-darwin

# --- Locate artifacts ------------------------------------------------------
APP="$(/usr/bin/find "$BUNDLE_DIR/macos" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
DMG="$(/usr/bin/find "$BUNDLE_DIR/dmg"   -maxdepth 1 -name '*.dmg' 2>/dev/null | head -1)"
[[ -n "$APP" ]] || fail "Could not find built .app under $BUNDLE_DIR/macos"

# --- Verify ----------------------------------------------------------------
log "Verifying signature, Gatekeeper acceptance and stapled ticket"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute -vvv "$APP" || \
  fail "Gatekeeper rejected the app — notarization/stapling likely incomplete."
xcrun stapler validate "$APP"
if [[ -n "$DMG" ]]; then
  xcrun stapler validate "$DMG" 2>/dev/null \
    && ok "DMG ticket stapled" \
    || log "DMG itself not stapled (fine — the .app inside is notarized & stapled)."
fi

echo ""
ok "Release ready to distribute:"
echo "    App: $APP"
echo "    DMG: ${DMG:-<not produced>}"
