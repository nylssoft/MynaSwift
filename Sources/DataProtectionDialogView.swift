import SwiftUI

struct DataProtectionDialogView: View {
    @Binding var isPresented: Bool
    let initialSecurityKey: String
    let onSave: (String) -> Void

    @State private var securityKey: String

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
            Text("Data Protection")
                .font(.title2)

            Text("Enter the security key used to encrypt and decrypt personal workspace data.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            SecureField("Security key", text: $securityKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }

                Button("Save") {
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
