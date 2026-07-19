# Release checklist

## Product

- [x] Run the onboarding, quick picker, history, settings and menu-bar smoke tests.
- [x] Verify keyboard navigation, click selection and real paste into another app.
- [x] Verify automatic paste with Accessibility both denied and authorized.
- [x] Verify light, dark and system appearance.
- [x] Verify onboarding, quick picker, history, settings and menu-bar layouts in French and English.
- [x] Verify the menu-bar/Dock visibility invariant.
- [ ] Test launch at login on an installed distribution build.

## Engineering

- [x] Run strict tests and Xcode static analysis.
- [x] Build both `arm64` and `x86_64` slices.
- [x] Verify Hardened Runtime and the final entitlements.
- [x] Confirm QA environment hooks are absent from the Release binary.
- [x] Confirm the app embeds no unexpected executable or framework.
- [x] Update version, build number and changelog.
- [x] Validate that every extracted French source string has an English translation.

## Distribution

- [x] Record the owner-approved v1.3 exception: no paid Apple Developer
      membership, Developer ID signature, or notarization.
- [x] Build with an ad-hoc signature and verify that no signing authority is present.
- [x] Confirm the expected Gatekeeper rejection on a quarantined copy and
      document Apple’s **Open Anyway** flow.
- [x] Publish the DMG, SHA-256 and dSYM.
- [x] Verify the Retina DMG layout and drag-to-Applications flow.
- [x] Publish the generated Cask to `EvanPluchart/homebrew-tap`.
- [x] Test `brew install --cask EvanPluchart/tap/clippy`.
- [ ] Future paid release: sign with Developer ID, notarize, staple, and pass
      Gatekeeper assessment.

## Publication

- [x] Add final light and dark screenshots to the README.
- [x] Choose and add the repository license.
- [x] Enable GitHub Private Vulnerability Reporting.
- [x] Create the source-only `v1.2.0` GitHub release from `CHANGELOG.md`.
- [x] Publish the bilingual website at `clippy.evanpluchart.fr`.
- [x] Create and publish the explicitly unsigned `v1.3.0` GitHub release.
- [ ] Add the repository and Homebrew links to the portfolio.
