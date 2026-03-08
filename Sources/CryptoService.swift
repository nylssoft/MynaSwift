import CommonCrypto
import CryptoKit
import Foundation

protocol CryptoServicing {
    func encryptSecurityKey(_ securityKey: String, passwordManagerSalt: String) throws
        -> String
    func decryptSecurityKey(_ encryptedSecurityKey: String, passwordManagerSalt: String)
        throws -> String
    func encryptText(_ text: String, encryptionKey: String, passwordManagerSalt: String)
        throws -> String
    func decryptText(_ encrypted: String, encryptionKey: String, passwordManagerSalt: String)
        throws -> String
    func encryptBinaryData(_ plainData: Data, encryptionKey: String, passwordManagerSalt: String)
        throws -> Data
    func decryptBinaryData(
        _ encryptedData: Data,
        encryptionKey: String,
        passwordManagerSalt: String
    ) throws -> Data
}

struct CryptoService: CryptoServicing {
    static let shared = CryptoService()

    private init() {}

    func encryptSecurityKey(_ securityKey: String, passwordManagerSalt: String) throws
        -> String
    {
        let symmetricKey = try deriveSaltSymmetricKey(passwordManagerSalt: passwordManagerSalt)
        let plaintext = Data(securityKey.utf8)
        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealed.combined else {
            throw ServiceError.encryptData
        }
        return combined.base64EncodedString()
    }

    func decryptSecurityKey(_ encryptedSecurityKey: String, passwordManagerSalt: String)
        throws -> String
    {
        guard let encryptedData = Data(base64Encoded: encryptedSecurityKey) else {
            throw ServiceError.decodingError
        }
        let symmetricKey = try deriveSaltSymmetricKey(passwordManagerSalt: passwordManagerSalt)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }

    func encryptText(_ text: String, encryptionKey: String, passwordManagerSalt: String)
        throws -> String
    {
        let cryptoKey = try deriveCryptoKey(
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt)
        let plainData = Data(text.utf8)
        let encryptedData = try encryptData(plainData, key: cryptoKey)
        return encryptedData.hexUppercasedString
    }

    func decryptText(_ encrypted: String, encryptionKey: String, passwordManagerSalt: String)
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

    func encryptBinaryData(_ plainData: Data, encryptionKey: String, passwordManagerSalt: String)
        throws -> Data
    {
        let cryptoKey = try deriveCryptoKey(
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt)
        return try encryptData(plainData, key: cryptoKey)
    }

    func decryptBinaryData(
        _ encryptedData: Data,
        encryptionKey: String,
        passwordManagerSalt: String
    ) throws -> Data {
        let cryptoKey = try deriveCryptoKey(
            encryptionKey: encryptionKey,
            passwordManagerSalt: passwordManagerSalt)
        return try decryptData(encryptedData, key: cryptoKey)
    }

    private func deriveSaltSymmetricKey(passwordManagerSalt: String) throws -> SymmetricKey {
        guard !passwordManagerSalt.isEmpty else {
            throw ServiceError.missingPasswordManagerSalt
        }
        let hash = SHA256.hash(data: Data(passwordManagerSalt.utf8))
        return SymmetricKey(data: Data(hash))
    }

    private func deriveCryptoKey(encryptionKey: String, passwordManagerSalt: String) throws
        -> Data
    {
        guard !encryptionKey.isEmpty, !passwordManagerSalt.isEmpty else {
            throw ServiceError.missingEncryptionKeyConfig
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
            throw ServiceError.deriveEncryptionKey
        }
        return derivedKey
    }

    private func encryptData(_ plainData: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(plainData, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw ServiceError.encryptData
        }
        return combined
    }

    private func decryptData(_ encryptedData: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw ServiceError.invalidDataProtectionKey
        }
    }
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
