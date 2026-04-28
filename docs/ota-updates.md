# Docky OTA Updates

Docky uses Sparkle 2 for direct-distribution updates.

## Configured URLs and Keys

- Appcast URL: `https://docky.quintero.gt/appcast.xml`
- Sparkle public key: `LfZUqraK4HiOj/+9iztgnWzdQTrC1ccmJPp/Fy/aTPc=`

The corresponding private key was generated with Sparkle's `generate_keys` tool and stored in this Mac's login keychain.

## One-time Setup

1. Create a `notarytool` keychain profile if you want the release script to notarize automatically.
2. Make sure `https://docky.quintero.gt/` can host static files over HTTPS.
3. Keep the Sparkle private key on a trusted machine only.

Example `notarytool` setup:

```bash
xcrun notarytool store-credentials "DockyNotary" \
  --apple-id "<apple-id>" \
  --team-id "2KC3797KP9" \
  --password "<app-specific-password>"
```

## Publishing a Release

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in Xcode.
2. Write release notes in a markdown file, for example `build/release-notes.md`.
3. Run:

```bash
chmod +x scripts/release_sparkle_update.sh
NOTARYTOOL_PROFILE=DockyNotary \
MARKETING_VERSION=1.0.1 \
BUILD_VERSION=202604281800 \
RELEASE_NOTES_FILE=build/release-notes.md \
scripts/release_sparkle_update.sh
```

4. Upload every file from `build/updates/` to `https://docky.quintero.gt/` and replace the starter `appcast.xml` there.

Generated output includes:

- `Docky-<version>-<build>.zip`
- optional matching `Docky-<version>-<build>.md` release notes
- `appcast.xml`
- Sparkle delta files when applicable

## Testing

1. Install an older Docky build locally.
2. Publish a newer build to the appcast.
3. Launch Docky twice.
4. Use `Check for Updates…` from the app menu or wait for Sparkle's automatic schedule.

If Sparkle does not detect the update, clear the last-check timestamp:

```bash
defaults delete gt.quintero.Docky SULastCheckTime
```

## Notes

- Sparkle stores user update preferences in `UserDefaults`; Docky does not duplicate them.
- Sparkle's `generate_appcast` tool signs update metadata using the private key in your keychain.
- Keep the private key safe. If you need to move it to another Mac, export/import it using Sparkle's key tools.
