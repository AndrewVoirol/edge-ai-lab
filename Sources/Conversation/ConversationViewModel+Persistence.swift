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

// MARK: - ConversationViewModel + Persistence

/// Conversation lifecycle: save, load, fork, delete, rename, and bulk operations.
extension ConversationViewModel {

    // MARK: - Conversation Management

    /// Start a new conversation — saves current, clears chat history, resets engine.
    func newConversation() async {
        Self.logger.info("🔄 New conversation requested")

        // Auto-save the current conversation before clearing
        if !isViewingArchivedConversation && !conversation.isEmpty {
            saveCurrentConversation()
        }

        conversation.clear()
        currentThinkingText = ""
        isThinking = false
        toolCallEvents = []
        performanceMetrics = nil
        activeConversationId = nil
        isViewingArchivedConversation = false

        // Reset the engine conversation (preserves model weights, clears context window)
        if engine.isLoaded {
            do {
                try await engine.resetConversation()
            } catch {
                statusMessage = "Failed to reset conversation: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Conversation Persistence

    /// Save the current conversation to the store.
    func saveCurrentConversation() {
        guard !conversation.isEmpty else { return }

        let config = ExperimentConfig.capture(
            profile: activeCapabilityProfile,
            modelURL: activeModelURL,
            backendResult: backendResult,
            topK: topK,
            topP: topP,
            temperature: temperature,
            seed: seed,
            systemMessage: systemMessage,
            flags: runtimeFlags
        )
        let summary = ExperimentSummary.compute(from: conversation.messages)
        let now = Date()

        let id = activeConversationId ?? UUID()
        let title: String
        if let existingEntry = conversationStore.indexEntries.first(where: { $0.id == id }) {
            title = existingEntry.title
        } else {
            title = SavedConversation.generateTitle(config: config, messages: conversation.messages)
        }

        let saved = SavedConversation(
            id: id,
            title: title,
            config: config,
            messages: conversation.messages,
            summary: summary,
            createdAt: conversationStore.indexEntries.first(where: { $0.id == id })?.createdAt ?? now,
            lastModifiedAt: now,
            forkedFrom: nil
        )

        do {
            try conversationStore.save(saved)
            activeConversationId = id
            Self.logger.info("💾 Auto-saved conversation: \(title, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to auto-save: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Save the current conversation with an explicit ID.
    ///
    /// Used by `generateText()` to auto-save with the conversation ID that was
    /// captured at the *start* of generation, avoiding the race condition where
    /// the user switches conversations mid-stream and `activeConversationId` changes.
    func saveConversationWithId(_ id: UUID) {
        guard !conversation.isEmpty else { return }

        let config = ExperimentConfig.capture(
            profile: activeCapabilityProfile,
            modelURL: activeModelURL,
            backendResult: backendResult,
            topK: topK,
            topP: topP,
            temperature: temperature,
            seed: seed,
            systemMessage: systemMessage,
            flags: runtimeFlags
        )
        let summary = ExperimentSummary.compute(from: conversation.messages)
        let now = Date()

        let title: String
        if let existingEntry = conversationStore.indexEntries.first(where: { $0.id == id }) {
            title = existingEntry.title
        } else {
            title = SavedConversation.generateTitle(config: config, messages: conversation.messages)
        }

        let saved = SavedConversation(
            id: id,
            title: title,
            config: config,
            messages: conversation.messages,
            summary: summary,
            createdAt: conversationStore.indexEntries.first(where: { $0.id == id })?.createdAt ?? now,
            lastModifiedAt: now,
            forkedFrom: nil
        )

        do {
            try conversationStore.save(saved)
            activeConversationId = id
            Self.logger.info("💾 Auto-saved conversation: \(title, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to auto-save: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load a saved conversation for viewing (read-only archive mode).
    func loadConversation(id: UUID) {
        do {
            let saved = try conversationStore.load(id: id)
            conversation = ConversationState()
            for message in saved.messages {
                conversation.append(message)
            }
            activeConversationId = saved.id
            isViewingArchivedConversation = true
            currentThinkingText = ""
            isThinking = false
            toolCallEvents = []
            performanceMetrics = nil
            Self.logger.info("📂 Loaded archived conversation: \(saved.title, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to load conversation: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Failed to load conversation: \(error.localizedDescription)"
        }
    }

    /// Fork a saved conversation — creates a new editable experiment with copied data.
    func forkConversation(id: UUID) {
        do {
            let original = try conversationStore.load(id: id)
            let newId = UUID()

            // Copy messages into current conversation state
            conversation = ConversationState()
            for message in original.messages {
                conversation.append(message)
            }

            // Create the forked conversation with a new ID
            let forked = SavedConversation(
                id: newId,
                title: "Fork of \(original.title)",
                config: original.config,
                messages: original.messages,
                summary: original.summary,
                createdAt: Date(),
                lastModifiedAt: Date(),
                forkedFrom: original.id
            )

            try conversationStore.save(forked)
            activeConversationId = newId
            isViewingArchivedConversation = false
            Self.logger.info("🔀 Forked conversation: \(original.title, privacy: .public) → \(forked.title, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to fork conversation: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Failed to fork conversation: \(error.localizedDescription)"
        }
    }

    /// Delete a saved conversation.
    func deleteConversation(id: UUID) {
        do {
            try conversationStore.delete(id: id)
            if activeConversationId == id {
                activeConversationId = nil
                if isViewingArchivedConversation {
                    conversation.clear()
                    isViewingArchivedConversation = false
                }
            }
            Self.logger.info("🗑️ Deleted conversation: \(id)")
        } catch {
            Self.logger.error("❌ Failed to delete conversation: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rename a saved conversation.
    func renameConversation(id: UUID, newTitle: String) {
        do {
            try conversationStore.rename(id: id, newTitle: newTitle)
            Self.logger.info("✏️ Renamed conversation: \(newTitle, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to rename conversation: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete all saved conversations.
    func deleteAllConversations() {
        // Clear active conversation state if it will be deleted
        clearActiveConversationIfNeeded()
        do {
            let count = try conversationStore.deleteAll()
            Self.logger.info("🗑️ Deleted all \(count) conversations")
        } catch {
            Self.logger.error("❌ Failed to delete all conversations: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete multiple conversations by their IDs.
    func deleteSelectedConversations(ids: Set<UUID>) {
        if let activeId = activeConversationId, ids.contains(activeId) {
            clearActiveConversationIfNeeded()
        }
        do {
            let count = try conversationStore.deleteMultiple(ids: ids)
            Self.logger.info("🗑️ Deleted \(count) selected conversations")
        } catch {
            Self.logger.error("❌ Failed to delete selected conversations: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete conversations older than a given number of days.
    func deleteConversationsOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        // Check if active conversation is in the deletion set
        if let activeId = activeConversationId,
           let activeEntry = conversationStore.indexEntries.first(where: { $0.id == activeId }),
           activeEntry.lastModifiedAt < cutoff {
            clearActiveConversationIfNeeded()
        }
        do {
            let count = try conversationStore.deleteOlderThan(cutoff)
            Self.logger.info("🗑️ Deleted \(count) conversations older than \(days) days")
        } catch {
            Self.logger.error("❌ Failed to delete old conversations: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Helper: Clears the active conversation state when the active conversation is being deleted.
    private func clearActiveConversationIfNeeded() {
        activeConversationId = nil
        if isViewingArchivedConversation {
            conversation.clear()
            isViewingArchivedConversation = false
        }
    }
}
