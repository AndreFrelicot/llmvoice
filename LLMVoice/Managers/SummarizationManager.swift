//
//  SummarizationManager.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import Foundation
import FoundationModels
import os.log

/// Manages AI-powered text summarization with multiple model options:
/// - Apple Intelligence (Foundation Models) for iPhone 15 Pro+
/// - MLX models (Gemma, Qwen, Llama) for older devices (iPhone 13+)
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class SummarizationManager {
    private let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "SummarizationManager")
    private var session: LanguageModelSession
    private let model = SystemLanguageModel.default
    private let mlxManager: MLXSummarizationManager
    private(set) var isUsingMLXFallback = false
    private(set) var selectedModel: MLXModel

    // UserDefaults key for tracking downloaded models (same as ModelDownloadManager)
    private let downloadedModelsKey = "dev.andrefrelicot.llmvoice.downloadedModels"

    init(model: MLXModel = .qwen25_05b) {
        logger.info("🤖 SummarizationManager initializing with model: \(model.displayName)")
        self.selectedModel = model
        session = LanguageModelSession()
        mlxManager = MLXSummarizationManager(model: model)
        logger.info("✅ SummarizationManager initialized")

        // Log initial model availability
        checkModelAvailability()
    }

    /// Check and log model availability status
    private func checkModelAvailability() {
        switch model.availability {
        case .available:
            logger.info("✅ AI model is available and ready")
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                logger.warning("⚠️ Apple Intelligence is not enabled")
            case .deviceNotEligible:
                logger.error("❌ Device does not support Apple Intelligence")
            case .modelNotReady:
                logger.warning("⚠️ AI model is not ready (may be downloading)")
            @unknown default:
                logger.warning("⚠️ AI model unavailable: unknown reason")
            }
        }
    }

    /// Mark a model as downloaded in persistent storage (same logic as ModelDownloadManager)
    private func setModelDownloaded(_ model: MLXModel) {
        var downloaded = Set(UserDefaults.standard.stringArray(forKey: downloadedModelsKey) ?? [])
        downloaded.insert(model.rawValue)
        UserDefaults.standard.set(Array(downloaded), forKey: downloadedModelsKey)
        logger.info("💾 Saved download flag for \(model.displayName)")
    }

    /// Generate a summary of the given transcription text
    /// Uses Apple Intelligence if selected and available, otherwise uses MLX models
    /// - Parameters:
    ///   - text: The transcription text to summarize
    ///   - progressHandler: Optional callback for model download progress (MLX fallback only)
    /// - Returns: A concise summary of the text
    func summarize(_ text: String, progressHandler: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        logger.info("🚀 summarize() called with text length: \(text.count), selected model: \(self.selectedModel.displayName)")

        guard !text.isEmpty else {
            logger.error("❌ Cannot summarize empty text")
            throw NSError(
                domain: "SummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot summarize empty text"]
            )
        }

        // If user explicitly selected Apple Intelligence, try to use it
        if selectedModel == .appleIntelligence {
            logger.info("🔍 User selected Apple Intelligence, checking availability")
            switch model.availability {
            case .available:
                logger.info("✅ Using Apple Intelligence for summarization")
                isUsingMLXFallback = false
                return try await summarizeWithAppleIntelligence(text)

            case .unavailable(let reason):
                let reasonStr: String
                switch reason {
                case .appleIntelligenceNotEnabled:
                    reasonStr = "Apple Intelligence is not enabled on this device"
                case .deviceNotEligible:
                    reasonStr = "This device does not support Apple Intelligence (requires iPhone 15 Pro or later)"
                case .modelNotReady:
                    reasonStr = "Apple Intelligence model is not ready"
                @unknown default:
                    reasonStr = "Apple Intelligence is unavailable for unknown reason"
                }
                logger.error("❌ Apple Intelligence selected but unavailable: \(reasonStr)")
                throw NSError(
                    domain: "SummarizationManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: reasonStr]
                )
            }
        } else {
            // User selected an MLX model
            logger.info("✅ Using MLX model (\(self.selectedModel.displayName)) for summarization")
            isUsingMLXFallback = true
            return try await summarizeWithMLX(text, progressHandler: progressHandler)
        }
    }

    /// Summarize using Apple Intelligence
    private func summarizeWithAppleIntelligence(_ text: String) async throws -> String {
        let prompt = """
        Please provide a concise summary of the following text in 2-3 sentences. \
        Focus on the key points and main ideas:

        \(text)
        """

        logger.info("📝 Sending prompt to Apple Intelligence")
        do {
            let response = try await session.respond(to: prompt)
            logger.info("✅ Received summary from Apple Intelligence, length: \(response.content.count)")
            return response.content
        } catch {
            logger.error("❌ Apple Intelligence failed: \(error.localizedDescription)")
            throw NSError(
                domain: "SummarizationManager",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate summary with Apple Intelligence",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
    }

    /// Summarize using MLX models
    private func summarizeWithMLX(_ text: String, progressHandler: (@Sendable (Double) -> Void)?) async throws -> String {
        logger.info("🔄 Using MLX for summarization")

        // Check if running on simulator - provide mock implementation
        #if targetEnvironment(simulator)
        logger.warning("⚠️ Running on simulator - MLX not available")
        logger.info("📝 Returning mock summary for simulator testing")

        // Get current model name for display
        let modelName = mlxManager.selectedModel.displayName

        // Return mock summary
        let mockSummary = """
        This is a mock summary generated by \(modelName) in simulator mode. \
        MLX requires a real iOS device with Metal GPU support to function. \
        To test the actual \(modelName) model (\(mlxManager.selectedModel.parameters)M params, ~\(mlxManager.selectedModel.sizeInMB)MB), \
        please deploy to a physical device.
        """

        // Simulate progress callback if provided
        if let handler = progressHandler {
            handler(1.0)
        }

        return mockSummary
        #else
        // Real device - use MLX
        do {
            // Load model with progress tracking if provided
            if let handler = progressHandler {
                try await mlxManager.loadModel(progressHandler: handler)
                // Save persistent flag after successful download
                setModelDownloaded(selectedModel)
            }

            let summary = try await mlxManager.summarize(text)
            logger.info("✅ Received summary from MLX model, length: \(summary.count)")
            return summary

        } catch {
            logger.error("❌ MLX summarization failed: \(error.localizedDescription)")
            throw NSError(
                domain: "SummarizationManager",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate summary. Please ensure you have sufficient storage (~300MB) and try again.",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        #endif
    }

    /// Get the download state of the MLX model
    func getMLXModelState() -> ModelDownloadState {
        return mlxManager.getDownloadState()
    }

    /// Check if MLX model is ready to use
    func isMLXModelReady() -> Bool {
        return mlxManager.isModelReady
    }

    /// Handle memory warning
    func handleMemoryWarning() {
        logger.warning("⚠️ Memory warning - freeing MLX memory")
        mlxManager.handleMemoryWarning()
    }

    /// Clear cached models from device (for debugging/testing)
    func clearModelCache() throws {
        logger.warning("🗑️ Clearing MLX model cache")
        try mlxManager.clearModelCache()
    }

    /// Get the model cache directory path
    func getModelCacheDirectory() -> URL? {
        return mlxManager.getModelCacheDirectory()
    }

    /// Switch to a different model (Apple Intelligence or MLX)
    /// - Parameter model: The new model to use
    func switchModel(_ model: MLXModel) {
        logger.info("🔄 Switching to model: \(model.displayName)")
        self.selectedModel = model

        // Only update MLX manager if it's an MLX model
        if model.isOnDeviceMLX {
            mlxManager.switchModel(model)
        }

        logger.info("✅ Model switched successfully to \(model.displayName)")
    }

    /// Get the currently selected model
    func getCurrentModel() -> MLXModel {
        return selectedModel
    }

    /// Send text as a direct prompt to the LLM (no summarization system prompt)
    /// - Parameters:
    ///   - text: The prompt text to send
    ///   - progressHandler: Optional callback for model download progress (MLX fallback only)
    /// - Returns: The model's response
    func sendDirectPrompt(_ text: String, progressHandler: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        logger.info("📨 sendDirectPrompt() called with text length: \(text.count), selected model: \(self.selectedModel.displayName)")

        guard !text.isEmpty else {
            logger.error("❌ Cannot send empty prompt")
            throw NSError(
                domain: "SummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot send empty prompt"]
            )
        }

        // If user explicitly selected Apple Intelligence, try to use it
        if selectedModel == .appleIntelligence {
            logger.info("🔍 User selected Apple Intelligence, checking availability")
            switch model.availability {
            case .available:
                logger.info("✅ Using Apple Intelligence for direct prompt")
                isUsingMLXFallback = false
                return try await sendDirectPromptWithAppleIntelligence(text)

            case .unavailable(let reason):
                let reasonStr: String
                switch reason {
                case .appleIntelligenceNotEnabled:
                    reasonStr = "Apple Intelligence is not enabled on this device"
                case .deviceNotEligible:
                    reasonStr = "This device does not support Apple Intelligence (requires iPhone 15 Pro or later)"
                case .modelNotReady:
                    reasonStr = "Apple Intelligence model is not ready"
                @unknown default:
                    reasonStr = "Apple Intelligence is unavailable for unknown reason"
                }
                logger.error("❌ Apple Intelligence selected but unavailable: \(reasonStr)")
                throw NSError(
                    domain: "SummarizationManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: reasonStr]
                )
            }
        } else {
            // User selected an MLX model
            logger.info("✅ Using MLX model (\(self.selectedModel.displayName)) for direct prompt")
            isUsingMLXFallback = true
            return try await sendDirectPromptWithMLX(text, progressHandler: progressHandler)
        }
    }

    /// Send direct prompt using Apple Intelligence
    private func sendDirectPromptWithAppleIntelligence(_ text: String) async throws -> String {
        logger.info("📝 Sending direct prompt to Apple Intelligence")
        do {
            let response = try await session.respond(to: text)
            logger.info("✅ Received response from Apple Intelligence, length: \(response.content.count)")
            return response.content
        } catch {
            logger.error("❌ Apple Intelligence failed: \(error.localizedDescription)")
            throw NSError(
                domain: "SummarizationManager",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate response with Apple Intelligence",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
    }

    /// Send direct prompt using MLX models
    private func sendDirectPromptWithMLX(_ text: String, progressHandler: (@Sendable (Double) -> Void)?) async throws -> String {
        logger.info("🔄 Using MLX for direct prompt")

        // Check if running on simulator - provide mock implementation
        #if targetEnvironment(simulator)
        logger.warning("⚠️ Running on simulator - MLX not available")
        logger.info("📝 Returning mock response for simulator testing")

        let modelName = mlxManager.selectedModel.displayName

        let mockResponse = """
        This is a mock response from \(modelName) in simulator mode. \
        MLX requires a real iOS device with Metal GPU support to function. \
        To test the actual \(modelName) model, please deploy to a physical device.
        """

        if let handler = progressHandler {
            handler(1.0)
        }

        return mockResponse
        #else
        // Real device - use MLX
        do {
            // Load model with progress tracking if provided
            if let handler = progressHandler {
                try await mlxManager.loadModel(progressHandler: handler)
                // Save persistent flag after successful download
                setModelDownloaded(selectedModel)
            }

            let response = try await mlxManager.sendDirectPrompt(text)
            logger.info("✅ Received response from MLX model, length: \(response.count)")
            return response

        } catch {
            logger.error("❌ MLX direct prompt failed: \(error.localizedDescription)")
            throw NSError(
                domain: "SummarizationManager",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate response. Please ensure you have sufficient storage and try again.",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        #endif
    }

    /// Generate a streaming summary with real-time metrics
    /// - Parameters:
    ///   - text: The text to summarize
    ///   - onStream: Callback with partial text and performance metrics
    ///   - progressHandler: Optional callback for model download progress (MLX only)
    /// - Returns: Final summary text
    func summarizeStreaming(
        _ text: String,
        onStream: @escaping MLXSummarizationManager.StreamingCallback,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        logger.info("🚀 summarizeStreaming() called with text length: \(text.count), selected model: \(self.selectedModel.displayName)")

        guard !text.isEmpty else {
            throw NSError(
                domain: "SummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot summarize empty text"]
            )
        }

        // For Apple Intelligence, use non-streaming (it has its own streaming API but different interface)
        if selectedModel == .appleIntelligence {
            logger.info("⚠️ Apple Intelligence doesn't support MLX-style streaming metrics, falling back to regular summarize")
            let result = try await summarize(text, progressHandler: progressHandler)
            // Send final result through callback
            var finalMetrics = GenerationMetrics.initial(modelName: "Apple Intelligence")
            finalMetrics.isComplete = true
            onStream(result, finalMetrics)
            return result
        } else {
            // Use MLX streaming
            logger.info("✅ Using MLX streaming with \(self.selectedModel.displayName)")
            isUsingMLXFallback = true

            #if targetEnvironment(simulator)
            // Mock for simulator
            let mockSummary = "This is a mock streaming summary from \(selectedModel.displayName) in simulator mode."
            var mockMetrics = GenerationMetrics.initial(modelName: selectedModel.displayName)
            mockMetrics.isComplete = true
            onStream(mockSummary, mockMetrics)
            return mockSummary
            #else
            // Real device - use MLX streaming
            if let handler = progressHandler {
                try await mlxManager.loadModel(progressHandler: handler)
                // Save persistent flag after successful download
                setModelDownloaded(selectedModel)
            }
            return try await mlxManager.summarizeStreaming(text, onStream: onStream)
            #endif
        }
    }

    /// Send direct prompt with streaming updates and metrics
    /// - Parameters:
    ///   - text: The prompt text
    ///   - onStream: Callback with partial text and performance metrics
    ///   - progressHandler: Optional callback for model download progress (MLX only)
    /// - Returns: Final response text
    func sendDirectPromptStreaming(
        _ text: String,
        onStream: @escaping MLXSummarizationManager.StreamingCallback,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        logger.info("📨 sendDirectPromptStreaming() called with text length: \(text.count), selected model: \(self.selectedModel.displayName)")

        guard !text.isEmpty else {
            throw NSError(
                domain: "SummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot send empty prompt"]
            )
        }

        if selectedModel == .appleIntelligence {
            logger.info("⚠️ Apple Intelligence doesn't support MLX-style streaming metrics, falling back to regular prompt")
            let result = try await sendDirectPrompt(text, progressHandler: progressHandler)
            var finalMetrics = GenerationMetrics.initial(modelName: "Apple Intelligence")
            finalMetrics.isComplete = true
            onStream(result, finalMetrics)
            return result
        } else {
            logger.info("✅ Using MLX streaming with \(self.selectedModel.displayName)")
            isUsingMLXFallback = true

            #if targetEnvironment(simulator)
            let mockResponse = "This is a mock streaming response from \(selectedModel.displayName) in simulator mode."
            var mockMetrics = GenerationMetrics.initial(modelName: selectedModel.displayName)
            mockMetrics.isComplete = true
            onStream(mockResponse, mockMetrics)
            return mockResponse
            #else
            if let handler = progressHandler {
                try await mlxManager.loadModel(progressHandler: handler)
                // Save persistent flag after successful download
                setModelDownloaded(selectedModel)
            }
            return try await mlxManager.sendDirectPromptStreaming(text, onStream: onStream)
            #endif
        }
    }
}
