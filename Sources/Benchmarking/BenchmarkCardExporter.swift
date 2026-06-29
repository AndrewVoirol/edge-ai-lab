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

// MARK: - Benchmark Card Exporter

/// Renders a BenchmarkCardView to platform-native images at various export sizes.
/// Supports multiple card sizes for different social media platforms.
enum BenchmarkCardExporter {

    /// Render the benchmark card at a specific size.
    @MainActor
    static func renderImage(
        data: BenchmarkCardData,
        size: CardSize
    ) -> PlatformImage? {
        let view = BenchmarkCardView(data: data, cardSize: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0  // Retina

        #if os(macOS)
        return renderer.nsImage
        #else
        return renderer.uiImage
        #endif
    }

    /// Render the benchmark card to PNG data at a specific size.
    @MainActor
    static func renderPNG(
        data: BenchmarkCardData,
        size: CardSize
    ) -> Data? {
        #if os(macOS)
        guard let image = renderImage(data: data, size: size),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        guard let image = renderImage(data: data, size: size) else { return nil }
        return image.pngData()
        #endif
    }

    /// Render all card sizes and return as a dictionary.
    @MainActor
    static func renderAllSizes(data: BenchmarkCardData) -> [CardSize: PlatformImage] {
        var results: [CardSize: PlatformImage] = [:]
        for size in CardSize.allCases {
            if let image = renderImage(data: data, size: size) {
                results[size] = image
            }
        }
        return results
    }
}
