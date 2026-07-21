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

import Testing
import Foundation
import Security
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite("HFTokenStorage & HFTokenError", .serialized)
struct HFTokenStorageSwiftTests {

    // MARK: - HFTokenError

    @Suite("HFTokenError descriptions")
    struct HFTokenErrorTests {
        @Test("invalidToken has description")
        func invalidToken() {
            let error = HFTokenError.invalidToken
            #expect(error.errorDescription?.contains("Invalid token") == true)
        }

        @Test("keychainSaveFailed includes status code")
        func keychainSaveFailed() {
            let error = HFTokenError.keychainSaveFailed(status: -25300)
            #expect(error.errorDescription?.contains("-25300") == true)
        }
    }

    // MARK: - HFTokenStorage Keychain Operations

    @Suite("Keychain operations", .serialized)
    struct KeychainTests {

        init() throws {
            // Probe Keychain accessibility — CI simulators may sandbox or block Keychain ops.
            let probeQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.edgeailab.test.keychain-probe",
                kSecValueData as String: Data("probe".utf8),
            ]
            SecItemDelete(probeQuery as CFDictionary)
            let status = SecItemAdd(probeQuery as CFDictionary, nil)
            SecItemDelete(probeQuery as CFDictionary)
            try #require(status == errSecSuccess, "Skipped — Keychain not accessible (status: \(status))")
        }
        @Test("Save and retrieve round-trip")
        func saveAndRetrieve() throws {
            // Clean up any existing token
            HFTokenStorage.delete()

            let testToken = "hf_test_token_\(UUID().uuidString.prefix(8))"
            try HFTokenStorage.save(token: testToken)

            let retrieved = HFTokenStorage.retrieve()
            #expect(retrieved == testToken)

            // Cleanup
            HFTokenStorage.delete()
        }

        @Test("hasToken returns true after save")
        func hasTokenAfterSave() throws {
            HFTokenStorage.delete()
            try HFTokenStorage.save(token: "hf_test_token")
            #expect(HFTokenStorage.hasToken == true)
            HFTokenStorage.delete()
        }

        @Test("hasToken returns false after delete")
        func hasTokenAfterDelete() {
            HFTokenStorage.delete()
            #expect(HFTokenStorage.hasToken == false)
        }

        @Test("retrieve returns nil when no token stored")
        func retrieveWhenEmpty() {
            HFTokenStorage.delete()
            #expect(HFTokenStorage.retrieve() == nil)
        }

        @Test("Save overwrites existing token")
        func saveOverwrites() throws {
            HFTokenStorage.delete()
            try HFTokenStorage.save(token: "old_token")
            try HFTokenStorage.save(token: "new_token")
            #expect(HFTokenStorage.retrieve() == "new_token")
            HFTokenStorage.delete()
        }

        @Test("Delete is idempotent")
        func deleteIdempotent() {
            HFTokenStorage.delete()
            HFTokenStorage.delete() // Should not throw
            #expect(HFTokenStorage.hasToken == false)
        }
    }
}
