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
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - KaggleTokenStorage Tests

@Suite("KaggleTokenStorage", .serialized)
struct KaggleTokenStorageSwiftTests {

    // Clean Keychain state before each test to avoid cross-test contamination.
    init() {
        KaggleTokenStorage.deleteCredentials()
    }

    @Test("Save then retrieve username matches")
    func saveAndRetrieveUsername() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        try KaggleTokenStorage.saveCredentials(username: "testuser", apiKey: "abc123key")

        let retrieved = KaggleTokenStorage.retrieveUsername()
        #expect(retrieved == "testuser")
    }

    @Test("Save then retrieve API key matches")
    func saveAndRetrieveAPIKey() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        try KaggleTokenStorage.saveCredentials(username: "testuser", apiKey: "abc123key")

        let retrieved = KaggleTokenStorage.retrieveAPIKey()
        #expect(retrieved == "abc123key")
    }

    @Test("hasCredentials is true after save")
    func hasCredentialsTrueAfterSave() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        try KaggleTokenStorage.saveCredentials(username: "user", apiKey: "key")

        #expect(KaggleTokenStorage.hasCredentials == true)
    }

    @Test("hasCredentials is false after delete")
    func hasCredentialsFalseAfterDelete() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        try KaggleTokenStorage.saveCredentials(username: "user", apiKey: "key")
        KaggleTokenStorage.deleteCredentials()

        #expect(KaggleTokenStorage.hasCredentials == false)
    }

    @Test("deleteCredentials removes both username and API key")
    func deleteRemovesBoth() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        try KaggleTokenStorage.saveCredentials(username: "user", apiKey: "key")
        KaggleTokenStorage.deleteCredentials()

        #expect(KaggleTokenStorage.retrieveUsername() == nil)
        #expect(KaggleTokenStorage.retrieveAPIKey() == nil)
    }

    @Test("retrieveUsername returns nil when no credentials stored")
    func retrieveUsernameNilWhenEmpty() {
        defer { KaggleTokenStorage.deleteCredentials() }

        #expect(KaggleTokenStorage.retrieveUsername() == nil)
    }

    @Test("retrieveAPIKey returns nil when no credentials stored")
    func retrieveAPIKeyNilWhenEmpty() {
        defer { KaggleTokenStorage.deleteCredentials() }

        #expect(KaggleTokenStorage.retrieveAPIKey() == nil)
    }

    @Test("Save overwrites previous credentials")
    func saveOverwritesPrevious() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        try KaggleTokenStorage.saveCredentials(username: "first", apiKey: "key1")
        try KaggleTokenStorage.saveCredentials(username: "second", apiKey: "key2")

        #expect(KaggleTokenStorage.retrieveUsername() == "second")
        #expect(KaggleTokenStorage.retrieveAPIKey() == "key2")
    }

    @Test("Save with special characters (emoji, spaces, unicode)")
    func saveSpecialCharacters() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        let specialUser = "user 🚀 名前"
        let specialKey = "key™ © 42 — ñ"
        try KaggleTokenStorage.saveCredentials(username: specialUser, apiKey: specialKey)

        #expect(KaggleTokenStorage.retrieveUsername() == specialUser)
        #expect(KaggleTokenStorage.retrieveAPIKey() == specialKey)
    }

    @Test("Save with empty strings succeeds")
    func saveEmptyStrings() throws {
        defer { KaggleTokenStorage.deleteCredentials() }

        try KaggleTokenStorage.saveCredentials(username: "", apiKey: "")

        // Empty strings are valid UTF-8, so save should succeed.
        // However hasCredentials checks for non-nil retrieval; empty Data
        // round-trips to empty String which is non-nil.
        #expect(KaggleTokenStorage.retrieveUsername() == "")
        #expect(KaggleTokenStorage.retrieveAPIKey() == "")
        #expect(KaggleTokenStorage.hasCredentials == true)
    }
}

// MARK: - KaggleTokenError Tests

@Suite("KaggleTokenError")
struct KaggleTokenErrorTests {

    @Test("invalidCredentials has non-nil errorDescription")
    func invalidCredentialsDescription() {
        let error = KaggleTokenError.invalidCredentials
        #expect(error.errorDescription != nil)
    }

    @Test("keychainSaveFailed errorDescription contains the status code")
    func keychainSaveFailedContainsStatus() {
        let status: OSStatus = -25299 // errSecDuplicateItem
        let error = KaggleTokenError.keychainSaveFailed(status: status)

        let description = error.errorDescription
        #expect(description != nil)
        #expect(description!.contains("-25299"))
    }

    @Test("invalidCredentials description is human-readable")
    func invalidCredentialsHumanReadable() {
        let error = KaggleTokenError.invalidCredentials
        let description = error.errorDescription!

        // Should mention what went wrong in plain language
        #expect(description.contains("UTF-8") || description.lowercased().contains("credential"))
    }

    @Test("keychainSaveFailed description is human-readable")
    func keychainSaveFailedHumanReadable() {
        let error = KaggleTokenError.keychainSaveFailed(status: -25300)
        let description = error.errorDescription!

        // Should mention Keychain and the status
        #expect(description.lowercased().contains("keychain"))
        #expect(description.contains("-25300"))
    }
}
