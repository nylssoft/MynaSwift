import SwiftUI

struct PinDialogView: View {
    private enum Field {
        case pin
    }

    @Binding var isPresented: Bool
    let onSubmit: (String) async throws -> Void
    var onCancel: (() -> Void)?

    @State private var pin = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PIN Required")
                .font(.title2)

            SecureField("PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .pin)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel?()
                    isPresented = false
                }
                .disabled(isSubmitting)

                Button("Continue") {
                    Task {
                        await submit()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isSubmitting || pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)

            if isSubmitting {
                ProgressView("Verifying PIN...")
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .pin
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await onSubmit(pin)
            isPresented = false
        } catch {
            if let authenticationError = error as? AuthenticationError {
                errorMessage = authenticationError.errorDescription
            } else {
                errorMessage = "Unexpected PIN authentication error."
            }
        }
        isSubmitting = false
    }
}
