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
import os

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Accessibility Tree Inspector

/// In-process accessibility tree inspector for automation flow step assertions.
///
/// This utility queries the live view hierarchy to verify that UI elements
/// with specific accessibility identifiers or labels exist. It enables the
/// `AutomationFlowRunner` to perform real UI verification without requiring
/// an external XCUITest process.
///
/// ## Platform Support
/// - **macOS**: Walks `NSApplication.shared.windows` → `contentView` subview tree
/// - **iOS**: Walks `UIApplication.shared.connectedScenes` → `UIWindowScene` → window subview tree
///
/// ## Usage
/// ```swift
/// // Check if an element exists
/// let exists = AccessibilityTreeInspector.elementExists("button_send")
///
/// // Get a snapshot for debugging
/// let snapshot = AccessibilityTreeInspector.debugSnapshot()
/// ```
///
/// ## Limitations
/// - Only inspects accessibility identifiers and labels set via SwiftUI modifiers
///   (`.accessibilityIdentifier()`, `.accessibilityLabel()`)
/// - Cannot inspect elements hidden from accessibility (`.accessibilityHidden(true)`)
/// - Tab bar items in SwiftUI use the view's `tabItem` label as the accessibility label,
///   not `.accessibilityIdentifier()`, so we check both identifier and label
@MainActor
struct AccessibilityTreeInspector {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "a11yInspector"
    )

    // MARK: - Public API

    /// Check if an element with the given identifier or label exists in the current view hierarchy.
    ///
    /// Searches both `accessibilityIdentifier` and `accessibilityLabel` properties,
    /// since SwiftUI tab items and navigation titles typically use labels rather than identifiers.
    ///
    /// - Parameter identifier: The accessibility identifier or label to search for.
    /// - Returns: `true` if a matching element is found.
    static func elementExists(_ identifier: String) -> Bool {
        let elements = collectAllElements()
        return elements.contains { element in
            element.identifier == identifier ||
            element.label == identifier ||
            element.label.localizedCaseInsensitiveContains(identifier)
        }
    }

    /// Get the value of an element with the given identifier.
    ///
    /// - Parameter identifier: The accessibility identifier or label to search for.
    /// - Returns: The element's accessibility value, or `nil` if not found.
    static func elementValue(_ identifier: String) -> String? {
        let elements = collectAllElements()
        return elements.first { element in
            element.identifier == identifier ||
            element.label == identifier
        }?.value
    }

    /// Get all unique accessibility identifiers currently in the view hierarchy.
    ///
    /// - Returns: Sorted array of non-empty accessibility identifiers.
    static func allIdentifiers() -> [String] {
        let elements = collectAllElements()
        let identifiers = Set(elements.compactMap { $0.identifier.isEmpty ? nil : $0.identifier })
        return identifiers.sorted()
    }

    /// Get all unique accessibility labels currently in the view hierarchy.
    ///
    /// - Returns: Sorted array of non-empty accessibility labels.
    static func allLabels() -> [String] {
        let elements = collectAllElements()
        let labels = Set(elements.compactMap { $0.label.isEmpty ? nil : $0.label })
        return labels.sorted()
    }

    /// Generate a debug snapshot of the current accessibility tree.
    ///
    /// Useful for diagnosing why a `verify_ui` step fails — the snapshot shows
    /// all accessible elements and their properties.
    ///
    /// - Returns: A multi-line string describing the accessibility tree.
    static func debugSnapshot() -> String {
        let elements = collectAllElements()
        guard !elements.isEmpty else {
            return "[AccessibilityTreeInspector] No elements found in view hierarchy."
        }

        var lines: [String] = [
            "[AccessibilityTreeInspector] Snapshot (\(elements.count) elements):",
            "─────────────────────────────────────────────"
        ]

        for element in elements {
            var parts: [String] = []
            if !element.identifier.isEmpty {
                parts.append("id=\"\(element.identifier)\"")
            }
            if !element.label.isEmpty {
                parts.append("label=\"\(element.label)\"")
            }
            if let value = element.value, !value.isEmpty {
                parts.append("value=\"\(value)\"")
            }
            parts.append("type=\(element.elementType)")

            let indent = String(repeating: "  ", count: element.depth)
            lines.append("\(indent)├─ \(parts.joined(separator: " | "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Internal Model

    /// Lightweight representation of an accessible element in the view hierarchy.
    struct AccessibleElement {
        let identifier: String
        let label: String
        let value: String?
        let elementType: String
        let depth: Int
    }

    // MARK: - Platform-Specific Collection

    /// Collect all accessible elements from the current view hierarchy.
    private static func collectAllElements() -> [AccessibleElement] {
        var elements: [AccessibleElement] = []

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        // macOS: Walk NSApplication windows
        for window in NSApplication.shared.windows {
            guard let contentView = window.contentView else { continue }
            collectFromNSView(contentView, depth: 0, into: &elements)
        }
        #elseif canImport(UIKit)
        // iOS: Walk UIWindowScene windows
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                collectFromUIView(window, depth: 0, into: &elements)
            }
        }
        #endif

        return elements
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    // MARK: - macOS Collection

    /// Recursively collect accessible elements from an NSView hierarchy.
    private static func collectFromNSView(_ view: NSView, depth: Int, into elements: inout [AccessibleElement]) {
        let identifier = view.accessibilityIdentifier()
        let label = view.accessibilityLabel() ?? ""
        let value = view.accessibilityValue() as? String

        // Only include elements that have meaningful accessibility info
        if !identifier.isEmpty || !label.isEmpty {
            let element = AccessibleElement(
                identifier: identifier,
                label: label,
                value: value,
                elementType: String(describing: type(of: view)),
                depth: depth
            )
            elements.append(element)
        }

        // Recurse into subviews
        for subview in view.subviews {
            collectFromNSView(subview, depth: depth + 1, into: &elements)
        }
    }
    #endif

    #if canImport(UIKit)
    // MARK: - iOS Collection

    /// Recursively collect accessible elements from a UIView hierarchy.
    private static func collectFromUIView(_ view: UIView, depth: Int, into elements: inout [AccessibleElement]) {
        let identifier = view.accessibilityIdentifier ?? ""
        let label = view.accessibilityLabel ?? ""
        let value = view.accessibilityValue

        // Only include elements that have meaningful accessibility info
        if !identifier.isEmpty || !label.isEmpty {
            let element = AccessibleElement(
                identifier: identifier,
                label: label,
                value: value,
                elementType: String(describing: type(of: view)),
                depth: depth
            )
            elements.append(element)
        }

        // Recurse into subviews
        for subview in view.subviews {
            collectFromUIView(subview, depth: depth + 1, into: &elements)
        }
    }
    #endif
}
