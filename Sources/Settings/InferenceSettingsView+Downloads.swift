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

// MARK: - Downloads Section

extension InferenceSettingsView {
    /// Settings section for controlling download behavior.
    ///
    /// Controls:
    /// - Max concurrent downloads (Stepper: 1–3)
    /// - Available storage display
    /// - Notification permission request (iOS only)
    @ViewBuilder
    var downloadsSection: some View {
        Section {
            // Max concurrent downloads
            HStack {
                Label("Concurrent Downloads", systemImage: "arrow.down.circle")
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Stepper(
                    "\(viewModel.downloadManager.maxConcurrentDownloads)",
                    value: Binding(
                        get: { viewModel.downloadManager.maxConcurrentDownloads },
                        set: { viewModel.downloadManager.maxConcurrentDownloads = $0 }
                    ),
                    in: 1...3,
                    step: 1
                )
                .accessibilityIdentifier("settings_maxConcurrentDownloads")
            }

            // Available storage
            HStack {
                Label("Available Storage", systemImage: "internaldrive")
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(formattedAvailableStorage)
                    .font(AppTypography.mono)
                    .foregroundStyle(AppColors.textSecondary)
            }

            #if os(iOS)
            // Request notification permission
            Button {
                viewModel.downloadManager.requestNotificationPermission()
            } label: {
                Label("Enable Download Notifications", systemImage: "bell.badge")
            }
            .accessibilityIdentifier("settings_enableNotifications")
            #endif
        } header: {
            Label("Downloads", systemImage: "arrow.down.doc")
        } footer: {
            Text("Controls how model downloads are managed. Downloads continue in the background even when the app is suspended.")
                .font(AppTypography.listTertiary)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    /// Formatted available storage string.
    private var formattedAvailableStorage: String {
        let bytes = viewModel.downloadManager.availableStorageBytes()
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
