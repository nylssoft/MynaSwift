# MynaSwift

A sample Swift desktop application for macOS with skeleton dialogs for:
- Login
- About

## Open and run

1. Open `Package.swift` in Xcode.
2. Select the `MynaSwift` scheme.
3. Press Run.

## Notes

- `LoginDialogView` is presented as a sheet from the main window.
- `AboutDialogView` is opened as a standalone dialog window from either:
  - The **About MynaSwift** app-menu item
  - The **Show About Dialog** button in the main window
- The auth stub accepts `demo` / `password123` and rejects other credentials.
