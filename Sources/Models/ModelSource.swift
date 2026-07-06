// ModelSource.swift — Unified model identity type for navigation
//
// Eliminates the need for separate detail views for on-device vs community models.
// Used as a NavigationLink(value:) type so both model sources can be navigated
// through a single `.navigationDestination(for:)`.

import Foundation

/// A model that can be displayed in a detail view, regardless of origin.
///
/// On iOS, this enables a single `navigationDestination(for: ModelSource.self)` handler
/// to route both on-device (known registry) models and HuggingFace community models.
/// On macOS, it unifies the sidebar selection type for the detail column.
enum ModelSource: Hashable {

    /// A model with known metadata from the local registry or dynamic catalog.
    case onDevice(ModelMetadata)

    /// A community model discovered via HuggingFace API.
    case huggingFace(HFModelInfo)

    /// The display name for this model source.
    var displayName: String {
        switch self {
        case .onDevice(let metadata):
            return metadata.name
        case .huggingFace(let model):
            return model.id.components(separatedBy: "/").last ?? model.id
        }
    }

    /// The organization or publisher name.
    var organizationName: String {
        switch self {
        case .onDevice:
            return "On Device"
        case .huggingFace(let model):
            return model.orgName
        }
    }

    /// The unique model identifier (filename for on-device, repo ID for HuggingFace).
    var modelId: String {
        switch self {
        case .onDevice(let metadata):
            return metadata.modelFile
        case .huggingFace(let model):
            return model.id
        }
    }

    /// Whether this model is on-device (downloaded/discovered).
    var isOnDevice: Bool {
        if case .onDevice = self { return true }
        return false
    }

    /// Whether this model is from the HuggingFace community.
    var isCommunity: Bool {
        if case .huggingFace = self { return true }
        return false
    }
}
