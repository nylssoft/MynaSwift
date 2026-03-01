import Foundation

struct AuthenticationRequest {
    let username: String
    let password: String
    let clientUUID: String
    let clientName: String
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
    func authenticate(_ request: AuthenticationRequest) async throws -> AuthenticationResponse
    func completeSecondFactor(token: String, secondFactorCode: String) async throws -> AuthenticationResponse
    func makeRequest(username: String, password: String) throws -> AuthenticationRequest
    func validateStoredSession(_ session: AuthSession) async throws -> Bool
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
           UUID(uuidString: storedUUID) != nil {
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
              !longLivedToken.isEmpty else {
            return
        }

        defaults.set(longLivedToken, forKey: Keys.longLivedToken)
    }

    func load() -> AuthSession? {
        guard let token = defaults.string(forKey: Keys.longLivedToken),
              !token.isEmpty else {
            return nil
        }

        return AuthSession(longLivedToken: token)
    }

    func clear() {
        defaults.removeObject(forKey: Keys.longLivedToken)
    }
}

struct RemoteAuthenticationService: AuthenticationServicing {
    private let endpoint = URL(string: "https://www.stockfleth.eu/api/pwdman/auth")
    private let secondFactorEndpoint = URL(string: "https://www.stockfleth.eu/api/pwdman/auth2")

    func makeRequest(username: String, password: String) throws -> AuthenticationRequest {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !password.isEmpty else {
            throw AuthenticationError.emptyCredentials
        }

        let clientIdentity = ClientIdentityStore.shared.loadOrCreateIdentity()
        return AuthenticationRequest(
            username: username,
            password: password,
            clientUUID: clientIdentity.uuid,
            clientName: clientIdentity.name
        )
    }

    func authenticate(_ request: AuthenticationRequest) async throws -> AuthenticationResponse {
        try await send(request)
    }

    func completeSecondFactor(token: String, secondFactorCode: String) async throws -> AuthenticationResponse {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSecondFactorCode = secondFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedToken.isEmpty else {
            throw AuthenticationError.twoFactorTokenMissing
        }

        guard !normalizedSecondFactorCode.isEmpty else {
            throw AuthenticationError.twoFactorCodeRequired
        }

        guard let secondFactorEndpoint else {
            throw AuthenticationError.invalidURL
        }

        var urlRequest = URLRequest(url: secondFactorEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(normalizedToken, forHTTPHeaderField: "token")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(normalizedSecondFactorCode)
        } catch {
            throw AuthenticationError.serverError("Failed to encode second factor request.")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw AuthenticationError.networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.networkError
        }

        let responseBodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 response body>"
        let maskedResponseBodyString = Self.maskTokenValues(in: responseBodyString)
        print("Second factor response body: \(maskedResponseBodyString)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let message = apiError.title,
               !message.isEmpty {
                throw AuthenticationError.serverError(message)
            }

            throw AuthenticationError.serverError("Server responded with status code \(httpResponse.statusCode).")
        }

        do {
            return try JSONDecoder().decode(AuthenticationResponse.self, from: data)
        } catch {
            let decodingMessage: String
            if let decodingError = error as? DecodingError {
                decodingMessage = String(describing: decodingError)
            } else {
                decodingMessage = error.localizedDescription
            }
            throw AuthenticationError.serverError("Could not parse second factor response: \(decodingMessage). Raw body: \(maskedResponseBodyString)")
        }
    }

    func validateStoredSession(_ session: AuthSession) async throws -> Bool {
        false
    }

    private func send(_ request: AuthenticationRequest) async throws -> AuthenticationResponse {
        guard let endpoint else {
            throw AuthenticationError.invalidURL
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AuthenticationRequestPayload(
            username: request.username,
            password: request.password,
            clientUUID: request.clientUUID,
            clientName: request.clientName
        )

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw AuthenticationError.networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.networkError
        }

        let responseBodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 response body>"
        let maskedResponseBodyString = Self.maskTokenValues(in: responseBodyString)
        print("Authentication response body: \(maskedResponseBodyString)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthenticationError.invalidCredentials
            }

            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let message = apiError.title,
               !message.isEmpty {
                throw AuthenticationError.serverError(message)
            }

            throw AuthenticationError.serverError("Server responded with status code \(httpResponse.statusCode).")
        }

        do {
            return try JSONDecoder().decode(AuthenticationResponse.self, from: data)
        } catch {
            let decodingMessage: String
            if let decodingError = error as? DecodingError {
                decodingMessage = String(describing: decodingError)
            } else {
                decodingMessage = error.localizedDescription
            }
            throw AuthenticationError.serverError("Could not parse authentication response: \(decodingMessage). Raw body: \(maskedResponseBodyString)")
        }
    }

    private static func maskTokenValues(in text: String) -> String {
        var maskedText = text
        let patterns = [
            #"("token"\s*:\s*")([^"]*)(")"#,
            #"("longLivedToken"\s*:\s*")([^"]*)(")"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(maskedText.startIndex..<maskedText.endIndex, in: maskedText)
            maskedText = regex.stringByReplacingMatches(
                in: maskedText,
                options: [],
                range: range,
                withTemplate: "$1***$3"
            )
        }

        return maskedText
    }
}

private struct AuthenticationRequestPayload: Encodable {
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
