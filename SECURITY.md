# Security policy

## Supported versions

Security fixes are provided for the latest published version of Clippy.

## Reporting a vulnerability

Please use GitHub Private Vulnerability Reporting from the repository’s **Security** tab. Include:

- the affected Clippy and macOS versions;
- clear reproduction steps;
- the expected and observed behavior;
- any crash report or proof of concept that does not contain real clipboard data.

Please do not publish the report until a fix is available.

## Privacy and trust boundaries

Clippy processes clipboard content locally and contains no telemetry, analytics SDK, synchronization service, or network client. Clipboard payloads must never be added to logs, crash annotations, fixtures, or issue reports.

Automatic paste requires the macOS Accessibility permission solely to synthesize Command-V in the app that was active before the quick panel. Public builds are Developer ID signed, hardened, and notarized. They are intentionally not App Sandbox builds because Apple documents accessibility clients as incompatible with App Sandbox.
