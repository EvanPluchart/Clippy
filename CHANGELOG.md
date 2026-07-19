# Changelog

All notable changes to Clippy are documented here.

## [Unreleased]

## [1.3.0] - 2026-07-19

### Added

- Official bilingual website at [clippy.evanpluchart.fr](https://clippy.evanpluchart.fr).
- Direct-install DMG packaging with an Applications shortcut.
- Polished language-neutral DMG experience with Retina artwork, fixed icon
  placement, a drag target, and a custom volume icon.
- Reproducible free release pipeline with an ad-hoc app signature, Hardened
  Runtime and entitlement validation, dSYM archive, SHA-256 checksum, and
  explicit verification that no Developer ID signature is present.
- Optional Developer ID signing, app and DMG notarization, stapling, and
  Gatekeeper assessment pipeline for a future signed distribution.

### Changed

- Updated the Homebrew Cask to install the official DMG, explain the one-time
  Gatekeeper confirmation, and use the official website as its homepage.
- Documented that the current free distribution is not Developer ID signed or
  notarized, with official first-launch instructions and checksum verification.
- Protected `main` behind required pull requests and a passing strict macOS CI check.

## [1.2.0] - 2026-07-18

### Added

- Automatic paste into the previously active app after choosing a clipboard item.
- First-launch onboarding with shortcut, privacy, and Accessibility guidance.
- Keyboard-first quick panel with search, type filters, arrows, Return, Escape, and Command-1 through Command-9.
- Full history window with sorting, pagination, multi-selection, pinning, and batch deletion.
- Configurable retention, deduplication, application exclusions, sensitive-content patterns, and ignored types.
- Universal Apple silicon and Intel release packaging, notarization script, Homebrew cask template, and CI.
- Twenty-three strict-concurrency unit and integration tests.
- Complete English localization alongside French, selected automatically from the macOS language order.
- CI validation that every extracted user-facing string has a complete English translation.

### Changed

- Reworked the quick panel so it never needs the full history window to be open.
- Made settings persistence idempotent to eliminate an idle CPU loop.
- Normalized image fingerprints from decoded sRGB pixels.
- Added transactional image writes, optimized thumbnails, decoded-image cache limits, and safe relative-path resolution.
- Kept at least one visible access point when changing the menu bar and Dock settings.
- Removed App Sandbox from Developer ID builds because Clippy’s user-authorized Accessibility workflow is incompatible with it.
- Reorganized the English and French READMEs around a quick table of contents, Homebrew-first installation, first use, and troubleshooting.

### Fixed

- Global shortcut crashes and unreliable panel presentation after the app had been idle.
- Arrow-key navigation, stationary-pointer selection, double-selection, and filter overflow in the quick panel.
- Focus restoration and automatic paste after clicking or pressing Return.
- Startup cleanup racing with a newly stored image.
- File lists containing newline characters.
- Incorrect alpha-channel interpretation for hexadecimal colors.
- Corrupt or partially migrated settings resetting unrelated preferences.
- Existing history and preferences not following users when upgrading from the earlier sandboxed build.
- Reopening the menu-bar-only app from Finder or Applications not presenting the history window.

[Unreleased]: https://github.com/EvanPluchart/Clippy/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/EvanPluchart/Clippy/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/EvanPluchart/Clippy/releases/tag/v1.2.0
