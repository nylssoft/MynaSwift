import CommonCrypto
import CryptoKit
import Foundation

struct UserInfoResponse: Decodable {
    let id: Int64
    let name: String
    let email: String
    let requires2FA: Bool
    let useLongLivedToken: Bool
    let usePin: Bool
    let allowResetPassword: Bool
    let lastLoginUtc: String
    let registeredUtc: String
    let roles: [String]
    let passwordManagerSalt: String
    let accountLocked: Bool
    let photo: String?
    let storageQuota: Int64
    let usedStorage: Int64
    let loginEnabled: Bool
    let hasContacts: Bool
    let hasDiary: Bool
    let hasNotes: Bool
    let hasPasswordManagerFile: Bool
    let secKey: String
}

struct AuthenticationResponse: Decodable {
    let token: String?
    let requiresPass2: Bool
    let requiresPin: Bool
    let longLivedToken: String?
    let username: String?
}

struct AuthSession {
    let longLivedToken: String
}

struct ContactData: Codable {
    let nextId: Int64
    let version: Int
    let items: [ContactItem]
}

struct ContactItem: Codable, Identifiable {
    let id: Int64
    var name: String
    var birthday: String
    var phone: String
    var address: String
    var email: String
    var note: String
}

enum ServiceError: LocalizedError {
    case emptyCredentials
    case invalidCredentials
    case twoFactorCodeRequired
    case twoFactorTokenMissing
    case invalidURL
    case networkError
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .emptyCredentials:
            return "Username and password are required."
        case .twoFactorCodeRequired:
            return "Second factor code is required."
        case .twoFactorTokenMissing:
            return "Second factor token is missing."
        case .invalidURL:
            return "The authentication URL is invalid."
        case .networkError:
            return "Authentication request failed. Please check your network connection."
        case .invalidCredentials:
            return "Invalid credentials."
        case .serverError(let message):
            return message
        case .decodingError:
            return "Could not parse the authentication response."
        }
    }
}

protocol Servicing {

    // authentication

    func authenticate(username: String, password: String) async throws -> AuthenticationResponse

    func authenticateLongLivedToken(longLivedToken: String) async throws -> AuthenticationResponse

    func completeSecondFactor(token: String, secondFactorCode: String) async throws
        -> AuthenticationResponse

    func getUserInfo(token: String) async throws -> UserInfoResponse

    func completePin(longLivedToken: String, pin: String) async throws -> AuthenticationResponse

    func logout(token: String) async throws

    // contacts

    func loadEncodedContacts(token: String) async throws -> String

    func saveEncodedContacts(token: String, encodedContacts: String) async throws

    func decodeContactText(encrypted: String, encryptionKey: String, passwordManagerSalt: String)
        throws -> String

    func encodeContactText(text: String, encryptionKey: String, passwordManagerSalt: String)
        throws -> String

    func getContactItems(
        token: String,
        encryptionKey: String,
        passwordManagerSalt: String
    ) async throws -> [ContactItem]

    func uploadContactItems(
        token: String,
        contactItems: [ContactItem],
        encryptionKey: String,
        passwordManagerSalt: String
    ) async throws

    // error translations

    func initializeTranslations(locale: String) async throws

    func translate(symbol: String) -> String
}

struct ClientIdentity {
    let uuid: String
    let name: String
}

final class ClientIdentityStore {
    static let shared = ClientIdentityStore()

    private enum Keys {
        static let clientUUID = "mynaswift.client.uuid"
        static let clientName = "mynaswift.client.name"
    }

    private let defaults = UserDefaults.standard
    private let fixedClientName = "MynaSwift"

    private init() {}

    func loadOrCreateIdentity() -> ClientIdentity {
        let storedUUID = defaults.string(forKey: Keys.clientUUID)
        if let storedUUID,
            UUID(uuidString: storedUUID) != nil
        {
            if defaults.string(forKey: Keys.clientName) != fixedClientName {
                defaults.set(fixedClientName, forKey: Keys.clientName)
            }
            return ClientIdentity(uuid: storedUUID, name: fixedClientName)
        }
        let newUUID = UUID().uuidString
        defaults.set(newUUID, forKey: Keys.clientUUID)
        defaults.set(fixedClientName, forKey: Keys.clientName)
        return ClientIdentity(uuid: newUUID, name: fixedClientName)
    }
}

final class AuthSessionStore {
    static let shared = AuthSessionStore()

    private enum Keys {
        static let longLivedToken = "mynaswift.session.longLivedToken"
        static let keepLoginEnabled = "mynaswift.session.keepLoginEnabled"
        static let encryptedSecurityKeyPrefix = "mynaswift.session.encryptedSecurityKey"
    }

    private let defaults = UserDefaults.standard

    private init() {}

    var keepLoginEnabled: Bool {
        defaults.object(forKey: Keys.keepLoginEnabled) as? Bool ?? true
    }

    func setKeepLoginEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.keepLoginEnabled)
    }

    func persistSession(from response: AuthenticationResponse, keepLogin: Bool) {
        setKeepLoginEnabled(keepLogin)
        guard keepLogin else {
            clear()
            return
        }
        save(from: response)
    }

    func save(from response: AuthenticationResponse) {
        guard let longLivedToken = response.longLivedToken,
            !longLivedToken.isEmpty
        else {
            return
        }
        defaults.set(longLivedToken, forKey: Keys.longLivedToken)
    }

    func load() -> AuthSession? {
        guard let token = defaults.string(forKey: Keys.longLivedToken),
            !token.isEmpty
        else {
            return nil
        }
        return AuthSession(longLivedToken: token)
    }

    func saveDataProtectionSecurityKey(
        _ securityKey: String,
        userID: Int64,
        passwordManagerSalt: String
    ) {
        guard !securityKey.isEmpty,
            !passwordManagerSalt.isEmpty
        else {
            clearDataProtectionSecurityKey(userID: userID)
            return
        }
        do {
            let symmetricKey = try deriveSymmetricKey(passwordManagerSalt: passwordManagerSalt)
            let plaintext = Data(securityKey.utf8)
            let sealed = try AES.GCM.seal(plaintext, using: symmetricKey)
            guard let combined = sealed.combined else {
                clearDataProtectionSecurityKey(userID: userID)
                return
            }
            defaults.set(
                combined.base64EncodedString(), forKey: encryptedSecurityStorageKey(userID: userID))
        } catch {
            clearDataProtectionSecurityKey(userID: userID)
        }
    }

    func loadDataProtectionSecurityKey(userID: Int64, passwordManagerSalt: String) -> String? {
        guard !passwordManagerSalt.isEmpty,
            let encrypted = defaults.string(forKey: encryptedSecurityStorageKey(userID: userID)),
            let encryptedData = Data(base64Encoded: encrypted)
        else {
            return nil
        }
        do {
            let symmetricKey = try deriveSymmetricKey(passwordManagerSalt: passwordManagerSalt)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func clearDataProtectionSecurityKey(userID: Int64) {
        defaults.removeObject(forKey: encryptedSecurityStorageKey(userID: userID))
    }

    func clear() {
        defaults.removeObject(forKey: Keys.longLivedToken)
    }

    private func encryptedSecurityStorageKey(userID: Int64) -> String {
        "\(Keys.encryptedSecurityKeyPrefix).\(userID)"
    }

    private func deriveSymmetricKey(passwordManagerSalt: String) throws -> SymmetricKey {
        guard !passwordManagerSalt.isEmpty else {
            throw ServiceError.serverError("Missing password manager salt.")
        }
        let hash = SHA256.hash(data: Data(passwordManagerSalt.utf8))
        return SymmetricKey(data: Data(hash))
    }
}

struct RemoteService: Servicing {
    private let baseURL = URL(string: "https://www.stockfleth.eu")
    private static let translationQueue = DispatchQueue(
        label: "mynaswift.translation.map", attributes: .concurrent)
    private static var translationMap: [String: String]?

    func initializeTranslations(locale: String) async throws {
        let localeURLRequest = URLRequest(
            url: URL(string: "/api/pwdman/locale/url/\(locale)", relativeTo: baseURL)!)
        let (localeData, localeResponse) = try await URLSession.shared.data(for: localeURLRequest)
        try checkResponse(localeResponse, data: localeData)
        let localeURLString = try JSONDecoder().decode(String.self, from: localeData)
        let translationURL: URL
        if let absoluteURL = URL(string: localeURLString), absoluteURL.scheme != nil {
            translationURL = absoluteURL
        } else {
            guard let relativeURL = URL(string: localeURLString, relativeTo: baseURL)?.absoluteURL
            else {
                throw ServiceError.invalidURL
            }
            translationURL = relativeURL
        }
        let translationRequest = URLRequest(url: translationURL)
        let (translationData, translationResponse) = try await URLSession.shared.data(
            for: translationRequest)
        try checkResponse(translationResponse, data: translationData)
        let map = try JSONDecoder().decode([String: String].self, from: translationData)
        Self.translationQueue.sync(flags: .barrier) {
            Self.translationMap = map
        }
    }

    func translate(symbol: String) -> String {
        let map = Self.translationQueue.sync {
            Self.translationMap
        }
        guard let map else {
            return symbol
        }
        let components = symbol.split(separator: ":", omittingEmptySubsequences: false).map(
            String.init)
        if components.count > 1 {
            guard var format = map[components[0]] else {
                return symbol
            }
            for index in 1..<components.count {
                format = format.replacingOccurrences(of: "{\(index - 1)}", with: components[index])
            }
            return format
        }
        return map[symbol] ?? symbol
    }

    func authenticate(username: String, password: String) async throws -> AuthenticationResponse {
        let clientIdentity: ClientIdentity = ClientIdentityStore.shared.loadOrCreateIdentity()
        var urlRequest = URLRequest(url: URL(string: "/api/pwdman/auth", relativeTo: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = AuthenticationRequest(
            username: username,
            password: password,
            clientUUID: clientIdentity.uuid,
            clientName: clientIdentity.name
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(AuthenticationResponse.self, from: data)
    }

    func completeSecondFactor(token: String, secondFactorCode: String) async throws
        -> AuthenticationResponse
    {
        var urlRequest = URLRequest(url: URL(string: "/api/pwdman/auth2", relativeTo: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(token, forHTTPHeaderField: "token")
        urlRequest.httpBody = try JSONEncoder().encode(secondFactorCode)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(AuthenticationResponse.self, from: data)
    }

    func authenticateLongLivedToken(longLivedToken: String) async throws -> AuthenticationResponse {
        let clientIdentity: ClientIdentity = ClientIdentityStore.shared.loadOrCreateIdentity()
        var urlRequest = URLRequest(
            url: URL(string: "/api/pwdman/auth/lltoken", relativeTo: baseURL)!)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(longLivedToken, forHTTPHeaderField: "token")
        urlRequest.setValue(clientIdentity.uuid, forHTTPHeaderField: "uuid")
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(AuthenticationResponse.self, from: data)
    }

    func completePin(longLivedToken: String, pin: String) async throws -> AuthenticationResponse {
        var urlRequest = URLRequest(url: URL(string: "/api/pwdman/auth/pin", relativeTo: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(longLivedToken, forHTTPHeaderField: "token")
        urlRequest.httpBody = try JSONEncoder().encode(pin)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(AuthenticationResponse.self, from: data)
    }

    func getUserInfo(token: String) async throws -> UserInfoResponse {
        var urlRequest = URLRequest(
            url: URL(string: "/api/pwdman/user?details=true", relativeTo: baseURL)!)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(UserInfoResponse.self, from: data)
    }

    func logout(token: String) async throws {
        var urlRequest = URLRequest(
            url: URL(string: "/api/pwdman/logout", relativeTo: baseURL)!)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)
    }

    func loadEncodedContacts(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "/api/contacts", relativeTo: baseURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(String.self, from: data)
    }

    func saveEncodedContacts(token: String, encodedContacts: String) async throws {
        var request = URLRequest(url: URL(string: "/api/contacts", relativeTo: baseURL)!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        request.httpBody = try JSONEncoder().encode(encodedContacts)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
    }

    func decodeContactText(encrypted: String, encryptionKey: String, passwordManagerSalt: String)
        throws -> String
    {
        guard !encrypted.isEmpty else {
            return ""
        }
        let cryptoKey = try deriveCryptoKey(
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt)
        let encryptedData = try Data(hexString: encrypted)
        let plainData = try decryptData(encryptedData, key: cryptoKey)
        return String(data: plainData, encoding: .utf8) ?? ""
    }

    func encodeContactText(text: String, encryptionKey: String, passwordManagerSalt: String)
        throws -> String
    {
        let cryptoKey = try deriveCryptoKey(
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt)
        let plainData = Data(text.utf8)
        let encryptedData = try encryptData(plainData, key: cryptoKey)
        return encryptedData.hexUppercasedString
    }

    func getContactItems(
        token: String,
        encryptionKey: String,
        passwordManagerSalt: String
    ) async throws -> [ContactItem] {
        guard !encryptionKey.isEmpty else {
            throw ServiceError.serverError("No data protection key configured.")
        }
        let encrypted = try await loadEncodedContacts(token: token)
        guard !encrypted.isEmpty else {
            return []
        }
        let json = try decodeContactText(
            encrypted: encrypted,
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt)
        let payload = try JSONDecoder().decode(ContactData.self, from: Data(json.utf8))
        return payload.items
    }

    func uploadContactItems(
        token: String,
        contactItems: [ContactItem],
        encryptionKey: String,
        passwordManagerSalt: String
    ) async throws {
        guard !encryptionKey.isEmpty else {
            throw ServiceError.serverError("No data protection key configured.")
        }
        let sortedItems = contactItems.sorted { $0.id < $1.id }
        let nextId = (sortedItems.map(\.id).max() ?? 0) + 1
        let payload = ContactData(nextId: nextId, version: 1, items: sortedItems)
        let jsonData = try JSONEncoder().encode(payload)
        let jsonString =
            String(data: jsonData, encoding: .utf8) ?? "{\"nextId\":1,\"version\":1,\"items\":[]}"
        let encoded = try encodeContactText(
            text: jsonString,
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt)
        try await saveEncodedContacts(token: token, encodedContacts: encoded)
    }

    private func deriveCryptoKey(encryptionKey: String, passwordManagerSalt: String) throws -> Data
    {
        guard !encryptionKey.isEmpty, !passwordManagerSalt.isEmpty else {
            throw ServiceError.serverError("Missing encryption key configuration.")
        }
        let keyLength = kCCKeySizeAES256
        var derivedKey = Data(repeating: 0, count: keyLength)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            passwordManagerSalt.withCString { saltCString in
                encryptionKey.withCString { passwordCString in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordCString,
                        encryptionKey.lengthOfBytes(using: .utf8),
                        UnsafePointer<UInt8>(OpaquePointer(saltCString)),
                        passwordManagerSalt.lengthOfBytes(using: .utf8),
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        1000,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw ServiceError.serverError("Could not derive encryption key.")
        }
        return derivedKey
    }

    private func encryptData(_ plainData: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(plainData, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw ServiceError.serverError("Could not encrypt contact data.")
        }
        return combined
    }

    private func decryptData(_ encryptedData: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw ServiceError.serverError("Invalid data protection key.")
        }
    }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.networkError
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
                let message = apiError.title,
                !message.isEmpty
            {
                throw ServiceError.serverError(translate(symbol: message))
            }
            throw ServiceError.serverError(
                "Server responded with status code \(httpResponse.statusCode).")
        }
    }
}

private struct AuthenticationRequest: Encodable {
    let username: String
    let password: String
    let clientUUID: String
    let clientName: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case password = "Password"
        case clientUUID = "ClientUUID"
        case clientName = "ClientName"
    }
}

private struct APIErrorResponse: Decodable {
    let title: String?
    let status: Int?
}

extension Data {
    fileprivate init(hexString: String) throws {
        guard hexString.count.isMultiple(of: 2) else {
            throw ServiceError.decodingError
        }
        var data = Data()
        data.reserveCapacity(hexString.count / 2)

        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]
            guard let value = UInt8(byteString, radix: 16) else {
                throw ServiceError.decodingError
            }
            data.append(value)
            index = nextIndex
        }
        self = data
    }

    fileprivate var hexUppercasedString: String {
        self.map { String(format: "%02X", $0) }.joined()
    }
}
