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

struct Note: Codable, Identifiable {
    let id: Int64
    var title: String
    var content: String?
    var lastModifiedUtc: String?
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

    // notes

    func getNotes(token: String, encryptionKey: String, passwordManagerSalt: String) async throws
        -> [Note]

    func getNote(token: String, id: Int64, encryptionKey: String, passwordManagerSalt: String)
        async throws -> Note

    func createNewNote(
        token: String, title: String, encryptionKey: String, passwordManagerSalt: String
    ) async throws -> Int64

    func deleteNote(token: String, id: Int64) async throws

    func updateNote(
        token: String, id: Int64, title: String, content: String, encryptionKey: String,
        passwordManagerSalt: String
    ) async throws -> String

    // contacts

    func loadContacts(token: String, encryptionKey: String, passwordManagerSalt: String)
        async throws
        -> [ContactItem]

    func saveContacts(
        token: String, contacts: [ContactItem], encryptionKey: String, passwordManagerSalt: String)
        async throws

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

    private let defaults: UserDefaults
    private let cryptoService: CryptoServicing

    init(
        defaults: UserDefaults = .standard,
        cryptoService: CryptoServicing = CryptoService.shared
    ) {
        self.defaults = defaults
        self.cryptoService = cryptoService
    }

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
            let combined = try cryptoService.encryptSecurityKey(
                securityKey,
                passwordManagerSalt: passwordManagerSalt)
            defaults.set(
                combined,
                forKey: encryptedSecurityStorageKey(userID: userID))
        } catch {
            clearDataProtectionSecurityKey(userID: userID)
        }
    }

    func loadDataProtectionSecurityKey(userID: Int64, passwordManagerSalt: String) -> String? {
        guard !passwordManagerSalt.isEmpty,
            let encrypted = defaults.string(forKey: encryptedSecurityStorageKey(userID: userID))
        else {
            return nil
        }
        do {
            return try cryptoService.decryptSecurityKey(
                encrypted,
                passwordManagerSalt: passwordManagerSalt)
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
}

struct RemoteService: Servicing {
    private let baseURL: URL?
    private let cryptoService: CryptoServicing
    private static let translationQueue = DispatchQueue(
        label: "mynaswift.translation.map", attributes: .concurrent)
    private static var translationMap: [String: String]?

    init(
        baseURL: URL? = URL(string: "https://www.stockfleth.eu"),
        cryptoService: CryptoServicing = CryptoService.shared
    ) {
        self.baseURL = baseURL
        self.cryptoService = cryptoService
    }

    // error message translations

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

    // authentication

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

    // notes

    func getNotes(token: String, encryptionKey: String, passwordManagerSalt: String) async throws
        -> [Note]
    {
        var request = URLRequest(url: URL(string: "/api/notes/note", relativeTo: baseURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        let encryptedNotes = try JSONDecoder().decode([Note].self, from: data)
        return try encryptedNotes.map { note in
            try decodeNoteFields(
                note,
                encryptionKey: encryptionKey,
                passwordManagerSalt: passwordManagerSalt,
                includeContent: false)
        }
    }

    func getNote(token: String, id: Int64, encryptionKey: String, passwordManagerSalt: String)
        async throws -> Note
    {
        var request = URLRequest(url: URL(string: "/api/notes/note/\(id)", relativeTo: baseURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        let encryptedNote = try JSONDecoder().decode(Note.self, from: data)
        return try decodeNoteFields(
            encryptedNote,
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt,
            includeContent: true)
    }

    func createNewNote(
        token: String, title: String, encryptionKey: String, passwordManagerSalt: String
    )
        async throws -> Int64
    {
        let encryptedTitle = try cryptoService.encryptText(
            title, encryptionKey: encryptionKey, passwordManagerSalt: passwordManagerSalt)
        var request = URLRequest(url: URL(string: "/api/notes/note", relativeTo: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        request.httpBody = try JSONEncoder().encode(CreateNoteRequest(title: encryptedTitle))
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(Int64.self, from: data)
    }

    func deleteNote(token: String, id: Int64) async throws {
        var request = URLRequest(url: URL(string: "/api/notes/note/\(id)", relativeTo: baseURL)!)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
    }

    func updateNote(
        token: String,
        id: Int64,
        title: String,
        content: String,
        encryptionKey: String,
        passwordManagerSalt: String
    ) async throws -> String {
        let encryptedTitle = try cryptoService.encryptText(
            title, encryptionKey: encryptionKey, passwordManagerSalt: passwordManagerSalt)
        let encryptedContent = try cryptoService.encryptText(
            content, encryptionKey: encryptionKey, passwordManagerSalt: passwordManagerSalt)
        var request = URLRequest(url: URL(string: "/api/notes/note", relativeTo: baseURL)!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        request.httpBody = try JSONEncoder().encode(
            UpdateNoteRequest(id: id, title: encryptedTitle, content: encryptedContent))
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(String.self, from: data)
    }

    // contacts

    func loadContacts(
        token: String,
        encryptionKey: String,
        passwordManagerSalt: String
    ) async throws -> [ContactItem] {
        var request = URLRequest(url: URL(string: "/api/contacts", relativeTo: baseURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        let encrypted = try JSONDecoder().decode(String.self, from: data)
        guard !encrypted.isEmpty else {
            return []
        }
        let json = try cryptoService.decryptText(
            encrypted, encryptionKey: encryptionKey, passwordManagerSalt: passwordManagerSalt)
        let payload = try JSONDecoder().decode(ContactData.self, from: Data(json.utf8))
        return payload.items
    }

    func saveContacts(
        token: String,
        contacts: [ContactItem],
        encryptionKey: String,
        passwordManagerSalt: String
    ) async throws {
        guard !encryptionKey.isEmpty else {
            throw ServiceError.noDataProtectionKey
        }
        let sortedItems = contacts.sorted { $0.id < $1.id }
        let nextId = (sortedItems.map(\.id).max() ?? 0) + 1
        let payload = ContactData(nextId: nextId, version: 1, items: sortedItems)
        let jsonData = try JSONEncoder().encode(payload)
        let jsonString =
            String(data: jsonData, encoding: .utf8) ?? "{\"nextId\":1,\"version\":1,\"items\":[]}"
        let encoded = try cryptoService.encryptText(
            jsonString, encryptionKey: encryptionKey, passwordManagerSalt: passwordManagerSalt)
        var request = URLRequest(url: URL(string: "/api/contacts", relativeTo: baseURL)!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "token")
        request.httpBody = try JSONEncoder().encode(encoded)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
    }

    private func decodeNoteFields(
        _ note: Note,
        encryptionKey: String,
        passwordManagerSalt: String,
        includeContent: Bool
    ) throws -> Note {
        var decoded = note
        decoded.title = try cryptoService.decryptText(
            note.title, encryptionKey: encryptionKey, passwordManagerSalt: passwordManagerSalt)
        if includeContent {
            if let encryptedContent = note.content {
                decoded.content = try cryptoService.decryptText(
                    encryptedContent, encryptionKey: encryptionKey,
                    passwordManagerSalt: passwordManagerSalt)
            } else {
                decoded.content = nil
            }
        }
        return decoded
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
            throw ServiceError.serverStatusCode(httpResponse.statusCode)
        }
    }

    private func debugLogResponse(endpoint: String, data: Data) {
        #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8-response>"
            print("[RemoteService] Response \(endpoint): \(body)")
        #endif
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

private struct CreateNoteRequest: Encodable {
    let title: String

    enum CodingKeys: String, CodingKey {
        case title = "Title"
    }
}

private struct UpdateNoteRequest: Encodable {
    let id: Int64
    let title: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case title = "Title"
        case content = "Content"
    }
}

private struct APIErrorResponse: Decodable {
    let title: String?
    let status: Int?
}
