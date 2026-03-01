import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MynaSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MynaSwift") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MynaSwift") {
                    AppDialogController.shared.showAboutDialog()
                }
            }
        }
    }
}
