# Contributing to Clippy

Thanks for helping improve Clippy.

## Development setup

Requirements:

- macOS 14 or later
- Xcode 16 or later
- Swift 6

Open `Clippy.xcodeproj` and run the `Clippy` scheme, or use:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The Xcode project is generated without third-party tooling. After adding or removing a Swift source file, run:

```sh
ruby scripts/generate_xcodeproj.rb
```

French is the source language and every user-facing string must include an English translation in `Clippy/Resources/Localizable.xcstrings`. Validate the catalog structure and placeholders with:

```sh
ruby scripts/validate_localizations.rb
```

## Pull requests

- Keep changes focused and explain their user-facing impact.
- Add or update tests for behavior changes.
- Preserve local-only processing: do not add telemetry or network access.
- Never log clipboard payloads.
- Run the strict Swift tests and Xcode analyzer before opening a pull request.
- Include screenshots for visible UI changes.
- Update both `README.md` and `README.fr.md` when documentation changes affect users.

## Architecture

`AppState` composes the application services. SwiftData metadata lives in the repository, image files are handled by the storage actor, and the quick panel is an AppKit `NSPanel` hosting SwiftUI. Avoid moving blocking file or image work onto the main actor.

## Security reports

Do not open a public issue for a vulnerability. Follow [SECURITY.md](SECURITY.md).
