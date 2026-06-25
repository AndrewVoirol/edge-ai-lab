// Copyright 2026 Andrew Voirol. Apache-2.0
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

/// Keychain-based storage for HuggingFace API tokens.
/// Used by `ModelDownloadManager` when downloading gated models that return 401.
enum HFTokenStorage {

    private static let service = "com.andrewvoirol.EdgeAILab.hf-token"
    private static let account = "huggingface-api-token"

    // MARK: - Save

    /// Store a HuggingFace API token in the Keychain.
    /// - Parameter token: The HuggingFace bearer token string.
    /// - Throws: `HFTokenError.keychainSaveFailed` if the operation fails.
    static func save(token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw HFTokenError.invalidToken
        }

        // Delete any existing token first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new token
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw HFTokenError.keychainSaveFailed(status: status)
        }
    }

    // MARK: - Retrieve

    /// Retrieve the stored HuggingFace API token from the Keychain.
    /// - Returns: The token string, or nil if no token is stored.
    static func retrieve() -> String? {
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
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    // MARK: - Delete

    /// Remove the stored HuggingFace API token from the Keychain.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Convenience

    /// Whether a HuggingFace token is currently stored.
    static var hasToken: Bool {
        retrieve() != nil
    }
}

// MARK: - Errors

enum HFTokenError: LocalizedError {
    case invalidToken
    case keychainSaveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Invalid token: could not encode as UTF-8."
        case .keychainSaveFailed(let status):
            return "Keychain save failed with status \(status)."
        }
    }
}
