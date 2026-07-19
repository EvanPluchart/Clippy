# Release checklist

## Product

- [x] Run the onboarding, quick picker, history, settings and menu-bar smoke tests.
- [x] Verify keyboard navigation, click selection and real paste into another app.
- [x] Verify automatic paste with Accessibility both denied and authorized.
- [x] Verify light, dark and system appearance.
- [x] Verify onboarding, quick picker, history, settings and menu-bar layouts in French and English.
- [x] Verify the menu-bar/Dock visibility invariant.
- [ ] Test launch at login on an installed, signed build.

## Engineering

- [x] Run strict tests and Xcode static analysis.
- [x] Build both `arm64` and `x86_64` slices.
- [x] Verify Hardened Runtime and the final entitlements.
- [x] Confirm QA environment hooks are absent from the Release binary.
- [x] Confirm the app embeds no unexpected executable or framework.
- [x] Update version, build number and changelog.
- [x] Validate that every extracted French source string has an English translation.

## Distribution

- [ ] Sign with a Developer ID Application certificate.
- [ ] Notarize and staple the app.
- [ ] Verify Gatekeeper assessment on a clean macOS account or Mac.
- [ ] Publish the DMG, SHA-256 and dSYM.
- [ ] Verify the Retina DMG layout, drag-to-Applications flow and first launch
      from a downloaded copy.
- [ ] Publish the generated Cask to `EvanPluchart/homebrew-tap`.
- [ ] Test `brew install --cask EvanPluchart/tap/clippy`.

## Publication

- [x] Add final light and dark screenshots to the README.
- [x] Choose and add the repository license.
- [x] Enable GitHub Private Vulnerability Reporting.
- [x] Create the source-only `v1.2.0` GitHub release from `CHANGELOG.md`.
- [x] Publish the bilingual website at `clippy.evanpluchart.fr`.
- [ ] Create and publish the signed `v1.3.0` GitHub release.
- [ ] Add the repository and Homebrew links to the portfolio.
