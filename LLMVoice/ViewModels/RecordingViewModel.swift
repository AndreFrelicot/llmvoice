//
//  RecordingViewModel.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import AVFoundation
import Foundation
import SwiftUI
import os.log

/// ViewModel managing the recording state, transcription, and summarization
@MainActor
@Observable
final class RecordingViewModel {
    private let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "RecordingViewModel")
    // MARK: - Published State
    private(set) var isRecording = false
    private(set) var isResolvingTranscription = false
    private(set) var finalizedTranscription = ""
    private(set) var volatileTranscription = ""
    private(set) var summaries: [Summary] = []
    private(set) var errorMessage: String?
    private(set) var isProcessingSummary = false
    private(set) var modelDownloadProgress: Double = 0.0
    private(set) var isDownloadingModel = false
    private(set) var speechModelReady = false
    private(set) var llmModelReady = false

    // Streaming state
    private(set) var streamingState = StreamingState.initial(modelName: "")
    private(set) var showMetrics = false

    // Model loading state
    private(set) var isLoadingModel = false
    private(set) var modelLoadProgress: Double = 0.0

    var selectedLanguage: TranscriptionLanguage {
        didSet {
            // Save language preference
            saveLanguagePreference()
        }
    }
    var selectedModel: MLXModel {
        didSet {
            // Save model preference
            saveModelPreference()

            // Reset performance metrics when changing model
            streamingState = StreamingState.initial(modelName: self.selectedModel.displayName)
            logger.info("🔄 Reset performance metrics for new model: \(self.selectedModel.displayName)")

            // Switch model in summarization manager
            if #available(iOS 26.0, macOS 26.0, *),
               let manager = summarizationManager as? SummarizationManager {
                manager.switchModel(self.selectedModel)
                // Mark model as not ready since we switched
                llmModelReady = false
                // Trigger model load for the new model
                Task {
                    await self.preloadModel()
                }
            }
        }
    }

    // MARK: - Managers
    private let audioManager = AudioManager()
    private var transcriptionManager: Any?
    private var summarizationManager: Any?

    // Generation task for cancellation
    private var generationTask: Task<Void, Never>?
    private var lastStreamingUIUpdate = Date.distantPast
    private let minimumStreamingUIUpdateInterval: TimeInterval = 0.08

    init() {
        // Load preferences first (before any logging that references them)
        selectedLanguage = Self.loadLanguagePreference()
        selectedModel = Self.loadModelPreference()

        logger.info("🎬 RecordingViewModel initializing")
        logger.info("🌍 Selected language: \(self.selectedLanguage.name) (\(self.selectedLanguage.localeIdentifier))")
        logger.info("🤖 Selected model: \(self.selectedModel.displayName)")

        if #available(iOS 26.0, macOS 26.0, *) {
            logger.info("✅ iOS 26+ detected, initializing managers")
            logger.info("📝 Creating TranscriptionManager")
            transcriptionManager = TranscriptionManager()
            logger.info("✅ TranscriptionManager created")

            logger.info("🤖 Creating SummarizationManager with model: \(self.selectedModel.displayName)")
            summarizationManager = SummarizationManager(model: self.selectedModel)
            logger.info("✅ SummarizationManager created")
        } else {
            logger.warning("⚠️ iOS version < 26.0, managers not available")
        }

        logger.info("💾 Loading saved summaries")
        loadSummaries()
        logger.info("✅ RecordingViewModel initialized with \(self.summaries.count) summaries")

        // Check model readiness
        checkModelReadiness()
    }

    // MARK: - Public Methods

    /// Check if models are ready to use
    func checkModelReadiness() {
        logger.info("🔍 Checking model readiness")

        // Speech model is always ready (built-in)
        speechModelReady = true
        logger.info("✅ Speech model ready (built-in)")

        // Check LLM model
        if #available(iOS 26.0, macOS 26.0, *),
           let manager = summarizationManager as? SummarizationManager {
            llmModelReady = manager.isMLXModelReady()
            logger.info("📊 LLM model ready: \(self.llmModelReady)")
        }
    }

    /// Download models if needed
    func downloadModels() async {
        logger.info("📥 Starting model download")

        guard #available(iOS 26.0, macOS 26.0, *) else {
            logger.error("❌ iOS 26+ required for model download")
            return
        }

        guard let manager = summarizationManager as? SummarizationManager else {
            logger.error("❌ Summarization manager not available")
            return
        }

        // Speech model is already available (built-in)
        speechModelReady = true

        // Download LLM model by triggering a test summarization
        do {
            logger.info("🔄 Triggering LLM model download")
            isDownloadingModel = true

            // Use a test text to trigger model download
            let testText = "This is a test to download the model."
            _ = try await manager.summarize(testText) { [weak self] progress in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.modelDownloadProgress = progress
                    self.logger.info("📥 Model download progress: \(Int(progress * 100))%")
                }
            }

            llmModelReady = true
            isDownloadingModel = false
            modelDownloadProgress = 1.0
            logger.info("✅ LLM model downloaded successfully")

        } catch {
            logger.error("❌ Failed to download LLM model: \(error.localizedDescription)")
            errorMessage = "Failed to download model: \(error.localizedDescription)"
            isDownloadingModel = false
        }
    }

    /// Toggle recording on/off
    func toggleRecording() {
        logger.info("🎤 Toggle recording called, current state: \(self.isRecording ? "recording" : "stopped")")
        if isRecording {
            logger.info("⏹️ Stopping recording")
            Task { await stopRecording() }
        } else {
            logger.info("▶️ Starting recording")
            Task { await startRecording() }
        }
    }

    /// Delete a summary from the list
    func deleteSummary(_ summary: Summary) {
        logger.info("🗑️ Deleting summary: \(summary.id)")
        summaries.removeAll { $0.id == summary.id }
        saveSummaries()
        logger.info("✅ Summary deleted, remaining: \(self.summaries.count)")
    }

    /// Clear all summaries
    func clearAllSummaries() {
        logger.info("🧹 Clearing all summaries")
        summaries.removeAll()
        saveSummaries()
        logger.info("✅ All summaries cleared")
    }

    /// Handle memory warning - aggressive cleanup
    func handleMemoryWarning() {
        logger.warning("⚠️ Memory warning received")

        if #available(iOS 26.0, macOS 26.0, *),
           let manager = summarizationManager as? SummarizationManager {
            manager.handleMemoryWarning()
        }
    }

    /// Clear all downloaded models from device
    func clearModelCache() throws {
        logger.warning("🗑️ Clearing all model caches from device")

        // Create a ModelDownloadManager instance to access its clearAllModels method
        let downloadManager = ModelDownloadManager()

        // Clear all downloaded models (excluding bundled models)
        downloadManager.clearAllModels()

        // Mark model as not ready since we cleared everything
        llmModelReady = false
        logger.info("✅ All model caches cleared")
    }

    /// Get the model cache directory path
    func getModelCacheDirectory() -> String? {
        guard #available(iOS 26.0, macOS 26.0, *),
              let manager = summarizationManager as? SummarizationManager else {
            return nil
        }

        return manager.getModelCacheDirectory()?.path
    }

    /// Set an error message to display to the user
    func setErrorMessage(_ message: String) {
        errorMessage = message
    }

    /// Summarize the given text (triggered manually by user)
    func summarizeText(_ text: String) async {
        logger.info("📝 Manual summarization requested for text length: \(text.count)")
        guard !text.isEmpty else {
            logger.warning("⚠️ Cannot summarize empty text")
            return
        }
        await generateSummary(for: text)
    }

    /// Send text as a direct prompt to the LLM (no summarization system prompt)
    func sendDirectPrompt(_ text: String) async {
        logger.info("📨 Direct prompt requested for text length: \(text.count)")
        guard !text.isEmpty else {
            logger.warning("⚠️ Cannot send empty prompt")
            return
        }
        await generateDirectResponse(for: text)
    }

    /// Cancel the current generation if running
    func cancelGeneration() {
        logger.info("🚫 Cancel generation requested")
        guard let task = generationTask else {
            logger.warning("⚠️ No generation task to cancel")
            return
        }

        logger.info("❌ Cancelling generation task")
        task.cancel()
        generationTask = nil

        // Clean up state
        isProcessingSummary = false
        isLoadingModel = false
        streamingState.isStreaming = false
        streamingState.error = "Generation cancelled by user"

        logger.info("✅ Generation cancelled")
    }

    /// Cancel generation when app enters background (iOS doesn't allow GPU operations in background)
    func cancelGenerationOnBackground() {
        logger.info("📱 App entering background - cancelling generation if running")

        if generationTask != nil {
            logger.info("🚫 Cancelling active generation to prevent GPU background crash")

            // Append cancellation message to partial text before cancelling
            if !streamingState.partialText.isEmpty {
                streamingState.partialText += "\n\n[...generation cancelled after going background mode...]"
            }

            cancelGeneration()
            streamingState.error = "Generation paused (app backgrounded)"
        } else {
            logger.info("✅ No active generation, model stays loaded and ready")
        }
    }

    /// Preload the model (e.g., when switching models)
    func preloadModel() async {
        logger.info("🔄 Preloading model: \(self.selectedModel.displayName)")

        guard #available(iOS 26.0, macOS 26.0, *) else {
            logger.warning("⚠️ Model preloading requires iOS 26.0+")
            return
        }

        guard let manager = summarizationManager as? SummarizationManager else {
            logger.warning("⚠️ Summarization manager not available")
            return
        }

        // Only preload if it's an MLX model and not already ready
        guard self.selectedModel.isOnDeviceMLX && !self.llmModelReady else {
            logger.info("ℹ️ Model already ready or not an MLX model, skipping preload")
            return
        }

        isLoadingModel = true
        modelLoadProgress = 0.0
        errorMessage = nil

        do {
            // Use a test text to trigger model loading
            let testText = "test"
            _ = try await manager.summarize(testText) { [weak self] progress in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.modelLoadProgress = progress
                    self.logger.info("📥 Model load progress: \(Int(progress * 100))%")
                }
            }

            llmModelReady = true
            modelLoadProgress = 1.0
            logger.info("✅ Model preloaded successfully")

        } catch {
            logger.error("❌ Failed to preload model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isLoadingModel = false
    }

    // MARK: - Private Methods

    private func startRecording() async {
        logger.info("🎙️ startRecording() called")
        do {
            logger.info("🧹 Clearing previous state")
            errorMessage = nil
            finalizedTranscription = ""
            volatileTranscription = ""

            logger.info("🔍 Checking iOS version availability")
            guard #available(iOS 26.0, macOS 26.0, *) else {
                logger.error("❌ iOS version check failed")
                throw NSError(
                    domain: "RecordingViewModel",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Speech transcription requires iOS 26.0 or later"]
                )
            }

            logger.info("🔍 Checking transcription manager")
            guard let manager = transcriptionManager as? TranscriptionManager else {
                logger.error("❌ Transcription manager not available")
                throw NSError(
                    domain: "RecordingViewModel",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Transcription manager not available"]
                )
            }

            logger.info("✅ Transcription manager available")
            logger.info("🚀 Starting transcription with language: \(self.selectedLanguage.name)")
            // Start transcription with selected language
            try await manager.startTranscription(locale: Locale(identifier: self.selectedLanguage.localeIdentifier)) { [weak self] text, isFinal in
                guard let self = self else { return }

                Task { @MainActor in
                    self.logger.info("🎤 TRANSCRIPTION CALLBACK:")
                    self.logger.info("   • text: '\(text)'")
                    self.logger.info("   • isFinal: \(isFinal)")
                    self.logger.info("   • isRecording: \(self.isRecording)")
                    self.logger.info("   • isResolvingTranscription: \(self.isResolvingTranscription)")
                    self.logger.info("   • BEFORE: volatile='\(self.volatileTranscription)', finalized.count=\(self.finalizedTranscription.count)")

                    if isFinal {
                        // Final result - append to finalized transcription
                        if !self.finalizedTranscription.isEmpty && !text.isEmpty {
                            self.finalizedTranscription += " "
                        }
                        self.finalizedTranscription += text
                        // Clear volatile result to avoid duplicates
                        self.volatileTranscription = ""
                        self.logger.info("✅ FINAL transcription processed")
                        self.logger.info("   • AFTER: volatile='\(self.volatileTranscription)', finalized='\(self.finalizedTranscription)'")
                    } else {
                        // Volatile result - show immediately as real-time guess
                        self.volatileTranscription = text
                        self.logger.info("⚡ VOLATILE transcription updated")
                        self.logger.info("   • AFTER: volatile='\(self.volatileTranscription)'")
                    }
                }
            }

            logger.info("✅ Transcription started successfully")
            logger.info("🎧 Starting audio stream")

            // Capture manager reference BEFORE entering audio callback to avoid MainActor isolation issues
            let capturedManager = manager
            let capturedLogger = logger
            let capturedAudioManager = audioManager

            // Start audio recording in a detached task to avoid MainActor isolation issues
            try await Task.detached {
                try capturedAudioManager.startAudioStream { @Sendable buffer in
                    // Process buffer directly on audio thread since processAudioBuffer is nonisolated
                    do {
                        try capturedManager.processAudioBuffer(buffer)
                    } catch {
                        // Log error on MainActor
                        Task { @MainActor in
                            capturedLogger.error("❌ Error processing audio buffer: \(error.localizedDescription)")
                        }
                    }
                }
            }.value

            logger.info("✅ Audio stream started successfully")

            isRecording = true
            logger.info("✅ Recording started successfully")
        } catch {
            logger.error("❌ Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        logger.info("⏹️ ========== stopRecording() CALLED ==========")
        logger.info("📊 INITIAL STATE:")
        logger.info("   • isRecording: \(self.isRecording)")
        logger.info("   • finalizedTranscription.count: \(self.finalizedTranscription.count)")
        logger.info("   • finalizedTranscription: '\(self.finalizedTranscription)'")
        logger.info("   • volatileTranscription.count: \(self.volatileTranscription.count)")
        logger.info("   • volatileTranscription: '\(self.volatileTranscription)'")

        isRecording = false
        isResolvingTranscription = true
        logger.info("🟠 STATE CHANGED: isRecording=false, isResolvingTranscription=true")

        logger.info("🛑 STEP 1: Stopping audio stream...")
        let capturedAudioManager = audioManager
        await Task.detached {
            capturedAudioManager.stopAudioStream()
        }.value
        logger.info("✅ Audio stream stopped")
        logger.info("📊 AFTER AUDIO STOP: volatile='\(self.volatileTranscription)', finalized.count=\(self.finalizedTranscription.count)")

        logger.info("🛑 STEP 2: Stopping transcription to trigger finalization...")
        if #available(iOS 26.0, macOS 26.0, *),
           let manager = transcriptionManager as? TranscriptionManager {
            await manager.stopTranscription()
            logger.info("✅ Transcription stopTranscription() returned")
        }
        logger.info("📊 AFTER STOP TRANSCRIPTION: volatile='\(self.volatileTranscription)', finalized.count=\(self.finalizedTranscription.count)")

        logger.info("⏳ STEP 3: Polling for volatile text to resolve...")
        let maxWaitTime: TimeInterval = 10.0
        let pollInterval: TimeInterval = 0.1
        let startTime = Date()
        var pollCount = 0

        while !self.volatileTranscription.isEmpty {
            let elapsedTime = Date().timeIntervalSince(startTime)
            pollCount += 1

            logger.info("🔄 POLL #\(pollCount) (t=\(String(format: "%.2f", elapsedTime))s):")
            logger.info("   • volatileTranscription: '\(self.volatileTranscription)'")
            logger.info("   • finalizedTranscription.count: \(self.finalizedTranscription.count)")

            if elapsedTime >= maxWaitTime {
                logger.warning("⚠️ SAFETY TIMEOUT reached after \(String(format: "%.1f", elapsedTime))s")
                logger.warning("   • volatile STILL contains: '\(self.volatileTranscription)'")
                break
            }

            try? await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        logger.info("📊 AFTER POLLING LOOP:")
        logger.info("   • pollCount: \(pollCount)")
        logger.info("   • volatileTranscription.isEmpty: \(self.volatileTranscription.isEmpty)")
        logger.info("   • volatileTranscription: '\(self.volatileTranscription)'")
        logger.info("   • finalizedTranscription: '\(self.finalizedTranscription)'")

        // NEVER delete volatile text - always preserve it
        if !self.volatileTranscription.isEmpty {
            let waitTime = Date().timeIntervalSince(startTime)
            logger.info("📝 PRESERVING VOLATILE TEXT (waited \(String(format: "%.2f", waitTime))s):")
            logger.info("   • volatile to preserve: '\(self.volatileTranscription)'")
            logger.info("   • current finalized: '\(self.finalizedTranscription)'")

            if !self.finalizedTranscription.isEmpty {
                self.finalizedTranscription += " "
            }
            self.finalizedTranscription += self.volatileTranscription

            logger.info("   • NEW finalized: '\(self.finalizedTranscription)'")
            logger.info("   • NEW finalized.count: \(self.finalizedTranscription.count)")

            self.volatileTranscription = ""
            logger.info("   • volatile cleared")
        } else {
            let waitTime = Date().timeIntervalSince(startTime)
            logger.info("✅ VOLATILE RESOLVED NATURALLY in \(String(format: "%.2f", waitTime))s")
        }

        isResolvingTranscription = false
        logger.info("🟢 STATE CHANGED: isResolvingTranscription=false")
        logger.info("========== stopRecording() COMPLETE ==========")
        logger.info("📊 FINAL STATE:")
        logger.info("   • finalizedTranscription: '\(self.finalizedTranscription)'")
        logger.info("   • volatileTranscription: '\(self.volatileTranscription)'")
    }

    private func resetStreamingState() {
        streamingState = StreamingState.initial(modelName: selectedModel.displayName)
        streamingState.isStreaming = true
        lastStreamingUIUpdate = .distantPast
    }

    private func applyStreamingUpdate(partialText: String, metrics: GenerationMetrics) {
        let now = Date()
        let tokenDelta = metrics.totalTokens - streamingState.metrics.totalTokens
        let enoughTimeElapsed = now.timeIntervalSince(lastStreamingUIUpdate) >= minimumStreamingUIUpdateInterval
        let shouldUpdate = metrics.isComplete
            || streamingState.partialText.isEmpty
            || tokenDelta >= 3
            || enoughTimeElapsed

        guard shouldUpdate else { return }

        if streamingState.partialText != partialText {
            streamingState.partialText = partialText
        }

        if streamingState.metrics != metrics {
            streamingState.metrics = metrics
        }

        let isStreaming = !metrics.isComplete
        if streamingState.isStreaming != isStreaming {
            streamingState.isStreaming = isStreaming
        }

        lastStreamingUIUpdate = now
    }

    private func generateSummary(for text: String) async {
        logger.info("🤖 generateSummary() called with text length: \(text.count)")
        isProcessingSummary = true
        isLoadingModel = true
        modelLoadProgress = 0.0
        errorMessage = nil

        resetStreamingState()
        showMetrics = true

        // Store the task for cancellation - DON'T await it, let it run in background
        generationTask = Task {
            await performGenerateSummary(for: text)
            // Clear task reference when done
            await MainActor.run {
                self.generationTask = nil
            }
        }
    }

    private func performGenerateSummary(for text: String) async {
        do {
            // Check if cancelled before starting
            try Task.checkCancellation()

            logger.info("🔍 Checking iOS version for summarization")
            guard #available(iOS 26.0, macOS 26.0, *) else {
                logger.error("❌ iOS version check failed for summarization")
                throw NSError(
                    domain: "RecordingViewModel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "AI summarization requires iOS 26.0 or later"]
                )
            }

            logger.info("🔍 Checking summarization manager")
            guard let manager = summarizationManager as? SummarizationManager else {
                logger.error("❌ Summarization manager not available")
                throw NSError(
                    domain: "RecordingViewModel",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Summarization manager not available"]
                )
            }

            logger.info("✅ Summarization manager available")
            logger.info("🚀 Starting streaming summarization")

            let startTime = Date()

            // Use streaming summarization with metrics
            let summaryText = try await manager.summarizeStreaming(text, onStream: { [weak self] partialText, metrics in
                guard let self = self else { return }
                self.applyStreamingUpdate(partialText: partialText, metrics: metrics)

                // Log progress
                if metrics.totalTokens % 10 == 0 || metrics.isComplete {
                    self.logger.info("📊 Tokens: \(metrics.totalTokens), TPS: \(metrics.formattedTPS), Time: \(metrics.formattedTotalTime)")
                }
            }, progressHandler: { [weak self] progress in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.modelDownloadProgress = progress
                    self.modelLoadProgress = progress
                    self.isDownloadingModel = progress < 1.0
                    self.isLoadingModel = progress < 1.0
                }
            })

            isLoadingModel = false
            let endTime = Date()
            let computationTime = endTime.timeIntervalSince(startTime)

            logger.info("✅ Summary generated, length: \(summaryText.count)")
            logger.info("⏱️ Computation time: \(String(format: "%.2f", computationTime))s")
            logger.info("🤖 Model used: \(self.selectedModel.displayName)")
            logger.info("📋 Summary: \(summaryText)")
            logger.info("📊 Final metrics: \(self.streamingState.metrics.totalTokens) tokens, \(self.streamingState.metrics.formattedAvgTPS) tok/s avg")
            isDownloadingModel = false

            let newSummary = Summary(
                content: summaryText,
                originalTranscription: text,
                computationTime: computationTime,
                modelUsed: self.selectedModel.displayName
            )

            logger.info("💾 Saving summary")
            summaries.insert(newSummary, at: 0)
            saveSummaries()
            logger.info("✅ Summary saved, total summaries: \(self.summaries.count)")

            // Keep metrics visible (don't hide them)
            // showMetrics remains true so user can see final performance

        } catch is CancellationError {
            logger.info("🚫 Generation cancelled by user")
            streamingState.error = "Generation cancelled by user"
            streamingState.isStreaming = false
            isLoadingModel = false
            isProcessingSummary = false
        } catch {
            logger.error("❌ Failed to generate summary: \(error.localizedDescription)")
            errorMessage = "Failed to generate summary: \(error.localizedDescription)"
            streamingState.error = error.localizedDescription
            streamingState.isStreaming = false
            isLoadingModel = false
        }

        isProcessingSummary = false
        logger.info("✅ Summary generation complete")
    }

    private func generateDirectResponse(for text: String) async {
        logger.info("🚀 generateDirectResponse() called with text length: \(text.count)")
        isProcessingSummary = true
        isLoadingModel = true
        modelLoadProgress = 0.0
        errorMessage = nil

        resetStreamingState()
        showMetrics = true

        // Store the task for cancellation - DON'T await it, let it run in background
        generationTask = Task {
            await performGenerateDirectResponse(for: text)
            // Clear task reference when done
            await MainActor.run {
                self.generationTask = nil
            }
        }
    }

    private func performGenerateDirectResponse(for text: String) async {
        do {
            // Check if cancelled before starting
            try Task.checkCancellation()

            logger.info("🔍 Checking iOS version for direct prompt")
            guard #available(iOS 26.0, macOS 26.0, *) else {
                logger.error("❌ iOS version check failed for direct prompt")
                throw NSError(
                    domain: "RecordingViewModel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "AI requires iOS 26.0 or later"]
                )
            }

            logger.info("🔍 Checking summarization manager")
            guard let manager = summarizationManager as? SummarizationManager else {
                logger.error("❌ Summarization manager not available")
                throw NSError(
                    domain: "RecordingViewModel",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Summarization manager not available"]
                )
            }

            logger.info("✅ Summarization manager available")
            logger.info("🚀 Sending streaming direct prompt")

            let startTime = Date()

            // Use streaming direct prompt with metrics
            let responseText = try await manager.sendDirectPromptStreaming(text, onStream: { [weak self] partialText, metrics in
                guard let self = self else { return }
                self.applyStreamingUpdate(partialText: partialText, metrics: metrics)

                // Log progress
                if metrics.totalTokens % 10 == 0 || metrics.isComplete {
                    self.logger.info("📊 Tokens: \(metrics.totalTokens), TPS: \(metrics.formattedTPS), Time: \(metrics.formattedTotalTime)")
                }
            }, progressHandler: { [weak self] progress in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.modelDownloadProgress = progress
                    self.modelLoadProgress = progress
                    self.isDownloadingModel = progress < 1.0
                    self.isLoadingModel = progress < 1.0
                }
            })

            isLoadingModel = false
            let endTime = Date()
            let computationTime = endTime.timeIntervalSince(startTime)

            logger.info("✅ Response generated, length: \(responseText.count)")
            logger.info("⏱️ Computation time: \(String(format: "%.2f", computationTime))s")
            logger.info("🤖 Model used: \(self.selectedModel.displayName)")
            logger.info("📋 Response: \(responseText)")
            logger.info("📊 Final metrics: \(self.streamingState.metrics.totalTokens) tokens, \(self.streamingState.metrics.formattedAvgTPS) tok/s avg")
            isDownloadingModel = false

            let newSummary = Summary(
                content: responseText,
                originalTranscription: text,
                computationTime: computationTime,
                modelUsed: self.selectedModel.displayName
            )

            logger.info("💾 Saving response")
            summaries.insert(newSummary, at: 0)
            saveSummaries()
            logger.info("✅ Response saved, total summaries: \(self.summaries.count)")

            // Keep metrics visible (don't hide them)
            // showMetrics remains true so user can see final performance

        } catch is CancellationError {
            logger.info("🚫 Generation cancelled by user")
            streamingState.error = "Generation cancelled by user"
            streamingState.isStreaming = false
            isLoadingModel = false
            isProcessingSummary = false
        } catch {
            logger.error("❌ Failed to generate response: \(error.localizedDescription)")
            errorMessage = "Failed to generate response: \(error.localizedDescription)"
            streamingState.error = error.localizedDescription
            streamingState.isStreaming = false
            isLoadingModel = false
        }

        isProcessingSummary = false
        logger.info("✅ Direct response generation complete")
    }

    // MARK: - Persistence

    private func saveSummaries() {
        logger.info("💾 Saving \(self.summaries.count) summaries to UserDefaults")
        do {
            let data = try JSONEncoder().encode(summaries)
            UserDefaults.standard.set(data, forKey: "savedSummaries")
            logger.info("✅ Summaries saved successfully")
        } catch {
            logger.error("❌ Failed to save summaries: \(error.localizedDescription)")
        }
    }

    private func loadSummaries() {
        logger.info("📂 Loading summaries from UserDefaults")
        guard let data = UserDefaults.standard.data(forKey: "savedSummaries") else {
            logger.info("ℹ️ No saved summaries found")
            return
        }

        do {
            summaries = try JSONDecoder().decode([Summary].self, from: data)
            logger.info("✅ Loaded \(self.summaries.count) summaries")
        } catch {
            logger.error("❌ Failed to load summaries: \(error.localizedDescription)")
        }
    }

    // MARK: - Language Preference

    private func saveLanguagePreference() {
        logger.info("💾 Saving language preference: \(self.selectedLanguage.name)")
        do {
            let data = try JSONEncoder().encode(selectedLanguage)
            UserDefaults.standard.set(data, forKey: "selectedLanguage")
            logger.info("✅ Language preference saved")
        } catch {
            logger.error("❌ Failed to save language preference: \(error.localizedDescription)")
        }
    }

    private static func loadLanguagePreference() -> TranscriptionLanguage {
        guard let data = UserDefaults.standard.data(forKey: "selectedLanguage") else {
            // No saved preference, return device preferred or default
            return TranscriptionLanguage.devicePreferred
        }

        do {
            let language = try JSONDecoder().decode(TranscriptionLanguage.self, from: data)
            return language
        } catch {
            // Failed to decode, return device preferred or default
            return TranscriptionLanguage.devicePreferred
        }
    }

    // MARK: - Model Preference

    private func saveModelPreference() {
        logger.info("💾 Saving model preference: \(self.selectedModel.displayName)")
        do {
            let data = try JSONEncoder().encode(selectedModel)
            UserDefaults.standard.set(data, forKey: "selectedModel")
            logger.info("✅ Model preference saved")
        } catch {
            logger.error("❌ Failed to save model preference: \(error.localizedDescription)")
        }
    }

    private static func loadModelPreference() -> MLXModel {
        guard let data = UserDefaults.standard.data(forKey: "selectedModel") else {
            // No saved preference, return default (Qwen3)
            return .qwen3_06b
        }

        do {
            let model = try JSONDecoder().decode(MLXModel.self, from: data)
            return model
        } catch {
            // Failed to decode, return default
            return .qwen3_06b
        }
    }
}
