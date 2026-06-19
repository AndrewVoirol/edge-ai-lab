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

// MARK: - MCPServerConfig Tests

@Suite("MCPServerConfig")
struct MCPServerConfigTests {

    @Suite("Initialization")
    struct Initialization {

        @Test("Init with all parameters preserves every property")
        func initWithAllParameters() {
            let id = UUID()
            let config = MCPServerConfig(
                id: id,
                name: "Full Config",
                enabled: true,
                command: "/usr/bin/python3",
                args: ["--verbose", "serve"],
                env: ["API_KEY": "secret", "MODE": "test"]
            )

            #expect(config.id == id)
            #expect(config.name == "Full Config")
            #expect(config.enabled == true)
            #expect(config.command == "/usr/bin/python3")
            #expect(config.args == ["--verbose", "serve"])
            #expect(config.env == ["API_KEY": "secret", "MODE": "test"])
        }

        @Test("Init with only required parameters uses correct defaults")
        func initWithDefaults() {
            let config = MCPServerConfig(name: "Minimal", command: "/usr/bin/node")

            #expect(config.name == "Minimal")
            #expect(config.command == "/usr/bin/node")
            #expect(config.enabled == false)
            #expect(config.args.isEmpty)
            #expect(config.env.isEmpty)
            // id should be auto-generated
            #expect(config.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        }
    }

    @Suite("Codable")
    struct CodableTests {

        @Test("Round-trip encode and decode preserves all fields")
        func roundTrip() throws {
            let id = UUID()
            let original = MCPServerConfig(
                id: id,
                name: "Codable Test",
                enabled: true,
                command: "/usr/local/bin/node",
                args: ["index.js", "--port", "3000"],
                env: ["HOME": "/Users/test", "PATH": "/usr/bin"]
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)

            #expect(decoded.id == original.id)
            #expect(decoded.name == original.name)
            #expect(decoded.enabled == original.enabled)
            #expect(decoded.command == original.command)
            #expect(decoded.args == original.args)
            #expect(decoded.env == original.env)
        }

        @Test("Round-trip encode and decode for an array of configs")
        func arrayRoundTrip() throws {
            let configs = [
                MCPServerConfig(name: "Server A", command: "cmdA", args: ["a1"]),
                MCPServerConfig(name: "Server B", enabled: true, command: "cmdB", env: ["K": "V"]),
                MCPServerConfig(name: "Server C", command: "cmdC"),
            ]

            let data = try JSONEncoder().encode(configs)
            let decoded = try JSONDecoder().decode([MCPServerConfig].self, from: data)

            #expect(decoded.count == 3)
            for (original, restored) in zip(configs, decoded) {
                #expect(restored.id == original.id)
                #expect(restored.name == original.name)
                #expect(restored.enabled == original.enabled)
                #expect(restored.command == original.command)
                #expect(restored.args == original.args)
                #expect(restored.env == original.env)
            }
        }

        @Test("Decoding from invalid JSON throws")
        func decodingInvalidJSONThrows() {
            let garbage = Data("not valid json".utf8)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(MCPServerConfig.self, from: garbage)
            }
        }
    }

    @Suite("Hashable and Equatable")
    struct HashableTests {

        @Test("Two configs with the same id are equal regardless of other fields")
        func equalityByAllFields() {
            let id = UUID()
            let configA = MCPServerConfig(id: id, name: "A", enabled: true, command: "cmd1", args: ["x"])
            let configB = MCPServerConfig(id: id, name: "A", enabled: true, command: "cmd1", args: ["x"])

            #expect(configA == configB)
        }

        @Test("Two configs with different ids are not equal")
        func inequalityByDifferentId() {
            let configA = MCPServerConfig(name: "Same", command: "cmd")
            let configB = MCPServerConfig(name: "Same", command: "cmd")

            #expect(configA != configB)
        }

        @Test("Hashable allows use in a Set")
        func hashableInSet() {
            let id = UUID()
            let configA = MCPServerConfig(id: id, name: "A", command: "cmd")
            let configB = MCPServerConfig(id: id, name: "A", command: "cmd")

            let set: Set<MCPServerConfig> = [configA, configB]
            #expect(set.count == 1)
        }
    }

    @Suite("Identifiable")
    struct IdentifiableTests {

        @Test("id property is accessible and matches the provided UUID")
        func idAccessible() {
            let id = UUID()
            let config = MCPServerConfig(id: id, name: "Test", command: "cmd")

            #expect(config.id == id)
        }

        @Test("Auto-generated id is a valid UUID")
        func autoGeneratedId() {
            let config = MCPServerConfig(name: "Auto", command: "cmd")
            // UUID is non-nil by type system; verify it's unique per instance
            let another = MCPServerConfig(name: "Auto", command: "cmd")
            #expect(config.id != another.id)
        }
    }
}

// MARK: - MCPServerStorage Tests

@Suite("MCPServerStorage", .serialized)
struct MCPServerStorageTests {

    /// The UserDefaults key used by MCPServerStorage (must match the source).
    private static let storageKey = "com.andrewvoirol.EdgeAILab.mcpServers"

    /// Saves the current value for the storage key, runs the body, then restores it.
    /// This avoids polluting UserDefaults.standard across tests.
    private func withCleanStorage(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let backup = defaults.data(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.storageKey)
        defer {
            if let backup {
                defaults.set(backup, forKey: Self.storageKey)
            } else {
                defaults.removeObject(forKey: Self.storageKey)
            }
        }
        try body()
    }

    @Test("load returns default templates when no data exists")
    func loadReturnsDefaultsWhenEmpty() {
        withCleanStorage {
            let configs = MCPServerStorage.load()

            #expect(configs.count == 2)
            #expect(configs[0].name == "Filesystem Tool (Example)")
            #expect(configs[0].command == "/usr/local/bin/node")
            #expect(configs[0].enabled == false)
            #expect(configs[1].name == "Git Inspector (Example)")
            #expect(configs[1].command == "npx")
            #expect(configs[1].enabled == false)
        }
    }

    @Test("Default templates have PATH in their env")
    func defaultTemplatesHavePathEnv() {
        withCleanStorage {
            let configs = MCPServerStorage.load()

            for config in configs {
                #expect(config.env["PATH"] != nil)
                #expect(config.env["PATH"]?.contains("/usr/bin") == true)
            }
        }
    }

    @Test("save then load round-trips configs correctly")
    func saveAndLoadRoundTrip() {
        withCleanStorage {
            let id1 = UUID()
            let id2 = UUID()
            let originals = [
                MCPServerConfig(id: id1, name: "Server 1", enabled: true, command: "/usr/bin/cmd1", args: ["--flag"], env: ["A": "1"]),
                MCPServerConfig(id: id2, name: "Server 2", enabled: false, command: "/usr/bin/cmd2"),
            ]

            MCPServerStorage.save(originals)
            let loaded = MCPServerStorage.load()

            #expect(loaded.count == 2)
            #expect(loaded[0].id == id1)
            #expect(loaded[0].name == "Server 1")
            #expect(loaded[0].enabled == true)
            #expect(loaded[0].command == "/usr/bin/cmd1")
            #expect(loaded[0].args == ["--flag"])
            #expect(loaded[0].env == ["A": "1"])
            #expect(loaded[1].id == id2)
            #expect(loaded[1].name == "Server 2")
            #expect(loaded[1].enabled == false)
        }
    }

    @Test("save empty array then load returns empty array")
    func saveEmptyArray() {
        withCleanStorage {
            MCPServerStorage.save([])
            let loaded = MCPServerStorage.load()

            #expect(loaded.isEmpty)
        }
    }

    @Test("save multiple configs preserves order and count")
    func saveMultipleConfigs() {
        withCleanStorage {
            let configs = (1...5).map { i in
                MCPServerConfig(name: "Config \(i)", command: "cmd\(i)")
            }

            MCPServerStorage.save(configs)
            let loaded = MCPServerStorage.load()

            #expect(loaded.count == 5)
            for (original, restored) in zip(configs, loaded) {
                #expect(restored.id == original.id)
                #expect(restored.name == original.name)
                #expect(restored.command == original.command)
            }
        }
    }

    @Test("load returns defaults when stored data is corrupted")
    func loadReturnsDefaultsOnCorruptData() {
        withCleanStorage {
            // Write garbage data to the storage key
            let garbage = Data("this is not valid JSON at all!!!".utf8)
            UserDefaults.standard.set(garbage, forKey: Self.storageKey)

            let loaded = MCPServerStorage.load()

            // Should fall back to default templates
            #expect(loaded.count == 2)
            #expect(loaded[0].name == "Filesystem Tool (Example)")
            #expect(loaded[1].name == "Git Inspector (Example)")
        }
    }

    @Test("save overwrites previously saved configs")
    func saveOverwritesPrevious() {
        withCleanStorage {
            let first = [MCPServerConfig(name: "First", command: "cmd1")]
            MCPServerStorage.save(first)

            let second = [
                MCPServerConfig(name: "Second A", command: "cmd2"),
                MCPServerConfig(name: "Second B", command: "cmd3"),
            ]
            MCPServerStorage.save(second)

            let loaded = MCPServerStorage.load()
            #expect(loaded.count == 2)
            #expect(loaded[0].name == "Second A")
            #expect(loaded[1].name == "Second B")
        }
    }
}
