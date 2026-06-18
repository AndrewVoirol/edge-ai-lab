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

#if os(iOS)
import SwiftUI

// MARK: - App Share Sheet

/// A unified `UIActivityViewController` wrapper for iOS share sheets.
///
/// This replaces the duplicate implementations that were previously defined
/// as private structs in multiple files:
/// - `ShareSheet` in `iOSConversationPickerSheet.swift`
/// - `ActivityViewController` in `iOSEvalTabView.swift`
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showShareSheet) {
///     AppShareSheet(activityItems: [myData])
/// }
/// ```
struct AppShareSheet: UIViewControllerRepresentable {
    /// The items to share (Data, URL, String, UIImage, etc.).
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#endif
