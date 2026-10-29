# Preparing a release

This repository is prepared for source publication and an **early-access** macOS app release. Creating archives locally does not publish them.

## Local preparation

```sh
bash scripts/swift-tool.sh test
bash scripts/prepare-release.sh
```

The release script audits the source selection, builds an optimized app, verifies its signature/resources and architecture, and creates versioned app/source ZIP files with `SHA256SUMS` under `dist/`. Source selection is explicit: local DMGs, downloaded runtimes, game files, logs, caches and build directories are excluded. The original graphics diagnostic and branding assets are intentionally included with their source/notices.

The app ZIP contains only Good Gameble Games, its icon, original diagnostic and license notices. It must never include Apple's evaluation environment or a Wine/game distribution.

## Version and review

Update `scripts/Info.plist`, `README.md` and `CHANGELOG.md` together. Keep `CFBundleShortVersionString` numeric and increase `CFBundleVersion`. Before publishing, review the generated source ZIP, verify the listed checksums, and launch the packaged app on a clean user profile.

Check runtime setup, environment creation, installer selection, library persistence, Play and error recovery. Check the Dock/Finder/About icon. Confirm that diagnostic details are optional and that no private library or developer paths have entered the source selection.

DX12 has a manual setup requirement in this release; do not describe it as one-click installation or claim general AAA compatibility. Unknown Witcher executable hashes must remain unsupported by the workaround.

## Signing

The default app is **ad-hoc signed and not notarized**. A downloaded archive can be blocked by Gatekeeper. Do not advertise an ad-hoc package as Apple-notarized or instruct users to disable security protections.

For an identity already installed in your signing keychain:

```sh
GGGMAC_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/prepare-release.sh
```

Developer ID builds use the hardened runtime and a secure timestamp. Submit the resulting app archive using your own Apple notarization setup, staple the approved ticket to the app, and recreate the archive/checksums before distribution. Account credentials, certificates, keychain profiles and signing exports do not belong in Git. The source-only project can be published without those credentials.

## GitHub

CI builds/tests the project and uploads a local app artifact; it does not download game assets or proprietary graphics payloads. The manual **Prepare release draft** workflow builds the version at the selected Git ref and attaches the app/source archives and checksum file to a draft GitHub release. It refuses a mismatched tag. Reviewing and publishing the draft remain explicit maintainer actions.

Include the matching source archive with a binary release, the existing GPL license/notices, the early-access status, requirements, signing/notarization status, and the manual D3DMetal setup limitation. No repository or release has to be created merely to run local preparation.
