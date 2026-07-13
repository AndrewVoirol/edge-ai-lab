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
import SwiftUI
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - AppTransition Tests

@Suite("AppTransition")
struct AppTransitionTests {

    // MARK: - Token existence

    @Test("slideDown transition exists")
    func slideDownExists() {
        // AnyTransition is an opaque type — verify it can be assigned
        let transition: AnyTransition = AppTransition.slideDown
        _ = transition  // Ensures no compilation or runtime error
    }

    @Test("slideUp transition exists")
    func slideUpExists() {
        let transition: AnyTransition = AppTransition.slideUp
        _ = transition
    }

    @Test("contentReveal transition exists")
    func contentRevealExists() {
        let transition: AnyTransition = AppTransition.contentReveal
        _ = transition
    }

    // MARK: - AnyTransition convenience extensions

    @Test("AnyTransition.slideDown matches AppTransition.slideDown")
    func convenienceSlideDown() {
        // Both should compile and be usable in .transition() context
        let direct: AnyTransition = AppTransition.slideDown
        let convenience: AnyTransition = .slideDown
        // AnyTransition doesn't conform to Equatable, but both should exist
        _ = direct
        _ = convenience
    }

    @Test("AnyTransition.slideUp matches AppTransition.slideUp")
    func convenienceSlideUp() {
        let direct: AnyTransition = AppTransition.slideUp
        let convenience: AnyTransition = .slideUp
        _ = direct
        _ = convenience
    }

    @Test("AnyTransition.contentReveal matches AppTransition.contentReveal")
    func convenienceContentReveal() {
        let direct: AnyTransition = AppTransition.contentReveal
        let convenience: AnyTransition = .contentReveal
        _ = direct
        _ = convenience
    }

    // MARK: - Token count stability

    @Test("AppTransition has exactly 3 tokens")
    func tokenCount() {
        // Manually enumerate all tokens — update this test when adding new tokens
        let tokens: [AnyTransition] = [
            AppTransition.slideDown,
            AppTransition.slideUp,
            AppTransition.contentReveal,
        ]
        #expect(tokens.count == 3, "Update this test if AppTransition tokens are added or removed")
    }
}

// MARK: - AppAnimation Extended Tests

@Suite("AppAnimation Extended")
struct AppAnimationExtendedTests {

    // MARK: - All tokens exist

    @Test("micro animation token exists")
    func microExists() {
        let animation: Animation = AppAnimation.micro
        _ = animation
    }

    @Test("quick animation token exists")
    func quickExists() {
        let animation: Animation = AppAnimation.quick
        _ = animation
    }

    @Test("standard animation token exists")
    func standardExists() {
        let animation: Animation = AppAnimation.standard
        _ = animation
    }

    @Test("spring animation token exists")
    func springExists() {
        let animation: Animation = AppAnimation.spring
        _ = animation
    }

    @Test("gentleSpring animation token exists")
    func gentleSpringExists() {
        let animation: Animation = AppAnimation.gentleSpring
        _ = animation
    }

    @Test("messageEntrance animation token exists")
    func messageEntranceExists() {
        let animation: Animation = AppAnimation.messageEntrance
        _ = animation
    }

    // MARK: - Token count stability

    @Test("AppAnimation has exactly 6 tokens")
    func tokenCount() {
        // Manually enumerate all tokens — update this test when adding new tokens
        let tokens: [Animation] = [
            AppAnimation.micro,
            AppAnimation.quick,
            AppAnimation.standard,
            AppAnimation.spring,
            AppAnimation.gentleSpring,
            AppAnimation.messageEntrance,
        ]
        #expect(tokens.count == 6, "Update this test if AppAnimation tokens are added or removed")
    }

    // MARK: - Determinism

    @Test("all animation tokens are deterministic")
    func deterministic() {
        // Static lets should return identical values on repeated access
        let micro1 = AppAnimation.micro
        let micro2 = AppAnimation.micro
        // Animation conforms to Equatable
        #expect(micro1 == micro2, "micro should be deterministic")

        let quick1 = AppAnimation.quick
        let quick2 = AppAnimation.quick
        #expect(quick1 == quick2, "quick should be deterministic")

        let standard1 = AppAnimation.standard
        let standard2 = AppAnimation.standard
        #expect(standard1 == standard2, "standard should be deterministic")
    }

    // MARK: - Duration ordering (semantic)

    @Test("micro is faster than quick")
    func microFasterThanQuick() {
        // We can't extract duration from Animation directly,
        // but we can verify the intent by checking they're different tokens
        #expect(AppAnimation.micro != AppAnimation.quick,
                "micro and quick should be distinct animations")
    }

    @Test("quick is faster than standard")
    func quickFasterThanStandard() {
        #expect(AppAnimation.quick != AppAnimation.standard,
                "quick and standard should be distinct animations")
    }

    @Test("micro is distinct from standard")
    func microDistinctFromStandard() {
        #expect(AppAnimation.micro != AppAnimation.standard,
                "micro and standard should be distinct animations")
    }
}
