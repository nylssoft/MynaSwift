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

enum AuthenticationError: LocalizedError {
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

protocol AuthenticationServicing {

    func authenticate(username: String, password: String) async throws -> AuthenticationResponse

    func authenticateLongLivedToken(longLivedToken: String) async throws -> AuthenticationResponse

    func completeSecondFactor(token: String, secondFactorCode: String) async throws
        -> AuthenticationResponse

    func getUserInfo(token: String) async throws -> UserInfoResponse
    
    func completePin(longLivedToken: String, pin: String) async throws -> AuthenticationResponse
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
    }

    private let defaults = UserDefaults.standard

    private init() {}

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

    func clear() {
        defaults.removeObject(forKey: Keys.longLivedToken)
    }
}

struct RemoteAuthenticationService: AuthenticationServicing {
    private let baseURL = URL(string: "https://www.stockfleth.eu")

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
        let responseBodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 response body>"
        print(responseBodyString)
        return try JSONDecoder().decode(UserInfoResponse.self, from: data)
    }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.networkError
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
                let message = apiError.title,
                !message.isEmpty
            {
                throw AuthenticationError.serverError(message)
            }
            throw AuthenticationError.serverError(
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
