import Foundation
import Security

enum KeychainStore {
    // Keep items created by earlier ad-hoc signed builds separate. Their ACLs
    // may require the old executable and can prompt on access after rebuilding.
    private static let service = "com.easyask.deepseek.v3"
    private static let legacyServices = ["com.easyask.deepseek.v2", "com.easyask.deepseek"]
    private static let account = "api-key"

    static func load() throws -> String? {
        try read(service: service)
    }

    static func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query = itemQuery(service: service)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainStoreError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainStoreError.status(status)
        }
    }

    static var hasLegacyItem: Bool {
        legacyServices.contains { legacyService in
            var query = itemQuery(service: legacyService)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
        }
    }

    private static func read(service: String) throws -> String? {
        var query = itemQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError.status(status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }
        return value
    }

    private static func itemQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

enum KeychainStoreError: LocalizedError {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .status(let code):
            let detail = SecCopyErrorMessageString(code, nil) as String? ?? "未知错误"
            return "钥匙串错误（\(code)）：\(detail)"
        case .invalidData:
            return "钥匙串中的密钥格式无法识别。"
        }
    }
}
