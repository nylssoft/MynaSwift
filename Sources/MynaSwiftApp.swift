import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconFactory.makeAppIcon()
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            DownloadDirectoryAccessManager.shared.ensureAccessOnStartup()
        }
    }
}

@main
struct MynaSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #if DEBUG
        @AppStorage("debug.locale.override") private var debugLocaleOverride = "system"
    #endif

    #if DEBUG
        private var debugLocale: Locale {
            switch debugLocaleOverride {
            case "de":
                return Locale(identifier: "de")
            case "en":
                return Locale(identifier: "en")
            default:
                return .autoupdatingCurrent
            }
        }

        private func debugLocaleLabel(_ key: String, title: String) -> String {
            let marker = debugLocaleOverride == key ? "[x]" : "[ ]"
            return "\(marker) \(title)"
        }
    #endif

    var body: some Scene {
        WindowGroup(L10n.s("app.name")) {
            ContentView()
        }
        #if DEBUG
            .environment(\.locale, debugLocale)
        #endif
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.s("menu.about")) {
                    AppDialogController.shared.showAboutDialog()
                }
            }
            #if DEBUG
                CommandMenu("Debug Locale") {
                    Button(debugLocaleLabel("system", title: "System")) {
                        debugLocaleOverride = "system"
                    }
                    Button(debugLocaleLabel("en", title: "English")) {
                        debugLocaleOverride = "en"
                    }
                    Button(debugLocaleLabel("de", title: "Deutsch")) {
                        debugLocaleOverride = "de"
                    }
                }
            #endif
        }
    }
}
