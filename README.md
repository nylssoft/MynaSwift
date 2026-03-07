# MynaSwift

MynaSwift is a macOS SwiftUI client for the Myna backend on `stockfleth.eu`.

MynaSwift is a personal workspace for managing notes, documents, passwords, contacts, appointments, and diary entries in one secure desktop application.
The goal of the application is to keep personal information organized while protecting workspace content with a user-defined security key.

## Status

This implementation is still work in progress. Existing features are usable, but APIs, UX details, and section coverage may still change.

## Current implementation

- Authentication flow with backend integration, including stored long-lived session handling and PIN step when required.
- User details panel with logout and data protection key management.
- Notes management: list, detail, create, edit, delete.
- Contacts management: load, edit, create, delete, and upload.
- Password manager: load, create, edit, delete, upload, per-item password encode/decode, URL open action, and favicon display.
- Diary: calendar month navigation, load days with entries, load/edit/save/delete encrypted diary entries.
- Encryption/decryption for protected notes, contacts, password data, and diary entries.
- Application status bar for asynchronous activity and action feedback (for example copy/save/delete messages).
- Localization support for English and German.
- Fallback behavior to English for missing/unsupported localization.
- About dialog integration via app menu, including version and copyright notice.

## Not fully implemented yet

- Some workspace sections are placeholders or skeleton views (for example documents and appointments).
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

## Related repositories

- Web client (TypeScript): [TsMynaPortal](https://github.com/nylssoft/TsMynaPortal)
- Android client (MAUI): [MynaPasswordReaderMAUI](https://github.com/nylssoft/MynaPasswordReaderMAUI)
- Server backend: [MynaAPIServer](https://github.com/nylssoft/MynaAPIServer)
