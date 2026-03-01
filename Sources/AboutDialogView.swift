import SwiftUI

struct AboutDialogView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("MynaSwift")
                .font(.title)

            Text("Version 0.1.0")
                .foregroundStyle(.secondary)

            Text("This is a skeleton About dialog for a macOS desktop app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            Spacer(minLength: 6)

            Button("Close") {
                NSApplication.shared.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 220)
    }
}
