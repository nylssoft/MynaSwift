import SwiftUI

struct LoggedInUserDetailsView: View {
    let displayName: String
    let email: String?
    let profileImageURL: URL?
    let lastLoginText: String?
    let registeredText: String?
    let hasDataProtectionSecurityKey: Bool
    let isLoggingOut: Bool
    let onDataProtectionTap: () -> Void
    let onLogoutTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let profileImageURL {
                AsyncImage(url: profileImageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)

                if let email, !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let lastLoginText {
                    Text("Last login: \(lastLoginText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let registeredText {
                    Text("Registered: \(registeredText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onDataProtectionTap) {
                    HStack(spacing: 6) {
                        Image(systemName: hasDataProtectionSecurityKey ? "lock.fill" : "lock.open")
                            .font(.caption)
                        Text(
                            hasDataProtectionSecurityKey
                                ? "Data protection key: Set" : "Data protection key: Not set"
                        )
                        .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button("Log out", action: onLogoutTap)
                    .font(.caption)
                    .buttonStyle(.link)
                    .disabled(isLoggingOut)
            }
        }
    }
}
