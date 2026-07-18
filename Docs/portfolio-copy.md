# Clippy — portfolio copy

## Short description

Clippy is a native, privacy-first clipboard history for macOS. It brings a keyboard-first `⌘⇧V` picker to the Mac, restores focus to the previous application and pastes the selected item without keeping a full window open.

## Description courte

Clippy est un historique de presse-papiers natif et respectueux de la vie privée pour macOS. Son panneau `⌘⇧V`, pensé pour le clavier, rend le focus à l’application précédente et colle l’élément choisi sans garder de fenêtre principale ouverte.

## Case-study outline

### Problem

macOS has no built-in equivalent to the Windows clipboard history. Existing tools often add accounts, cloud sync, Electron runtimes or busy interfaces to a workflow that should be instant.

### Product response

- A menu-bar utility with a focused floating picker
- Complete keyboard navigation and configurable global shortcut
- Native pasteboard parsing for text, RTF, links, files, images and colors
- Automatic focus restoration and paste through user-authorized Accessibility
- Local SwiftData persistence, bounded image caching and retention controls
- App exclusions and defensive sensitive-content filtering

### Engineering highlights

- Swift 6 strict concurrency with no third-party runtime dependency
- SwiftUI views hosted in purpose-built AppKit windows and panels
- Carbon global hot key without broad keyboard monitoring
- Transactional file storage and safe relative-path resolution
- Normalized image fingerprints and optimized thumbnails
- Idempotent migration from the earlier sandboxed data container
- Hardened Runtime, privacy manifest, Developer ID/notarization pipeline
- Universal Apple silicon and Intel build

### Quality

- Unit and integration coverage for parsing, pasteboard writing, storage, retention, settings migration, privacy filtering and shortcut validation
- Xcode static analysis and warnings-as-errors
- End-to-end validation of keyboard selection, focus restoration and real automatic paste
- Visual checks across onboarding, history, settings, quick picker, menus and appearance modes

## Suggested portfolio labels

- macOS
- Swift 6
- SwiftUI
- AppKit
- SwiftData
- Accessibility
- Performance
- Privacy
- Product design
- Open source

## Suggested call to action

Install with Homebrew:

```sh
brew install --cask EvanPluchart/tap/clippy
```

Source and releases: `github.com/EvanPluchart/Clippy`
