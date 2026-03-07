import Foundation

enum ServiceError: LocalizedError {
    case emptyCredentials
    case invalidCredentials
    case twoFactorCodeRequired
    case twoFactorTokenMissing
    case invalidURL
    case networkError
    case noDataProtectionKey
    case missingPasswordManagerSalt
    case missingEncryptionKeyConfig
    case deriveEncryptionKey
    case encryptData
    case invalidDataProtectionKey
    case serverStatusCode(Int)
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .emptyCredentials:
            return L10n.s("service.error.emptyCredentials")
        case .twoFactorCodeRequired:
            return L10n.s("service.error.twoFactorCodeRequired")
        case .twoFactorTokenMissing:
            return L10n.s("service.error.twoFactorTokenMissing")
        case .invalidURL:
            return L10n.s("service.error.invalidURL")
        case .networkError:
            return L10n.s("service.error.network")
        case .noDataProtectionKey:
            return L10n.s("service.error.noDataProtectionKey")
        case .missingPasswordManagerSalt:
            return L10n.s("service.error.missingPasswordManagerSalt")
        case .missingEncryptionKeyConfig:
            return L10n.s("service.error.missingEncryptionKeyConfig")
        case .deriveEncryptionKey:
            return L10n.s("service.error.deriveEncryptionKey")
        case .encryptData:
            return L10n.s("service.error.encryptData")
        case .invalidDataProtectionKey:
            return L10n.s("service.error.invalidDataProtectionKey")
        case .serverStatusCode(let statusCode):
            return String(
                format: L10n.s("service.error.serverStatusCode.format"),
                statusCode)
        case .invalidCredentials:
            return L10n.s("service.error.invalidCredentials")
        case .serverError(let message):
            return message
        case .decodingError:
            return L10n.s("service.error.decoding")
        }
    }
}
