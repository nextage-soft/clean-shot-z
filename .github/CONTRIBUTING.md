# Contributing to CleanShot Z

Thanks for helping! CleanShot Z is small and native on purpose — a few ground
rules keep it that way.

## Ground rules

- **Zero external Swift dependencies.** Only Apple frameworks and code in this
  repo. PRs adding a package dependency will be declined — implement it, or
  propose it in an issue first.
- **On-device only.** No network calls, no analytics, no account. Privacy is a
  feature; a PR that phones home won't land.
- **File naming**: kebab-case, long and descriptive
  (`area-selection-view.swift`, not `Selection.swift`). Keep files small and
  single-purpose — split when one grows past ~200 lines.
- **Comments** explain constraints the code can't show (coordinate-space flips,
  AppKit quirks, why a workaround exists), not what the next line does.
- One logical change per PR; squash-merge keeps history linear.

## Building

Command Line Tools are enough — no full Xcode required:

```bash
./scripts/build-and-bundle-app.sh          # build + sign → build/CleanShot Z.app
open "build/CleanShot Z.app"
# or build, install to /Applications, and launch:
./scripts/install-to-applications.sh
```

If your Mac has only Command Line Tools and the newest macOS SDK, the script
pins `SDKROOT` automatically (the SwiftUI macro plugin doesn't ship with CLT).
See the README's *Install / Build* section for code-signing options.

First run needs **Screen Recording** permission (System Settings → Privacy &
Security), then a relaunch.

## Testing

XCTest doesn't ship with the Command Line Tools, so automated checks run as an
in-process subcommand of the app binary:

```bash
swift build -c release
.build/release/CleanShotZ --selftest-project   # must print "PROJECT SELFTEST OK"
```

CI (`build-and-test`) runs the same and must pass before merge. Add coverage
for any new pure logic (codecs, geometry, stitching, OCR assembly) in the
self-test path so it's exercised headlessly.

For UI-affecting changes, verify in the running app and say how in the PR —
capture an area, drive the editor, run OCR, etc. (the app can't be fully
driven headless).

## Pull requests

1. Fork, branch from `master`, make the change.
2. `.build/release/CleanShotZ --selftest-project` passes locally.
3. Open the PR — CI must be green; the maintainer reviews and squash-merges.
4. For big features, open an issue first so we agree on the approach — see the
   feature specs in [docs/](../docs/) for the level of detail that helps.

## Reporting security issues

Please don't open public issues for vulnerabilities — see
[SECURITY.md](SECURITY.md).
