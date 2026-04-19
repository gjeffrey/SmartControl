# Releasing SmartControl

SmartControl now has a practical path from local packaging to GitHub Releases.

## Local Packaging

For a local release candidate:

```bash
./script/build_and_run.sh --package
```

That produces:

- `SmartControl-<version>.zip`
- `SmartControl-<version>.dmg`
- checksum files
- a release notes template
- a simple release manifest

Artifacts land in `dist/release/<version>/`.

## GitHub Actions Release Flow

The repository includes `.github/workflows/release.yml`.

It does two useful things:

- on `workflow_dispatch`, it builds and uploads release artifacts
- on a `v*` tag push, it also publishes a GitHub Release and attaches the packaged artifacts

Example:

```bash
git tag v0.1.1
git push origin v0.1.1
```

That tag name becomes the packaged app version.

## Optional Signing And Notarization

The packaging script stays friendly for local work:

- with no signing credentials, it ad-hoc signs the app for local testing
- with Developer ID credentials, it can sign properly
- with notarization credentials too, it can notarize and staple the app artifacts

The release workflow looks for these GitHub secrets:

- `APPLE_DEVELOPER_ID_P12`
  Base64-encoded `.p12` containing the Developer ID Application certificate.
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
  Password for that `.p12`.
- `APPLE_DEVELOPER_ID_APPLICATION`
  The codesign identity name, for example `Developer ID Application: Your Name (TEAMID)`.
- `APPLE_ID`
  Apple ID used for notarization.
- `APPLE_TEAM_ID`
  Apple Developer team identifier.
- `APPLE_APP_SPECIFIC_PASSWORD`
  App-specific password for notarization with `notarytool`.

If all notarization secrets are present, the workflow sets `NOTARIZE=1` and the script will:

1. sign the app with the supplied Developer ID identity
2. notarize the ZIP
3. staple the app bundle
4. rebuild the ZIP from the stapled app
5. build the DMG
6. notarize and staple the DMG

## Manual Signing / Notarization

You can also drive this locally:

```bash
SIGNING_IDENTITY="Developer ID Application: Example Corp (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_SPECIFIC_PASSWORD="app-specific-password" \
NOTARIZE=1 \
./script/build_and_run.sh --package
```

Without `NOTARIZE=1`, the script will still produce signed artifacts if `SIGNING_IDENTITY` is set.

## Caveats

- This workflow assumes a fairly simple SwiftPM app bundle with no nested helper tools.
- Sparkle should wait until signed, notarized GitHub release artifacts are routine and stable.
- If notarization fails, treat that as distribution plumbing work, not as a product bug.
