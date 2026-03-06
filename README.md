# MynaSwift

MynaSwift is a macOS SwiftUI client for the Myna backend.

## Status

This implementation is still work in progress. Existing features are usable, but APIs, UX details, and section coverage may still change.

## Current implementation

- Authentication flow with backend integration, including stored long-lived session handling and PIN step when required.
- User details panel with logout and data protection key management.
- Notes management: list, detail, create, edit, delete.
- Contacts management: load, edit, create, delete, and upload.
- Encryption/decryption for protected contact and note fields.
- Localization support for English and German.
- Fallback behavior to English for missing/unsupported localization.
- About dialog integration via app menu.

## Not fully implemented yet

- Some workspace sections are placeholders or skeleton views (for example documents, passwords, appointments, and diary entries).
- UI and service behavior are still being refined.

## Run the app

### With Xcode

1. Open `Package.swift` in Xcode.
2. Select the `MynaSwift` scheme.
3. Press Run.

### With SwiftPM

1. Build: `swift build -c debug`
2. Run: `swift run`

## Localization

- Localization resources are in `Sources/Resources/en.lproj/Localizable.strings` and `Sources/Resources/de.lproj/Localizable.strings`.
- Package default localization is English.
- In debug builds, a debug locale menu is available to switch locale override during development.
