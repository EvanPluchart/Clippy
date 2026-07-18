# Clippy

<p align="center">
  <img src="Artwork/ClippyIconMaster.png" width="168" alt="Clippy app icon">
</p>

<p align="center">
  A fast, private, keyboard-first clipboard history for macOS.
</p>

<p align="center">
  <a href="README.fr.md">Français</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
  ·
  <a href="SECURITY.md">Security</a>
</p>

Clippy brings a native `⌘⇧V` clipboard picker to macOS. It lives quietly in the menu bar, keeps clipboard history on the Mac, and pastes the selected item back into the app you were using—without requiring the full history window to stay open.

> Clippy 1.2 currently has a French interface. English localization is planned for the next release.

![Clippy quick clipboard picker](Docs/Images/quick-panel.jpg)

## Highlights

- Native Swift 6, SwiftUI, AppKit and SwiftData application
- Text, rich text, links, files, images and hexadecimal colors
- Keyboard-first picker: search, filters, arrows, Return, Escape and `⌘1`…`⌘9`
- Automatic focus restoration and paste into the previously active app
- Full history with sorting, multi-selection, pinning and batch deletion
- Configurable retention, deduplication and ignored content types
- App exclusions and custom sensitive-content patterns
- Optional launch at login
- Light, dark and system appearance
- Local-only processing: no account, sync, analytics, telemetry or network client
- Universal binary for Apple silicon and Intel Macs

![Clippy history window](Docs/Images/history.jpg)

![Clippy settings in dark mode](Docs/Images/settings-dark.jpg)

## Install

### Homebrew and direct download

The public Cask and downloadable app will be published with the first Developer ID signed and notarized release. Until then, build Clippy locally from source.

### Build locally

```sh
git clone https://github.com/EvanPluchart/Clippy.git
cd Clippy
./scripts/build_local.sh
```

The universal, ad-hoc signed app is written to `dist/local/Clippy.app`. This local build is intended for development; public downloads are Developer ID signed and notarized.

## First run

![Clippy onboarding](Docs/Images/onboarding.jpg)

1. Open Clippy. The onboarding screen explains the shortcut and privacy model.
2. Enable **Launch Clippy at login** if you want `⌘⇧V` available after every restart.
3. Copy text, an image, a URL or a file.
4. Press `⌘⇧V`, choose an item with the arrows, then press Return.
5. Grant Accessibility permission when macOS asks. Clippy needs it only to synthesize `⌘V` in the app that was active before the picker.

The history window never needs to remain open. Clippy can run menu-bar-only with no Dock icon.
If Clippy is already running, opening it again from Finder or Applications brings the history window forward.

## Permissions

Reading and writing the pasteboard does not require a macOS permission prompt. The global shortcut uses the public Carbon hot-key API and does not monitor general keystrokes.

Automatic paste requires **System Settings → Privacy & Security → Accessibility**. Clippy first writes the chosen item to the pasteboard, restores the previous app, and only then sends Command-V.

Clippy’s Developer ID build intentionally does not use App Sandbox because macOS Accessibility clients are incompatible with it. Hardened Runtime remains enabled, there are no network entitlements or networking dependencies, and all clipboard processing stays local.

If automatic paste does not work after permission was granted:

1. Quit every running copy of Clippy.
2. Make sure the app is installed at `/Applications/Clippy.app`.
3. In Accessibility settings, turn Clippy off and back on. Remove and re-add it if macOS still references an older build.
4. Reopen Clippy and confirm **Settings → General → Collage automatique** is enabled.

## Privacy

Clipboard history is stored under:

```text
~/Library/Application Support/Clippy/
├── database/Clippy.store
├── images/
└── thumbnails/
```

Preferences are stored in `~/Library/Preferences/com.evpl.clippy.plist`.

On first launch, Clippy safely imports compatible history and preferences from the container used by earlier sandboxed builds. The migration is idempotent and leaves the legacy data untouched.

Clippy never sends clipboard data anywhere. It does not include telemetry, crash-reporting SDKs, remote configuration or an updater. The privacy controls can:

- pause monitoring immediately;
- exclude applications by bundle identifier;
- ignore selected clipboard types;
- ignore transient or confidential pasteboard markers;
- ignore short entries from known password managers;
- reject entries matching custom regular expressions;
- erase the complete local history.

Sensitive-content detection is defensive, not a security boundary. Any clipboard manager can contain private data, so review the privacy settings before using Clippy with confidential material.

## Keyboard controls

| Action | Shortcut |
| --- | --- |
| Open quick picker | `⌘⇧V` |
| Move selection | `↑` / `↓` |
| Paste selected item | `Return` |
| Choose result 1–9 | `⌘1`…`⌘9` |
| Close picker | `Escape` |
| Open settings | `⌘,` |

The global picker shortcut is configurable under **Settings → Shortcut**.

## Development

Requirements:

- macOS 14 Sonoma or later
- Xcode 16 or later
- Swift 6

Open `Clippy.xcodeproj` and run the shared **Clippy** scheme, or use:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The project has no third-party runtime dependency. After adding or removing a Swift source file, regenerate the checked-in Xcode project:

```sh
ruby scripts/generate_xcodeproj.rb
```

### Architecture

```text
Clippy/
├── App/             lifecycle, shared state and AppKit window controllers
├── Models/          SwiftData model and Codable settings
├── Repositories/    transactional history access
├── Services/        monitoring, parsing, paste, storage and cleanup
├── Utilities/       normalization, hashing, privacy filters and logging
├── Views/           quick picker, history, settings, onboarding and menu
└── Resources/       icon assets, entitlements and privacy manifest
```

Original images are stored as normalized PNG files. Small JPEG thumbnails and a bounded decoded-image cache keep list scrolling responsive. Stored paths are relative and validated before access.

## Release

`scripts/release.sh` performs the strict tests, creates a universal archive, signs it with Developer ID, validates entitlements, submits it for notarization, staples the ticket, produces the release ZIP and SHA-256, and generates the Homebrew cask.

Required environment variables:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="clippy-notary" \
DEVELOPMENT_TEAM="TEAMID" \
./scripts/release.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines and [SECURITY.md](SECURITY.md) for responsible disclosure.

## License

Clippy is available under the [MIT License](LICENSE).
