import SwiftUI

final class AppDialogController {
    static let shared = AppDialogController()

    private init() {}

    func showAboutDialog() {
        let view = AboutDialogView()
        let host = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: host)
        window.title = L10n.s("about.window.title")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 260))
        window.center()
        window.isReleasedWhenClosed = false

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
