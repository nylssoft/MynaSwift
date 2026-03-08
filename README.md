# MynaSwift

MynaSwift is a macOS SwiftUI client for the Myna backend on `stockfleth.eu`.

MynaSwift is a personal workspace for managing notes, documents, passwords, contacts, appointments, and diary entries in one secure desktop application.
The goal of the application is to keep personal information organized while protecting workspace content with a user-defined security key.

## Status

This implementation is usable for all major workspace sections. The app is still under active development, but documents and appointments are no longer placeholders.

## Current implementation

- Authentication flow with backend integration, including stored long-lived session handling and PIN step when required.
- User details panel with logout and data protection key management.
- Notes management: list, detail, create, edit, delete.
- Contacts management: load, create, edit, delete, and upload.
- Password manager: load, create, edit, delete, upload, per-item password encode/decode, URL open action, and favicon display.
- Diary: calendar month navigation, load days with entries, load/edit/save/delete encrypted diary entries.
- Documents: folder navigation, create folder, rename (file/folder), upload, replace upload, single and bulk selection, move, delete, download to `~/Downloads` with automatic unique file naming, open downloaded files with default macOS app, per-file icons, and Quick Look thumbnail preview in details.
- Appointments: load list/details, create/edit/delete, participant editing, option date selection via calendar month grid, read-only month calendar with previous/next navigation, and vote URL open/copy actions.
- Encryption/decryption for protected notes, contacts, password data, diary entries, documents, and appointment owner/access-token handling.
- Application status bar for asynchronous activity and action feedback (for example copy/save/delete messages).
- Localization support for English and German.
- Fallback behavior to English for missing/unsupported localization.
- About dialog integration via app menu, including version and copyright notice.

## Not fully implemented yet

- Some UX and validation behavior is still being refined to match other Myna clients in all edge cases.
- App permissions (for example Downloads folder access) depend on macOS Privacy settings and how the app is launched (Xcode/app bundle vs terminal).

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

## macOS permissions

- For Downloads access, open `System Settings > Privacy & Security > Files and Folders` and enable `Downloads Folder` for `MynaSwift`.
- If running from terminal, macOS may apply permission to the terminal app instead of `MynaSwift`.

## Related repositories

- Web client (TypeScript): [TsMynaPortal](https://github.com/nylssoft/TsMynaPortal)
- Android client (MAUI): [MynaPasswordReaderMAUI](https://github.com/nylssoft/MynaPasswordReaderMAUI)
- Server backend: [MynaAPIServer](https://github.com/nylssoft/MynaAPIServer)
