# DMG artwork

The installer uses a 720 × 450 Finder window with a Retina background, a
custom volume icon, and fixed positions for `Clippy.app` and the Applications
shortcut.

`background-source.png` was generated from the Clippy app icon as a visual
reference. It intentionally contains no text, logos, or controls so the same
installer remains understandable in French and English.

Regenerate the shipping assets after changing the source:

```bash
swift scripts/render_dmg_background.swift \
  Packaging/DMG/background-source.png \
  Packaging/DMG
```

The renderer adds the drag arrow deterministically and exports:

- `background.png` at 1×
- `background@2x.png` at 2×

`scripts/create_dmg.sh` combines both files into a multi-resolution TIFF when
building the disk image. `scripts/verify_dmg.sh` mounts the finished image and
checks its visible contents, Applications link, app signature, architectures,
version, and both background resolutions.
