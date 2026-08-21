# Releasing SwilClip — signed & notarized macOS build

This guide makes SwilClip downloadable so that **anyone can double-click the
`.dmg`, drag the app to Applications, and open it with no warning** — no
"damaged" dialog, no `xattr -cr` workaround.

For a Mac app distributed **outside the App Store**, three things must be true:

1. The app and DMG are **code-signed** with a *Developer ID Application* certificate.
2. **Hardened Runtime** is enabled (Tauri does this by default).
3. The app is **notarized** by Apple and the ticket is **stapled** into it.

**Parts A and B below are the one-time setup**, and are the part only you can do:
they need your Apple ID and your paid Apple Developer Program membership. Do them
once; everything after is a single command.

---

## The Swift app (current)

```bash
cd swift
bash scripts/release.sh
```

That gate-runs `swift test`, builds a universal binary, signs it with your
Developer ID, notarizes and staples **both the app and the disk image**, then
verifies the result the way Gatekeeper will. Output lands in
`swift/build/dist/`.

Both artefacts are stapled rather than just the image: the ticket travels with
whatever it is attached to, so a stapled DMG alone would leave the app
unverifiable once dragged out of it on a machine that happens to be offline.

**For local iteration, skip notarization.** `bash scripts/bundle.sh --release`
takes about 13 seconds and produces a Developer ID–signed app — enough for the
Keychain ACL to recognise it, which a **debug build is not**: an ad-hoc signature
does not match the ACL on the encryption key, so a debug build stops at a
password prompt and cannot read the history. Notarization only matters for
someone else's Mac.

Renaming the product is `PRODUCT_NAME` in `scripts/bundle.sh` and a rebuild. The
bundle identifier and data directory must not follow it — see `CLAUDE.md` §7.

## The Tauri app (frozen at v0.1.3)

`pnpm tauri build` does (1), (2) and (3) automatically once the credentials are
in place; `tauri/scripts/release-macos.sh` wraps it. Kept for reference — the
tree is frozen and is not expected to ship again.

---

## Part A — One-time Apple setup (interactive)

### A1. Create the *Developer ID Application* certificate

Easiest path, since Xcode is already installed:

1. Open **Xcode → Settings (⌘,) → Accounts**.
2. Add your Apple ID (the one in the Apple Developer Program) and select your Team.
3. Click **Manage Certificates…** → the **+** button → **Developer ID Application**.

That creates the certificate **and its private key** in your login keychain.
Verify:

```bash
security find-identity -v -p codesigning
```

You should see a line like:

```
1) ABCD... "Developer ID Application: Your Name (TEAMID)"
```

Copy that quoted string verbatim — it becomes `APPLE_SIGNING_IDENTITY`.

> A *free* Apple ID cannot create Developer ID certificates. The paid
> Apple Developer Program membership (which you have) is required.
> "Apple Development" / "Apple Distribution" certificates are **not** the right
> ones for this — they're for the App Store / local testing.

### A2. Create an App Store Connect API key (for notarization)

1. Go to **appstoreconnect.apple.com → Users and Access → Integrations**
   (the **App Store Connect API** section).
2. Click **+** to generate a key. Name it e.g. `Notarization`. Role: **Developer**.
3. **Download the `AuthKey_XXXXXXXXXX.p8` file — you can only download it once.**
4. Note two IDs:
   - **Key ID** — the `XXXXXXXXXX` part → `APPLE_API_KEY`
   - **Issuer ID** — the UUID at the top of the Keys page → `APPLE_API_ISSUER`

Store the key somewhere stable, e.g.:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
```

---

## Part B — Local machine setup (once per machine)

```bash
cp .env.release.example .env.release
# then edit .env.release and fill in the 4 values from Part A
```

Add the Intel Rust target so we can build a Universal (Apple Silicon + Intel)
binary (the release script also does this automatically if missing):

```bash
rustup target add x86_64-apple-darwin
```

---

## Part C — Build a release

```bash
pnpm release:mac        # = bash scripts/release-macos.sh
```

This runs `pnpm tauri build --target universal-apple-darwin`, which:
signs with your Developer ID → submits to Apple's notary service → waits →
staples the ticket. Notarization is a network round-trip, so it takes a few
minutes. The script then verifies the result.

Output:

```
src-tauri/target/universal-apple-darwin/release/bundle/dmg/SwilClip_<version>_universal.dmg
```

---

## Part D — Verify before publishing

The release script runs these for you, but to check by hand:

```bash
APP="src-tauri/target/universal-apple-darwin/release/bundle/macos/SwilClip.app"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute -vvv "$APP"   # expect: accepted, source=Notarized Developer ID
xcrun stapler validate "$APP"               # expect: The validate action worked!
```

---

## Part E — Distribute

Upload the `.dmg` to your GitHub Releases page (or your website). Users:
double-click the DMG → drag **SwilClip** to **Applications** → open it.
No warning, no `xattr`.

---

## Troubleshooting

- **Signing fails / identity not found** — the `APPLE_SIGNING_IDENTITY` string
  must match `security find-identity -v -p codesigning` exactly (including the
  `(TEAMID)`).
- **Notarization returns `Invalid`** — get the detailed log:
  ```bash
  xcrun notarytool log <submission-id> \
    --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER"
  ```
  Common causes: a nested binary missing hardened runtime or signature (Tauri
  handles its own binaries, so this is rare for a stock build).
- **Alternative credential method (Apple ID instead of API key)** — set
  `APPLE_ID`, `APPLE_PASSWORD` (an app-specific password from
  appleid.apple.com) and `APPLE_TEAM_ID` instead of the three `APPLE_API_*`
  variables. The API-key method is preferred (more stable, no password).
