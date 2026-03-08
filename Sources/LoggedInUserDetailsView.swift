import SwiftUI

struct LoggedInUserDetailsView: View {
    private let securitySettingsURL = URL(string: "https://www.stockfleth.eu")

    let displayName: String
    let email: String?
    let profileImageURL: URL?
    let lastLoginText: String?
    let storageText: String?
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
                    Text(
                        String(format: L10n.s("user.lastLogin.format"), lastLoginText)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let storageText {
                    Text(
                        String(format: L10n.s("user.storage.format"), storageText)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button(action: onDataProtectionTap) {
                    HStack(spacing: 6) {
                        Image(systemName: hasDataProtectionSecurityKey ? "lock.fill" : "lock.open")
                            .font(.caption)
                        Text(
                            hasDataProtectionSecurityKey
                                ? L10n.s("user.dataProtectionKey.set")
                                : L10n.s("user.dataProtectionKey.notSet")
                        )
                        .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if let securitySettingsURL {
                    Link(L10n.s("user.securitySettings.link"), destination: securitySettingsURL)
                        .font(.caption)
                }

                Button(L10n.s("user.logout"), action: onLogoutTap)
                    .font(.caption)
                    .buttonStyle(.link)
                    .disabled(isLoggingOut)
            }
        }
    }
}
