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

import SwiftUI

// MARK: - Panel Resize Handle

/// A draggable vertical divider handle for resizing adjacent panels.
///
/// Features:
/// - **Wide hit area** (8pt invisible) so users can easily grab the handle
/// - **Cursor change** on hover (resize left-right) so it's discoverable
/// - **Visual grip indicator** — subtle dots that appear on hover/drag
/// - **Thin visual line** (1pt) so it looks clean when not interacting
///
/// Usage:
/// ```swift
/// HStack(spacing: 0) {
///     LeftPanel()
///     PanelResizeHandle(
///         onDragStart: { widthAtStart = currentWidth },
///         onDragChanged: { delta in currentWidth = widthAtStart - delta },
///         onDragEnded: { }
///     )
///     RightPanel()
///         .frame(width: currentWidth)
/// }
/// ```
#if os(macOS)
struct PanelResizeHandle: View {
    /// Called once when the drag gesture begins. Use to snapshot current state.
    var onDragStart: () -> Void = {}

    /// Called with the cumulative horizontal translation from the drag start.
    /// Positive = dragging right, negative = dragging left.
    let onDragChanged: (CGFloat) -> Void

    /// Called when the drag gesture ends.
    var onDragEnded: () -> Void = {}

    /// Whether this handle is currently being dragged.
    @State private var isDragging = false

    /// Whether the mouse is hovering over the handle.
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Thin visual divider line (always visible)
            Rectangle()
                .fill(isHovering || isDragging ? AppColors.textTertiary : AppColors.border)
                .frame(width: 1)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .animation(.easeInOut(duration: 0.15), value: isDragging)

            // Grip dots — shown on hover/drag for discoverability
            if isHovering || isDragging {
                VStack(spacing: AppSpacing.xxs) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(AppColors.textTertiary.opacity(0.6))
                            .frame(width: 3, height: 3)
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        // Wide invisible hit area for easy grabbing
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onDragStart()
                    }
                    onDragChanged(value.translation.width)
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnded()
                }
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityIdentifier("panelResizeHandle")
        .accessibilityLabel("Resize panels")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
#endif
