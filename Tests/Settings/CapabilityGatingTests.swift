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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Vision Gating

@Suite("CapabilityGating — Vision")
struct VisionGatingTests {

    @Test("nil profile returns .unknown")
    func nilProfile() {
        let status = CapabilityGating.vision(profile: nil)
        if case .unknown = status { /* pass */ } else {
            Issue.record("Expected .unknown, got \(status)")
        }
    }

    @Test("Vision supported from config.json")
    func visionSupported() {
        let profile = makeProfile(supportsVision: SourcedValue(true, source: .configJSON))
        let status = CapabilityGating.vision(profile: profile)
        #expect(status.isEnabled == true)
        #expect(status.isVisible == true)
        #expect(status.sourceLabel == "from config.json")
    }

    @Test("Vision unsupported from config.json")
    func visionUnsupported() {
        let profile = makeProfile(supportsVision: SourcedValue(false, source: .configJSON))
        let status = CapabilityGating.vision(profile: profile)
        #expect(status.isEnabled == false)
        #expect(status.isVisible == true)
        #expect(status.disabledReason != nil)
    }

    @Test("Vision nil in profile returns .unknown")
    func visionNilInProfile() {
        let profile = makeProfile(supportsVision: nil)
        let status = CapabilityGating.vision(profile: profile)
        if case .unknown = status { /* pass */ } else {
            Issue.record("Expected .unknown, got \(status)")
        }
    }
}

// MARK: - Audio Gating

@Suite("CapabilityGating — Audio")
struct AudioGatingTests {

    @Test("Audio supported")
    func audioSupported() {
        let profile = makeProfile(supportsAudio: SourcedValue(true, source: .configJSON))
        let status = CapabilityGating.audio(profile: profile)
        #expect(status.isEnabled == true)
    }

    @Test("Audio unsupported")
    func audioUnsupported() {
        let profile = makeProfile(supportsAudio: SourcedValue(false, source: .heuristic))
        let status = CapabilityGating.audio(profile: profile)
        #expect(status.isEnabled == false)
        #expect(status.sourceLabel == "estimated")
    }
}

// MARK: - Thinking Gating

@Suite("CapabilityGating — Thinking")
struct ThinkingGatingTests {

    @Test("Thinking supported for Gemma model")
    func thinkingSupported() {
        let profile = makeProfile(supportsThinking: SourcedValue(true, source: .apiMetadata))
        let status = CapabilityGating.thinking(profile: profile)
        #expect(status.isEnabled == true)
        #expect(status.sourceLabel == "from API")
    }

    @Test("Thinking unknown when nil")
    func thinkingUnknown() {
        let profile = makeProfile(supportsThinking: nil)
        let status = CapabilityGating.thinking(profile: profile)
        if case .unknown = status { /* pass */ } else {
            Issue.record("Expected .unknown")
        }
    }
}

// MARK: - Tool Calling Gating

@Suite("CapabilityGating — Tool Calling")
struct ToolCallingGatingTests {

    @Test("Tool calling enabled for instruction-tuned model")
    func toolCallingEnabled() {
        let profile = makeProfile(supportsToolCalling: SourcedValue(true, source: .heuristic))
        let status = CapabilityGating.toolCalling(profile: profile)
        #expect(status.isEnabled == true)
        #expect(status.sourceLabel == "estimated")
    }

    @Test("Tool calling disabled for base model")
    func toolCallingDisabled() {
        let profile = makeProfile(supportsToolCalling: SourcedValue(false, source: .heuristic))
        let status = CapabilityGating.toolCalling(profile: profile)
        #expect(status.isEnabled == false)
    }
}

// MARK: - MTP Gating

@Suite("CapabilityGating — MTP")
struct MTPGatingTests {

    @Test("MTP not applicable on MLX")
    func mtpNotApplicableOnMLX() {
        let profile = makeProfile(
            runtimeType: .mlx,
            supportsMTP: SourcedValue(true, source: .apiMetadata)
        )
        let status = CapabilityGating.mtp(profile: profile, runtimeType: .mlx)
        if case .notApplicable = status { /* pass */ } else {
            Issue.record("Expected .notApplicable, got \(status)")
        }
        #expect(status.isVisible == false)
    }

    @Test("MTP supported on LiteRT-LM")
    func mtpSupportedOnLiteRT() {
        let profile = makeProfile(
            runtimeType: .litertlm,
            supportsMTP: SourcedValue(true, source: .apiMetadata)
        )
        let status = CapabilityGating.mtp(profile: profile, runtimeType: .litertlm)
        #expect(status.isEnabled == true)
    }

    @Test("MTP unsupported on LiteRT-LM")
    func mtpUnsupportedOnLiteRT() {
        let profile = makeProfile(
            runtimeType: .litertlm,
            supportsMTP: SourcedValue(false, source: .heuristic)
        )
        let status = CapabilityGating.mtp(profile: profile, runtimeType: .litertlm)
        #expect(status.isEnabled == false)
        #expect(status.isVisible == true)
    }
}

// MARK: - Constrained Decoding Gating

@Suite("CapabilityGating — Constrained Decoding")
struct ConstrainedDecodingGatingTests {

    @Test("CD not applicable on GGUF")
    func cdNotApplicableOnGGUF() {
        let profile = makeProfile(runtimeType: .gguf)
        let status = CapabilityGating.constrainedDecoding(profile: profile, runtimeType: .gguf)
        if case .notApplicable = status { /* pass */ } else {
            Issue.record("Expected .notApplicable")
        }
    }

    @Test("CD supported on LiteRT-LM")
    func cdSupportedOnLiteRT() {
        let profile = makeProfile(
            runtimeType: .litertlm,
            supportsConstrainedDecoding: SourcedValue(true, source: .apiMetadata)
        )
        let status = CapabilityGating.constrainedDecoding(profile: profile, runtimeType: .litertlm)
        #expect(status.isEnabled == true)
    }
}

// MARK: - CapabilityGateStatus Properties

@Suite("CapabilityGateStatus")
struct GateStatusPropertyTests {

    @Test("supported is enabled and visible")
    func supportedProperties() {
        let status = CapabilityGateStatus.supported(source: .configJSON)
        #expect(status.isEnabled == true)
        #expect(status.isVisible == true)
        #expect(status.sourceLabel == "from config.json")
        #expect(status.disabledReason == nil)
    }

    @Test("unsupported is disabled and visible")
    func unsupportedProperties() {
        let status = CapabilityGateStatus.unsupported(source: .heuristic, reason: "Test reason")
        #expect(status.isEnabled == false)
        #expect(status.isVisible == true)
        #expect(status.sourceLabel == "estimated")
        #expect(status.disabledReason == "Test reason")
    }

    @Test("unknown is disabled and visible")
    func unknownProperties() {
        let status = CapabilityGateStatus.unknown
        #expect(status.isEnabled == false)
        #expect(status.isVisible == true)
        #expect(status.sourceLabel == nil)
    }

    @Test("notApplicable is not visible")
    func notApplicableProperties() {
        let status = CapabilityGateStatus.notApplicable(reason: "Wrong backend")
        #expect(status.isEnabled == false)
        #expect(status.isVisible == false)
        #expect(status.disabledReason == "Wrong backend")
    }
}

// MARK: - Test Helpers

/// Creates a minimal ModelCapabilityProfile for testing.
private func makeProfile(
    id: String = "test/model",
    runtimeType: RuntimeType = .litertlm,
    supportsVision: SourcedValue<Bool>? = nil,
    supportsAudio: SourcedValue<Bool>? = nil,
    supportsThinking: SourcedValue<Bool>? = nil,
    supportsToolCalling: SourcedValue<Bool>? = nil,
    supportsMTP: SourcedValue<Bool>? = nil,
    supportsConstrainedDecoding: SourcedValue<Bool>? = nil
) -> ModelCapabilityProfile {
    ModelCapabilityProfile(
        id: id,
        displayName: "Test Model",
        repoId: nil,
        runtimeType: runtimeType,
        supportsVision: supportsVision,
        supportsAudio: supportsAudio,
        supportsThinking: supportsThinking,
        supportsToolCalling: supportsToolCalling,
        supportsMTP: supportsMTP,
        supportsConstrainedDecoding: supportsConstrainedDecoding,
        architecture: nil,
        contextWindow: nil,
        fileSizeBytes: nil,
        estimatedMemoryGB: nil,
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .medium,
        source: .huggingFaceInferred,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil,
        licenseLink: nil,
        baseModelId: nil,
        downloads: nil,
        likes: nil,
        downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: nil,
        platformSupport: nil,
        modelDescription: nil,
        recommendedFor: nil,
        modelFile: nil,
        modelId: nil
    )
}
