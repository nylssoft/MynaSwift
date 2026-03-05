import SwiftUI

struct AboutDialogView: View {
    private let appVersion = "0.2.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.s("app.name"))
                .font(.title)

            Text(String(format: L10n.s("about.version.format"), appVersion))
                .foregroundStyle(.secondary)

            Text(L10n.s("about.description"))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            HStack {
                Spacer()
                Button(L10n.s("common.close")) {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 320)
    }
}
