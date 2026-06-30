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

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Camera Image Picker

/// SwiftUI bridge for the iOS camera via `UIImagePickerController`.
///
/// Uses the `.camera` source type to capture photos for VLM input.
/// The captured image is compressed to JPEG (quality 0.8) before returning
/// to keep memory/transfer overhead manageable.
///
/// ## Usage
///
/// ```swift
/// @State private var showCamera = false
///
/// .fullScreenCover(isPresented: $showCamera) {
///     CameraImagePicker { data in
///         viewModel.selectedImageData = data
///     }
/// }
/// ```
struct CameraImagePicker: UIViewControllerRepresentable {
    /// Callback with the captured image data (JPEG).
    let onImageCaptured: (Data) -> Void

    /// Dismiss the picker when the user cancels or captures.
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No-op: camera configuration is static after creation.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onImageCaptured(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
