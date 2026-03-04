import SwiftUI

struct AboutDialogView: View {
    private let appVersion = "0.2.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MynaSwift")
                .font(.title)

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            Text(
                "MynaSwift is a personal workspace for managing notes, documents, passwords, contacts, appointments, and diary entries in one secure desktop application.\n\nThe goal of the application is to keep personal information organized while protecting workspace content with a user-defined security key."
            )
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            HStack {
                Spacer()
                Button("Close") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
    }
}
