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

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - GalleryModelDiscovery Path Tests
//
// Verifies that getAppModelsDirectory() returns the correct project-root `models/`
// directory on DEBUG macOS, not an intermediate directory like `Sources/Models/`.
// This regression occurred when GalleryModelDiscovery.swift was moved from
// Sources/Utilities/ to Sources/Models/, adding a directory level without updating
// the deletingLastPathComponent() count.

final class GalleryModelDiscoveryPathTests: XCTestCase {

    #if DEBUG && os(macOS)
    /// The DEBUG macOS models directory must be the project root's `models/` dir,
    /// not `Sources/Models/` or any other intermediate path.
    ///
    /// When GalleryModelDiscovery.swift lives at:
    ///   <project>/Sources/Models/GalleryModelDiscovery.swift
    ///
    /// getAppModelsDirectory() must resolve to:
    ///   <project>/models
    ///
    /// NOT to:
    ///   <project>/Sources/models (which case-folds to Sources/Models/)
    func testAppModelsDirectoryPointsToProjectRootModels() throws {
        let modelsDir = GalleryModelDiscovery.getAppModelsDirectory()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelsDir.path),
            "Skipped — models/ directory not present at \(modelsDir.path)"
        )

        // The path should end with /models (the project root's models directory)
        XCTAssertEqual(
            modelsDir.lastPathComponent, "models",
            "Models directory should be named 'models'"
        )

        // The parent should NOT be "Sources" — that was the bug.
        // It should be the project root (containing Project.swift, Sources/, etc.)
        let parent = modelsDir.deletingLastPathComponent()
        XCTAssertNotEqual(
            parent.lastPathComponent, "Sources",
            "Models directory must be at project root, not inside Sources/"
        )

        // Positive check: the parent should contain Sources/ as a subdirectory
        // (this confirms we're at the project root)
        let sourcesDir = parent.appendingPathComponent("Sources")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sourcesDir.path),
            "Project root should contain a Sources/ directory. Got parent: \(parent.path)"
        )

        // Additional check: Project.swift should exist at the project root
        let projectSwift = parent.appendingPathComponent("Project.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: projectSwift.path),
            "Project root should contain Project.swift. Got parent: \(parent.path)"
        )
    }

    /// The models directory should actually exist on disk.
    func testAppModelsDirectoryExists() throws {
        let modelsDir = GalleryModelDiscovery.getAppModelsDirectory()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelsDir.path),
            "Skipped — models/ directory not present at \(modelsDir.path)"
        )
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelsDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "Models directory should exist at: \(modelsDir.path)")
        XCTAssertTrue(isDir.boolValue, "Models path should be a directory, not a file")
    }

    /// The download manager's documentsDirectory should match discovery's models directory.
    func testDownloadManagerUsesCorrectModelsDirectory() {
        let discoveryDir = GalleryModelDiscovery.getAppModelsDirectory()
        let downloadManager = ModelDownloadManager()
        XCTAssertEqual(
            downloadManager.documentsDirectory.standardizedFileURL,
            discoveryDir.standardizedFileURL,
            "Download manager and discovery must use the same models directory"
        )
    }
    #endif
}
