# Clippy

<p align="center">
  <img src="Artwork/ClippyIconMaster.png" width="168" alt="Clippy app icon">
</p>

<p align="center">
  A fast, private, keyboard-first clipboard history for macOS.
</p>

<p align="center">
  <a href="https://clippy.evanpluchart.fr">Website</a>
  ·
  <a href="README.fr.md">Français</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
  ·
  <a href="CONTRIBUTING.md">Contributing</a>
  ·
  <a href="SECURITY.md">Security</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138">
  <img alt="CI status" src="https://img.shields.io/github/actions/workflow/status/EvanPluchart/Clippy/ci.yml?branch=main&label=CI">
  <img alt="MIT License" src="https://img.shields.io/github/license/EvanPluchart/Clippy">
</p>

Clippy adds a native `⌘⇧V` clipboard picker to macOS. It stays quietly in the menu bar, keeps clipboard history on your Mac, and pastes the selected item back into the app you were using. The full history window never needs to stay open.

![Clippy quick clipboard picker](Docs/Images/quick-panel.jpg)

## Contents

- [Install](#install)
- [Use Clippy](#use-clippy)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Features](#features)
- [Permissions and troubleshooting](#permissions-and-troubleshooting)
- [Privacy](#privacy)
- [Languages](#languages)
- [Development](#development)
- [Release](#release)
- [License](#license)

## Install

### Direct download — easiest

Download the latest signed and notarized DMG from [clippy.evanpluchart.fr](https://clippy.evanpluchart.fr), open it, then drag Clippy into Applications.

![Clippy drag-to-Applications installer](Docs/Images/installer.jpg)

If the website still shows “Download coming soon”, the signed release has not been published yet. Source builds remain available below.

### Homebrew — recommended for Terminal users

```sh
brew install --cask EvanPluchart/tap/clippy
```

Then open Clippy from Applications or with:

```sh
open -a Clippy
```

Update or uninstall it with:

```sh
brew upgrade --cask clippy
brew uninstall --cask clippy
```

> The Cask becomes available with the first Developer ID signed and notarized public release. If Homebrew reports that the Cask does not exist yet, use the source build below in the meantime.

### Build from source

Requirements: macOS 14 Sonoma or later and Xcode 16 or later.

```sh
git clone https://github.com/EvanPluchart/Clippy.git
cd Clippy
./scripts/build_local.sh
ditto dist/local/Clippy.app /Applications/Clippy.app
open /Applications/Clippy.app
```

The script creates a universal Apple silicon and Intel app at `dist/local/Clippy.app`. It is ad-hoc signed for local development; public releases are Developer ID signed and notarized.

## Use Clippy

1. Open Clippy and complete the short introduction.
2. Copy text, an image, a link, or a file.
3. Press `⌘⇧V`.
4. Move with `↑` and `↓`, then press Return to paste.
5. Allow Accessibility access when macOS asks. It is used only for automatic paste into the previously active app.

Clippy can run menu-bar-only without a Dock icon. Opening it again from Finder or Applications brings up the full history.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open the quick panel | `⌘⇧V` |
| Move the selection | `↑` / `↓` |
| Paste the selected item | `Return` |
| Paste result 1–9 | `⌘1`…`⌘9` |
| Close the quick panel | `Escape` |
| Open settings | `⌘,` |

The global shortcut can be changed under **Settings → Shortcut**.

## Features

- Native Swift 6, SwiftUI, AppKit, and SwiftData app
- Text, rich text, links, files, images, and hexadecimal colors
- Search, type filters, keyboard navigation, and `⌘1`…`⌘9`
- Focus restoration and automatic paste into the previous app
- Full history with sorting, pagination, multi-selection, pinning, and batch deletion
- Configurable retention, storage limits, deduplication, and ignored content types
- Application exclusions and custom sensitive-content patterns
- Optional launch at login
- System, light, and dark appearance
- English and French interface, selected automatically from macOS
- No account, cloud sync, analytics, telemetry, or network client
- Universal binary for Apple silicon and Intel Macs

![Clippy history window](Docs/Images/history.jpg)

![Clippy settings in dark mode](Docs/Images/settings-dark.jpg)

## Permissions and troubleshooting

### Why Accessibility permission is needed

Reading and writing the pasteboard does not require a macOS permission prompt. The global shortcut uses the public Carbon hot-key API and does not monitor general keystrokes.

Automatic paste requires **System Settings → Privacy & Security → Accessibility**. Clippy writes the selected item to the pasteboard, restores the previous app, and only then sends `⌘V`.

Clippy’s Developer ID build intentionally does not use App Sandbox because the user-authorized Accessibility workflow is incompatible with it. Hardened Runtime remains enabled, and the app has no network entitlement or networking dependency.

### Automatic paste does not work

1. Quit every running copy of Clippy.
2. Make sure the app is installed at `/Applications/Clippy.app`.
3. Open **System Settings → Privacy & Security → Accessibility**.
4. Turn Clippy off and back on. If macOS still references an older build, remove Clippy from the list and add `/Applications/Clippy.app` again.
5. Reopen Clippy and check **Settings → General → Automatic Paste**.

Even without Accessibility permission, selecting an item still copies it to the pasteboard so you can paste manually.

### `⌘⇧V` does not open the panel

- Open **Settings → Shortcut** and confirm that the shortcut is active.
- Another app may already use the same shortcut; choose a different combination and click **Apply**.
- Enable **Launch Clippy at Login** if you want the shortcut available after every restart.

## Privacy

Clipboard history is stored locally under:

```text
~/Library/Application Support/Clippy/
├── database/Clippy.store
├── images/
└── thumbnails/
```

Preferences are stored in `~/Library/Preferences/com.evpl.clippy.plist`.

Clippy never sends clipboard data anywhere. It has no telemetry, crash-reporting SDK, remote configuration, updater, or network client. Privacy settings can pause monitoring, exclude applications, ignore content types, reject custom regular-expression patterns, and erase all local history.

On first launch, Clippy safely imports compatible history and preferences from earlier sandboxed builds. Migration is idempotent and leaves the legacy data untouched.

Sensitive-content detection is defensive, not a security boundary. Review the privacy settings before using any clipboard manager with confidential material.

## Languages

Clippy 1.3 is available in English and French. The app automatically follows the preferred language configured in macOS and falls back to French when no supported language is selected.

## Development

Requirements:

- macOS 14 Sonoma or later
- Xcode 16 or later
- Swift 6

Open `Clippy.xcodeproj` and run the shared **Clippy** scheme, or run:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The project has no third-party runtime dependency. After adding or removing a Swift source or resource file, regenerate the checked-in Xcode project:

```sh
ruby scripts/generate_xcodeproj.rb
```

Validate the translation catalog and its format placeholders with:

```sh
ruby scripts/validate_localizations.rb
```

CI also compares the catalog with the localization keys emitted by the Swift compiler.

### Architecture

```text
Clippy/
├── App/             lifecycle, shared state, and AppKit window controllers
├── Models/          SwiftData model and Codable settings
├── Repositories/    transactional history access
├── Services/        monitoring, parsing, paste, storage, and cleanup
├── Utilities/       normalization, hashing, privacy filters, and localization
├── Views/           quick panel, history, settings, onboarding, and menu bar
└── Resources/       icon assets, translations, entitlements, and privacy manifest
```

Original images are stored as normalized PNG files. Small JPEG thumbnails and a bounded decoded-image cache keep list scrolling responsive. Stored paths are relative and validated before access.

## Release

`scripts/release.sh` runs strict tests, creates a universal archive, signs it with Developer ID, validates entitlements, notarizes and staples both the app and DMG, verifies Gatekeeper, produces the DMG and SHA-256, and generates the Homebrew Cask.

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="clippy-notary" \
DEVELOPMENT_TEAM="TEAMID" \
./scripts/release.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request and [SECURITY.md](SECURITY.md) for responsible disclosure.

## License

Clippy is available under the [MIT License](LICENSE).
