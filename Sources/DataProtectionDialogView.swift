import SwiftUI

struct DataProtectionDialogView: View {
    @Binding var isPresented: Bool
    let initialSecurityKey: String
    let onSave: (String) -> Void

    @State private var securityKey: String
    @State private var isShowingSecurityKey = false

    init(
        isPresented: Binding<Bool>,
        initialSecurityKey: String = "",
        onSave: @escaping (String) -> Void
    ) {
        _isPresented = isPresented
        self.initialSecurityKey = initialSecurityKey
        self.onSave = onSave
        _securityKey = State(initialValue: initialSecurityKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.s("dataProtection.title"))
                .font(.title2)

            Text(L10n.s("dataProtection.description"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.s("dataProtection.warning.title"))
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text(L10n.s("dataProtection.warning.message"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Group {
                    if isShowingSecurityKey {
                        TextField(L10n.s("dataProtection.securityKey"), text: $securityKey)
                    } else {
                        SecureField(L10n.s("dataProtection.securityKey"), text: $securityKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    isShowingSecurityKey.toggle()
                } label: {
                    Image(systemName: isShowingSecurityKey ? "eye.slash" : "eye")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(
                    isShowingSecurityKey
                        ? L10n.s("dataProtection.hideSecurityKey")
                        : L10n.s("dataProtection.showSecurityKey"))
            }

            HStack {
                Spacer()

                Button(L10n.s("common.cancel")) {
                    isPresented = false
                }

                Button(L10n.s("common.save")) {
                    onSave(securityKey)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 380)
    }
}
