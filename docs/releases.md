# Releases and build automation

[Repository](https://github.com/WaterWaters/codex-island) · [Actions](https://github.com/WaterWaters/codex-island/actions) · [Preview downloads](https://github.com/WaterWaters/codex-island/releases)

## Continuous integration

The macOS checks workflow runs for pushes to main, pull requests, and manual dispatch. Its matrix covers the macOS 14 Apple Silicon runner and the macOS 15 Intel runner. Each job checks public files and documentation links, validates script syntax, runs the fixture-based tests, builds a native Release app, verifies its signature, and executes the packaged binary with `--check-resources`. This checks the four language catalogs and brand icon without creating NSApplication or reading Codex data.

Hosted-runner unit tests do not replace real desktop validation of approvals, Spaces, displays, or long-duration performance. No real chats, personal images, or signing credentials are required. The native gallery rasterization test is an opt-in desktop integration check (`CODEX_ISLAND_TEST_RENDER_PREVIEWS=1 ./Scripts/test.sh`). A headless runner may return a Metal device that still aborts during rendering, so device availability alone is insufficient. Default CI explicitly skips that check while synthetic gallery model and brand-pixel checks still run.

## Preview release workflow

Pushing a version tag such as v0.8.1 starts the preview workflow. Maintainers can also dispatch it manually with an existing tag. The workflow:

1. Checks that the tag is a version, resolves to the checked-out commit, and is on main's history.
2. Checks the public source set and runs Release tests.
3. Builds arm64 and x86_64 binaries, combines them into a universal app, and verifies both binary architectures and the ad-hoc signature.
4. Checks the app bundle against a public-file allowlist, then creates a DMG, ZIP, and SHA-256 checksums.
5. Transfers only the named release artifacts to a separate publishing job. Build jobs have read-only repository permissions; only publishing has contents:write.
6. Rechecks the tag commit and artifact checksums, creates a draft with assets, and publishes it as a prerelease. An existing release is never replaced automatically.

Third-party actions are official GitHub actions pinned to commit SHAs; Dependabot is configured to propose updates.

## Preparing a version

Update MARKETING_VERSION and BUILD_NUMBER in Scripts/package_app.sh, plus the changelog. The tag must match the bundle's marketing version. Validate locally:

```bash
python3 Scripts/verify_repository.py
./Scripts/test.sh -c release
./Scripts/package_release.sh v0.8.1
```

After committing and pushing to main, wait for all CI jobs on that exact commit to pass before creating the version tag:

```bash
git tag -a v0.8.1 -m "Codex Island v0.8.1 preview"
git push origin v0.8.1
```

Do not reuse a published tag. A failed workflow may leave a draft; inspect it and the failure logs before manually recovering. Published assets are not overwritten by rerunning the workflow.

## Downloads and verification

Each successful preview provides:

- CodexIsland-vVERSION-macos-universal.dmg, with an Applications shortcut.
- CodexIsland-vVERSION-macos-universal.zip, containing the app.
- SHA256SUMS.txt, covering both downloads.

Download the checksums and the assets to the same directory, then run:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Current builds are **ad-hoc signed and not notarized**. No Developer ID certificate or notarization credential is configured. The minimum deployment target and universal architecture checks are distinct from full real-device verification. These packages remain compatibility previews, not a claim that all release-readiness checks are complete.

## Public source gate

Scripts/verify_repository.py rejects generated/private directories, session databases and JSONL, key material paths, unexpected media, and recognizable embedded GitHub tokens/private-key blocks. The media allowlist contains the reviewed brand assets, the settings icon copy, and sixteen synthetic native Full/Mini state previews. It also checks local Markdown references. This targeted gate is not a complete secret scanner or a replacement for code review.

Personal pet files stay in the ignored local directory and are absent from Git history and release bundles. The app's separate bundle allowlist prevents an accidental private resource copy from reaching a release archive.
