// Copyright 2026 Andrew Voirol
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Security

/// Keychain-based storage for Kaggle API credentials (username + API key).
/// Used by `URLImportManager` when downloading models from Kaggle.
enum KaggleTokenStorage {

    private static let service = "com.andrewvoirol.GemmaEdgeGallery.kaggle-credentials"
    private static let usernameAccount = "kaggle-username"
    private static let apiKeyAccount = "kaggle-api-key"

    // MARK: - Save

    /// Store Kaggle API credentials in the Keychain.
    /// - Parameters:
    ///   - username: The Kaggle username.
    ///   - apiKey: The Kaggle API key.
    /// - Throws: `KaggleTokenError.keychainSaveFailed` if the operation fails.
    static func saveCredentials(username: String, apiKey: String) throws {
        guard let usernameData = username.data(using: .utf8) else {
            throw KaggleTokenError.invalidCredentials
        }
        guard let apiKeyData = apiKey.data(using: .utf8) else {
            throw KaggleTokenError.invalidCredentials
        }

        // Save username
        try saveItem(account: usernameAccount, data: usernameData)

        // Save API key
        try saveItem(account: apiKeyAccount, data: apiKeyData)
    }

    /// Save a single Keychain item, deleting any existing value first.
    private static func saveItem(account: String, data: Data) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KaggleTokenError.keychainSaveFailed(status: status)
        }
    }

    // MARK: - Retrieve

    /// Retrieve the stored Kaggle username from the Keychain.
    /// - Returns: The username string, or nil if not stored.
    static func retrieveUsername() -> String? {
        retrieveItem(account: usernameAccount)
    }

    /// Retrieve the stored Kaggle API key from the Keychain.
    /// - Returns: The API key string, or nil if not stored.
    static func retrieveAPIKey() -> String? {
        retrieveItem(account: apiKeyAccount)
    }

    /// Retrieve a single Keychain item by account.
    private static func retrieveItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    // MARK: - Delete

    /// Remove all stored Kaggle credentials from the Keychain.
    static func deleteCredentials() {
        // Delete username
        let usernameQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: usernameAccount,
        ]
        SecItemDelete(usernameQuery as CFDictionary)

        // Delete API key
        let apiKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
        ]
        SecItemDelete(apiKeyQuery as CFDictionary)
    }

    // MARK: - Convenience

    /// Whether Kaggle credentials are currently stored.
    static var hasCredentials: Bool {
        retrieveUsername() != nil && retrieveAPIKey() != nil
    }
}

// MARK: - Errors

enum KaggleTokenError: LocalizedError {
    case invalidCredentials
    case keychainSaveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials: could not encode as UTF-8."
        case .keychainSaveFailed(let status):
            return "Keychain save failed with status \(status)."
        }
    }
}
