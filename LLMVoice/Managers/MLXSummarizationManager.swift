//
//  MLXSummarizationManager.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import os.log

/// Manages task extraction using MLX Swift with multiple model support
/// This serves as a fallback for devices that don't support Apple Intelligence
/// Supports: Gemma 3, Qwen2.5, Llama 3.2 (all 4-bit quantized)
/// NOTE: MLX requires real iOS devices with Metal GPU support - not available on simulators
@MainActor
final class MLXSummarizationManager {
    private let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "MLXSummarizationManager")

    // Selected model configuration
    private(set) var selectedModel: MLXModel
    private var modelContainer: ModelContainer?
    private var downloadState: ModelDownloadState = .notDownloaded
    private let parametersManager = ModelParametersManager()

    init(model: MLXModel = .qwen25_05b) {
        self.selectedModel = model
        logger.info("🤖 MLXSummarizationManager initializing with \(model.displayName)")

        // Set HuggingFace cache directory to Application Support
        if let modelDir = getModelCacheDirectory()?.deletingLastPathComponent() {
            // Set to parent directory (before "huggingface" part)
            setenv("HF_HOME", modelDir.path, 1)
            logger.info("📂 Set HF_HOME to: \(modelDir.path)")
        }

        #if targetEnvironment(simulator)
        logger.warning("⚠️ Running on simulator - MLX not available (requires Metal GPU)")
        logger.warning("⚠️ MLX features will be disabled. Use a real device to test MLX functionality.")
        #else
        // Check device compatibility
        if !DeviceCapabilities.supportsMLX {
            logger.error("❌ Device does not support MLX")
            logger.error("❌ Device: \(DeviceCapabilities.deviceModelName)")
            logger.error("❌ Reason: \(DeviceCapabilities.mlxUnsupportedReason)")
            logger.error("⚠️ MLX features will be disabled to prevent crashes")
            return
        }

        // Set memory limits optimized for selected model (real device only)
        GPU.set(cacheLimit: model.cacheLimitBytes)
        GPU.set(memoryLimit: model.memoryLimitBytes, relaxed: false)

        logger.info("💾 Memory limits set - Cache: \(model.cacheLimitBytes / 1024 / 1024)MB, Total: \(model.memoryLimitBytes / 1024 / 1024)MB")

        // Log device info
        let deviceInfo = GPU.deviceInfo()
        logger.info("📱 Device: \(deviceInfo.architecture), Total RAM: \(deviceInfo.memorySize / 1024 / 1024)MB")
        logger.info("📦 Model: \(model.displayName) (\(model.parameters)M params, ~\(model.sizeInMB)MB)")
        #endif
    }

    /// Check if the model is available (bundled in app or cached on disk)
    var isModelReady: Bool {
        #if targetEnvironment(simulator)
        // Not available on simulator
        return false
        #else
        // Check device compatibility first
        if !DeviceCapabilities.supportsMLX {
            return false
        }

        // If loaded in memory, definitely ready
        if modelContainer != nil {
            return true
        }

        // Check if model is bundled in app
        if let bundlePath = getBundledModelPath() {
            logger.info("✅ Model found in app bundle at: \(bundlePath)")
            return true
        }

        // Check persistent download flag (from ModelDownloadManager)
        let downloadedModelsKey = "dev.andrefrelicot.llmvoice.downloadedModels"
        let downloadedFlags = Set(UserDefaults.standard.stringArray(forKey: downloadedModelsKey) ?? [])
        let hasFlag = downloadedFlags.contains(selectedModel.rawValue)

        // Check if model files exist in cache
        guard let cacheDir = getModelCacheDirectory() else {
            logger.warning("⚠️ Could not get cache directory")
            // If we have a flag but no cache dir, trust the flag
            return hasFlag
        }

        // Check all possible cache patterns (handles case sensitivity)
        var filesExist = false
        for pattern in self.selectedModel.possibleCachePatterns {
            let modelPath = cacheDir.appendingPathComponent(pattern)

            // Check if directory exists
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory), isDirectory.boolValue {
                // Verify config.json exists
                let configPath = modelPath.appendingPathComponent("config.json")
                if FileManager.default.fileExists(atPath: configPath.path) {
                    logger.info("✅ Model files found in cache at: \(modelPath.path)")
                    filesExist = true
                    break
                }
            }
        }

        // Model is ready if either files exist OR we have a persistent flag
        let isReady = filesExist || hasFlag

        if isReady {
            logger.info("✅ Model \(self.selectedModel.displayName) is ready (files: \(filesExist), flag: \(hasFlag))")
        } else {
            logger.info("⚠️ Model \(self.selectedModel.displayName) not found in bundle, cache, or flags")
        }

        return isReady
        #endif
    }

    /// Get the path to bundled model in app bundle
    private func getBundledModelPath() -> String? {
        guard let bundlePath = Bundle.main.resourcePath else {
            return nil
        }

        // Check if this model has a bundled folder name
        guard let bundledFolderName = self.selectedModel.bundledFolderName else {
            logger.info("ℹ️ Model \(self.selectedModel.displayName) is not bundled, will download from HuggingFace")
            return nil
        }

        // Check if model files are directly in the bundle root (fileSystemSynchronizedGroups behavior)
        let configPath = (bundlePath as NSString).appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath) {
            logger.info("✅ Found bundled model files at bundle root")
            // Return the bundle path itself since files are at root
            return bundlePath
        }

        // Try different possible folder paths
        let possiblePaths = [
            bundledFolderName,
            "Models/\(bundledFolderName)",
            "Models 2/\(bundledFolderName)"
        ]

        for relativePath in possiblePaths {
            let modelPath = (bundlePath as NSString).appendingPathComponent(relativePath)
            let configInFolder = (modelPath as NSString).appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: configInFolder) {
                logger.info("✅ Found bundled model at: \(relativePath)")
                return modelPath
            }
        }

        logger.warning("⚠️ Bundled model not found. Tried paths: bundle root, \(possiblePaths)")
        return nil
    }

    /// Get the current download state
    func getDownloadState() -> ModelDownloadState {
        return downloadState
    }

    /// Load the selected MLX model (4-bit quantized)
    /// - Parameters:
    ///   - progressHandler: Callback for download progress updates
    ///   - maxRetries: Maximum number of retry attempts (default: 5, increased for better reliability)
    func loadModel(progressHandler: @escaping @Sendable (Double) -> Void, maxRetries: Int = 5) async throws {
        logger.info("📦 Loading \(self.selectedModel.displayName) (\(self.selectedModel.parameters)M params, ~\(self.selectedModel.sizeInMB)MB)")

        #if !targetEnvironment(simulator)
        // Check device compatibility
        guard DeviceCapabilities.supportsMLX else {
            let errorMsg = DeviceCapabilities.mlxUnsupportedReason
            logger.error("❌ \(errorMsg)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 20,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMsg,
                    NSLocalizedFailureReasonErrorKey: "Device: \(DeviceCapabilities.deviceModelName)"
                ]
            )
        }
        #endif

        guard modelContainer == nil else {
            logger.info("✅ Model already loaded")
            return
        }

        // Store original memory limits for restoration later
        let originalCacheLimit = selectedModel.cacheLimitBytes
        let originalMemoryLimit = selectedModel.memoryLimitBytes

        // CRITICAL: Free all memory before download to prevent crashes
        #if !targetEnvironment(simulator)
        logger.info("🧹 Clearing GPU memory before download")
        GPU.clearCache()
        GPU.resetPeakMemory()

        // Log available memory
        let memoryBefore = GPU.snapshot()
        logger.info("💾 Memory before download - Active: \(memoryBefore.activeMemory / 1024 / 1024)MB, Cache: \(memoryBefore.cacheMemory / 1024 / 1024)MB")

        // Temporarily reduce memory limits during download to prevent crashes
        GPU.set(cacheLimit: 64 * 1024 * 1024)  // 64MB during download
        GPU.set(memoryLimit: 512 * 1024 * 1024, relaxed: true)  // 512MB during download, relaxed
        logger.info("💾 Reduced memory limits during download - Cache: 64MB, Total: 512MB (relaxed)")
        #endif

        // Check if model is bundled in app
        if let bundledPath = getBundledModelPath() {
            logger.info("📦 Loading model from app bundle: \(bundledPath)")
            downloadState = .downloading(progress: 0.0)

            do {
                // Load from bundle using URL-based configuration
                let bundleURL = URL(fileURLWithPath: bundledPath)
                let configuration = ModelConfiguration(directory: bundleURL)

                // Report immediate progress since no download needed
                progressHandler(1.0)
                downloadState = .downloading(progress: 1.0)

                logger.info("📂 Loading from bundle...")
                modelContainer = try await LLMModelFactory.shared.loadContainer(
                    configuration: configuration
                )

                downloadState = .downloaded

                #if !targetEnvironment(simulator)
                // Restore original memory limits after successful bundle load
                GPU.set(cacheLimit: originalCacheLimit)
                GPU.set(memoryLimit: originalMemoryLimit, relaxed: false)
                logger.info("💾 Restored memory limits - Cache: \(originalCacheLimit / 1024 / 1024)MB, Total: \(originalMemoryLimit / 1024 / 1024)MB")
                #endif

                logger.info("✅ Model loaded successfully from bundle")
                return

            } catch {
                logger.error("❌ Failed to load bundled model: \(error.localizedDescription)")

                #if !targetEnvironment(simulator)
                // Restore original memory limits before falling through to download
                GPU.set(cacheLimit: originalCacheLimit)
                GPU.set(memoryLimit: originalMemoryLimit, relaxed: false)
                logger.info("💾 Restored memory limits after bundle error")
                #endif

                // Fall through to download from HuggingFace
            }
        }

        // If not bundled or bundle load failed, try downloading from HuggingFace
        logger.info("📥 Model not in bundle, attempting download from HuggingFace")

        var lastError: Error?
        var attempt = 0

        while attempt < maxRetries {
            attempt += 1

            if attempt > 1 {
                logger.warning("🔄 Retry attempt \(attempt) of \(maxRetries)")
            }

            downloadState = .downloading(progress: 0.0)

            do {
                let configuration = ModelConfiguration(id: self.selectedModel.huggingFaceID)

                logger.info("⬇️ Downloading and loading \(self.selectedModel.displayName) (attempt \(attempt)/\(maxRetries))...")

                // Load the model with progress tracking
                modelContainer = try await LLMModelFactory.shared.loadContainer(
                    configuration: configuration
                ) { progress in
                    Task { @MainActor in
                        let progressValue = progress.fractionCompleted
                        self.downloadState = .downloading(progress: progressValue)
                        progressHandler(progressValue)

                        if progressValue.truncatingRemainder(dividingBy: 0.1) < 0.01 {
                            self.logger.info("📥 Download progress: \(Int(progressValue * 100))%")
                        }
                    }
                }

                downloadState = .downloaded

                #if !targetEnvironment(simulator)
                // Restore original memory limits after successful download
                GPU.set(cacheLimit: originalCacheLimit)
                GPU.set(memoryLimit: originalMemoryLimit, relaxed: false)
                logger.info("💾 Restored memory limits - Cache: \(originalCacheLimit / 1024 / 1024)MB, Total: \(originalMemoryLimit / 1024 / 1024)MB")
                #endif

                logger.info("✅ Model loaded successfully on attempt \(attempt)")
                return

            } catch {
                lastError = error
                downloadState = .failed(error: error.localizedDescription)
                logger.error("❌ Failed to load model (attempt \(attempt)): \(error.localizedDescription)")

                // Check error type for better handling
                let errorString = error.localizedDescription.lowercased()

                // Don't retry on certain errors (disk space, cancelled by user)
                if errorString.contains("cancelled") || errorString.contains("disk") || errorString.contains("space") {
                    logger.error("❌ Non-retryable error detected, aborting")

                    #if !targetEnvironment(simulator)
                    // Restore original memory limits before throwing
                    GPU.set(cacheLimit: originalCacheLimit)
                    GPU.set(memoryLimit: originalMemoryLimit, relaxed: false)
                    logger.info("💾 Restored memory limits after non-retryable error")
                    #endif

                    throw error
                }

                // Network errors that should retry
                let isNetworkError = errorString.contains("network") ||
                                    errorString.contains("timeout") ||
                                    errorString.contains("connection") ||
                                    errorString.contains("unreachable") ||
                                    errorString.contains("timed out")

                if isNetworkError {
                    logger.warning("⚠️ Network error detected, will retry with longer delay")
                }

                if attempt < maxRetries {
                    // Exponential backoff with longer delays for network errors
                    let baseDelay = pow(2.0, Double(attempt))
                    let delay = isNetworkError ? min(baseDelay * 2.0, 60.0) : min(baseDelay, 30.0)
                    logger.info("⏳ Waiting \(Int(delay)) seconds before retry...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    logger.error("❌ All \(maxRetries) retry attempts exhausted")

                    // Provide helpful error message
                    if isNetworkError {
                        logger.error("💡 Tip: Check your internet connection or try using WiFi instead of cellular")
                    }
                }
            }
        }

        // If we get here, all retries failed
        #if !targetEnvironment(simulator)
        // Restore original memory limits before throwing final error
        GPU.set(cacheLimit: originalCacheLimit)
        GPU.set(memoryLimit: originalMemoryLimit, relaxed: false)
        logger.error("💾 Restored memory limits after all retries exhausted")
        #endif

        let errorMessage: String
        if let lastError = lastError {
            let errorStr = lastError.localizedDescription.lowercased()
            if errorStr.contains("network") || errorStr.contains("timeout") || errorStr.contains("connection") {
                errorMessage = "Failed to download model after \(maxRetries) attempts due to network issues. Please check your internet connection and try again. Tip: Try using WiFi or switch to a smaller model like Qwen2.5 (0.5B) which is only 150MB."
            } else {
                errorMessage = "Failed to load model after \(maxRetries) attempts: \(lastError.localizedDescription)"
            }
        } else {
            errorMessage = "Failed to load model after \(maxRetries) attempts"
        }

        throw NSError(
            domain: "MLXSummarizationManager",
            code: 10,
            userInfo: [
                NSLocalizedDescriptionKey: errorMessage,
                NSLocalizedFailureReasonErrorKey: lastError?.localizedDescription ?? "Unknown error"
            ]
        )
    }

    /// Streaming callback type for progressive text generation
    /// Parameters: (partialText, metrics)
    typealias StreamingCallback = @MainActor (_ partialText: String, _ metrics: GenerationMetrics) -> Void

    /// Summarize with streaming updates (progressive generation)
    /// - Parameters:
    ///   - text: The transcription text to summarize
    ///   - onStream: Callback for streaming updates with partial text and metrics
    /// - Returns: Final summary text
    func summarizeStreaming(_ text: String, onStream: @escaping StreamingCallback) async throws -> String {
        logger.info("🚀 MLX streaming summarization called with \(self.selectedModel.displayName), text length: \(text.count)")

        #if targetEnvironment(simulator)
        throw NSError(
            domain: "MLXSummarizationManager",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "MLX is not available on iOS Simulator."]
        )
        #else
        // Check device compatibility
        guard DeviceCapabilities.supportsMLX else {
            let errorMsg = DeviceCapabilities.mlxUnsupportedReason
            logger.error("❌ \(errorMsg)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 20,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMsg,
                    NSLocalizedFailureReasonErrorKey: "Device: \(DeviceCapabilities.deviceModelName)"
                ]
            )
        }

        guard !text.isEmpty else {
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot summarize empty text"]
            )
        }

        // Ensure model is loaded
        if modelContainer == nil {
            logger.info("⏳ Model not loaded, loading now...")
            try await loadModel { _ in }
        }

        guard let container = modelContainer else {
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load model"]
            )
        }

        // Get custom parameters if available
        let customParams = parametersManager.getParameters(for: self.selectedModel)
        let prompt = self.selectedModel.formatPrompt(text: text, customTemplate: customParams.prompt)

        let generateParameters = GenerateParameters(
            maxTokens: customParams.maxTokens,
            temperature: customParams.temperature,
            topP: customParams.topP
        )

        let input = UserInput(prompt: prompt)
        let stopSequences = self.selectedModel.stopSequences

        // Track timing metrics - use actor-isolated state
        let modelName = self.selectedModel.displayName
        let startTime = Date()

        do {
            // Track the last metrics locally in the generation closure
            let result = try await container.perform { [input, stopSequences, startTime, modelName] context in
                let input = try await context.processor.prepare(input: input)

                // Local tracking state (non-isolated)
                var firstTokenTime: Date?
                var lastUpdateTime = Date()
                var lastTokenCount = 0
                var lastMetrics: GenerationMetrics?

                let generationResult = try MLXLMCommon.generate(
                    input: input,
                    parameters: generateParameters,
                    context: context
                ) { tokens in
                    // Check for cancellation first
                    if Task.isCancelled {
                        return .stop
                    }

                    let now = Date()
                    let tokenCount = tokens.count

                    // Build metrics locally
                    var metrics = GenerationMetrics.initial(modelName: modelName)

                    // Track first token
                    if firstTokenTime == nil && tokenCount > 0 {
                        firstTokenTime = now
                        metrics.timeToFirstToken = now.timeIntervalSince(startTime)
                    } else if let ttft = firstTokenTime {
                        metrics.timeToFirstToken = ttft.timeIntervalSince(startTime)
                    }

                    // Update metrics
                    metrics.totalTokens = tokenCount
                    metrics.totalGenerationTime = now.timeIntervalSince(startTime)

                    // Calculate average TPS
                    if metrics.totalGenerationTime > 0 {
                        metrics.averageTokensPerSecond = Float(tokenCount) / Float(metrics.totalGenerationTime)
                    }

                    // Calculate instantaneous TPS (since last update)
                    let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
                    let tokensSinceLastUpdate = tokenCount - lastTokenCount
                    if timeSinceLastUpdate > 0 {
                        metrics.tokensPerSecond = Float(tokensSinceLastUpdate) / Float(timeSinceLastUpdate)
                        if metrics.tokensPerSecond > metrics.peakTokensPerSecond {
                            metrics.peakTokensPerSecond = metrics.tokensPerSecond
                        }
                    }

                    // Calculate average latency
                    if tokenCount > 0 {
                        metrics.averageTokenLatency = metrics.totalGenerationTime / Double(tokenCount)
                    }

                    // Estimate remaining
                    if let maxTokens = generateParameters.maxTokens {
                        metrics.estimatedTokensRemaining = maxTokens - tokenCount
                        if metrics.averageTokensPerSecond > 0 {
                            let remainingTokens = Float(maxTokens - tokenCount)
                            metrics.estimatedTimeRemaining = TimeInterval(remainingTokens / metrics.averageTokensPerSecond)
                        }
                    }

                    // Save last metrics
                    lastMetrics = metrics

                    // Decode current text
                    let generatedText = context.tokenizer.decode(tokens: tokens)

                    // Stream update to caller
                    Task { @MainActor [metrics] in
                        onStream(generatedText, metrics)
                    }

                    lastUpdateTime = now
                    lastTokenCount = tokenCount

                    // Check stop conditions
                    if let maxTokens = generateParameters.maxTokens, tokenCount >= maxTokens {
                        return .stop
                    }

                    for stopSeq in stopSequences {
                        if generatedText.contains(stopSeq) {
                            return .stop
                        }
                    }

                    return .more
                }

                // Return both generation result and last metrics
                return (generationResult, lastMetrics)
            }

            // Extract generation result and last metrics
            let (generationResult, lastMetrics) = result

            // Final cleanup
            var summary = generationResult.output
            for stopSeq in stopSequences {
                if let range = summary.range(of: stopSeq) {
                    summary = String(summary[..<range.lowerBound])
                }
            }
            summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

            // Final metrics update - preserve accumulated metrics from last stream
            var finalMetrics = lastMetrics ?? GenerationMetrics.initial(modelName: modelName)
            finalMetrics.isComplete = true
            finalMetrics.totalGenerationTime = Date().timeIntervalSince(startTime)

            // Update final generation time for accurate average TPS calculation
            if finalMetrics.totalTokens > 0 && finalMetrics.totalGenerationTime > 0 {
                finalMetrics.averageTokensPerSecond = Float(finalMetrics.totalTokens) / Float(finalMetrics.totalGenerationTime)
            }

            Task { @MainActor in
                onStream(summary, finalMetrics)
            }

            logger.info("✅ Streaming summary complete - \(summary.count) chars in \(String(format: "%.2fs", finalMetrics.totalGenerationTime))")

            GPU.clearCache()
            return summary

        } catch {
            GPU.clearCache()
            logger.error("❌ Failed to generate streaming summary: \(error.localizedDescription)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate summary with \(self.selectedModel.displayName)",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        #endif
    }

    /// Summarize the given transcription text using selected MLX model (non-streaming)
    /// - Parameter text: The transcription text to summarize
    /// - Returns: Natural language summary text
    func summarize(_ text: String) async throws -> String {
        logger.info("🚀 MLX summarization called with \(self.selectedModel.displayName), text length: \(text.count)")

        #if targetEnvironment(simulator)
        // Not available on simulator
        logger.error("❌ MLX not available on simulator (requires Metal GPU)")
        throw NSError(
            domain: "MLXSummarizationManager",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "MLX is not available on iOS Simulator. Please use a real device to test MLX functionality."]
        )
        #else
        // Check device compatibility
        guard DeviceCapabilities.supportsMLX else {
            let errorMsg = DeviceCapabilities.mlxUnsupportedReason
            logger.error("❌ \(errorMsg)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 20,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMsg,
                    NSLocalizedFailureReasonErrorKey: "Device: \(DeviceCapabilities.deviceModelName)"
                ]
            )
        }

        // Log memory before inference
        let memoryBefore = GPU.snapshot()
        logger.info("💾 Memory before inference - Active: \(memoryBefore.activeMemory / 1024 / 1024)MB, Cache: \(memoryBefore.cacheMemory / 1024 / 1024)MB")

        guard !text.isEmpty else {
            logger.error("❌ Cannot summarize empty text")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot summarize empty text"]
            )
        }

        // Ensure model is loaded
        if modelContainer == nil {
            logger.info("⏳ Model not loaded, loading now...")
            try await loadModel { _ in }
        }

        guard let container = modelContainer else {
            logger.error("❌ Model container is nil after loading attempt")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load model"]
            )
        }

        // Get custom parameters if available
        let customParams = parametersManager.getParameters(for: self.selectedModel)
        let prompt = self.selectedModel.formatPrompt(text: text, customTemplate: customParams.prompt)

        logger.info("📝 Sending summarization prompt to \(self.selectedModel.displayName)")

        do {
            // Use custom generation parameters
            let generateParameters = GenerateParameters(
                maxTokens: customParams.maxTokens,
                temperature: customParams.temperature,
                topP: customParams.topP
            )

            let input = UserInput(prompt: prompt)
            let stopSequences = self.selectedModel.stopSequences

            // Run inference
            let result = try await container.perform { [input, stopSequences] context in
                let input = try await context.processor.prepare(input: input)

                return try MLXLMCommon.generate(
                    input: input,
                    parameters: generateParameters,
                    context: context
                ) { tokens in
                    // Stop if we've generated enough tokens
                    if let maxTokens = generateParameters.maxTokens, tokens.count >= maxTokens {
                        return .stop
                    }

                    // Check for stop sequences in generated text
                    let generatedText = context.tokenizer.decode(tokens: tokens)
                    for stopSeq in stopSequences {
                        if generatedText.contains(stopSeq) {
                            return .stop
                        }
                    }

                    return .more
                }
            }

            // Clean up output by removing stop sequences
            var summary = result.output
            for stopSeq in stopSequences {
                if let range = summary.range(of: stopSeq) {
                    summary = String(summary[..<range.lowerBound])
                }
            }
            summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("✅ Summary generated, length: \(summary.count)")
            logger.info("📋 Summary: \(summary)")

            // CRITICAL: Clear GPU cache after inference to free memory
            GPU.clearCache()

            // Log memory after cleanup
            let memoryAfter = GPU.snapshot()
            logger.info("💾 Memory after cleanup - Active: \(memoryAfter.activeMemory / 1024 / 1024)MB, Cache: \(memoryAfter.cacheMemory / 1024 / 1024)MB")

            let delta = memoryBefore.delta(memoryAfter)
            logger.info("📊 Memory delta - Active: \(delta.activeMemory / 1024 / 1024)MB, Cache: \(delta.cacheMemory / 1024 / 1024)MB")

            return summary

        } catch {
            // Clear cache even on error to prevent memory leaks
            GPU.clearCache()

            logger.error("❌ Failed to generate summary: \(error.localizedDescription)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate summary with \(self.selectedModel.displayName)",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        #endif
    }

    /// Send direct prompt with streaming updates (progressive generation)
    /// - Parameters:
    ///   - text: The prompt text to send
    ///   - onStream: Callback for streaming updates with partial text and metrics
    /// - Returns: Final response text
    func sendDirectPromptStreaming(_ text: String, onStream: @escaping StreamingCallback) async throws -> String {
        logger.info("📨 MLX streaming direct prompt called with \(self.selectedModel.displayName), text length: \(text.count)")

        #if targetEnvironment(simulator)
        throw NSError(
            domain: "MLXSummarizationManager",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "MLX is not available on iOS Simulator."]
        )
        #else
        guard DeviceCapabilities.supportsMLX else {
            let errorMsg = DeviceCapabilities.mlxUnsupportedReason
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 20,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMsg,
                    NSLocalizedFailureReasonErrorKey: "Device: \(DeviceCapabilities.deviceModelName)"
                ]
            )
        }

        guard !text.isEmpty else {
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot send empty prompt"]
            )
        }

        if modelContainer == nil {
            try await loadModel { _ in }
        }

        guard let container = modelContainer else {
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load model"]
            )
        }

        let prompt = text
        let params = self.selectedModel.generationParams
        let generateParameters = GenerateParameters(
            maxTokens: params.maxTokens,
            temperature: params.temperature,
            topP: params.topP
        )

        let input = UserInput(prompt: prompt)
        let stopSequences = self.selectedModel.stopSequences

        let modelName = self.selectedModel.displayName
        let startTime = Date()

        do {
            // Track the last metrics locally in the generation closure
            let result = try await container.perform { [input, stopSequences, startTime, modelName] context in
                let input = try await context.processor.prepare(input: input)

                // Local tracking state (non-isolated)
                var firstTokenTime: Date?
                var lastUpdateTime = Date()
                var lastTokenCount = 0
                var lastMetrics: GenerationMetrics?

                let generationResult = try MLXLMCommon.generate(
                    input: input,
                    parameters: generateParameters,
                    context: context
                ) { tokens in
                    // Check for cancellation first
                    if Task.isCancelled {
                        return .stop
                    }

                    let now = Date()
                    let tokenCount = tokens.count

                    // Build metrics locally
                    var metrics = GenerationMetrics.initial(modelName: modelName)

                    if firstTokenTime == nil && tokenCount > 0 {
                        firstTokenTime = now
                        metrics.timeToFirstToken = now.timeIntervalSince(startTime)
                    } else if let ttft = firstTokenTime {
                        metrics.timeToFirstToken = ttft.timeIntervalSince(startTime)
                    }

                    metrics.totalTokens = tokenCount
                    metrics.totalGenerationTime = now.timeIntervalSince(startTime)

                    if metrics.totalGenerationTime > 0 {
                        metrics.averageTokensPerSecond = Float(tokenCount) / Float(metrics.totalGenerationTime)
                    }

                    let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
                    let tokensSinceLastUpdate = tokenCount - lastTokenCount
                    if timeSinceLastUpdate > 0 {
                        metrics.tokensPerSecond = Float(tokensSinceLastUpdate) / Float(timeSinceLastUpdate)
                        if metrics.tokensPerSecond > metrics.peakTokensPerSecond {
                            metrics.peakTokensPerSecond = metrics.tokensPerSecond
                        }
                    }

                    if tokenCount > 0 {
                        metrics.averageTokenLatency = metrics.totalGenerationTime / Double(tokenCount)
                    }

                    if let maxTokens = generateParameters.maxTokens {
                        metrics.estimatedTokensRemaining = maxTokens - tokenCount
                        if metrics.averageTokensPerSecond > 0 {
                            let remainingTokens = Float(maxTokens - tokenCount)
                            metrics.estimatedTimeRemaining = TimeInterval(remainingTokens / metrics.averageTokensPerSecond)
                        }
                    }

                    // Save last metrics
                    lastMetrics = metrics

                    let generatedText = context.tokenizer.decode(tokens: tokens)

                    Task { @MainActor [metrics] in
                        onStream(generatedText, metrics)
                    }

                    lastUpdateTime = now
                    lastTokenCount = tokenCount

                    if let maxTokens = generateParameters.maxTokens, tokenCount >= maxTokens {
                        return .stop
                    }

                    for stopSeq in stopSequences {
                        if generatedText.contains(stopSeq) {
                            return .stop
                        }
                    }

                    return .more
                }

                // Return both generation result and last metrics
                return (generationResult, lastMetrics)
            }

            // Extract generation result and last metrics
            let (generationResult, lastMetrics) = result

            var response = generationResult.output
            for stopSeq in stopSequences {
                if let range = response.range(of: stopSeq) {
                    response = String(response[..<range.lowerBound])
                }
            }
            response = response.trimmingCharacters(in: .whitespacesAndNewlines)

            // Final metrics update - preserve accumulated metrics from last stream
            var finalMetrics = lastMetrics ?? GenerationMetrics.initial(modelName: modelName)
            finalMetrics.isComplete = true
            finalMetrics.totalGenerationTime = Date().timeIntervalSince(startTime)

            // Update final generation time for accurate average TPS calculation
            if finalMetrics.totalTokens > 0 && finalMetrics.totalGenerationTime > 0 {
                finalMetrics.averageTokensPerSecond = Float(finalMetrics.totalTokens) / Float(finalMetrics.totalGenerationTime)
            }

            Task { @MainActor in
                onStream(response, finalMetrics)
            }

            logger.info("✅ Streaming response complete - \(response.count) chars in \(String(format: "%.2fs", finalMetrics.totalGenerationTime))")

            GPU.clearCache()
            return response

        } catch {
            GPU.clearCache()
            logger.error("❌ Failed to generate streaming response: \(error.localizedDescription)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate response with \(self.selectedModel.displayName)",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        #endif
    }

    /// Send text as a direct prompt to the model (no summarization system prompt, non-streaming)
    /// - Parameter text: The prompt text to send
    /// - Returns: Natural language response text
    func sendDirectPrompt(_ text: String) async throws -> String {
        logger.info("📨 MLX direct prompt called with \(self.selectedModel.displayName), text length: \(text.count)")

        #if targetEnvironment(simulator)
        // Not available on simulator
        logger.error("❌ MLX not available on simulator (requires Metal GPU)")
        throw NSError(
            domain: "MLXSummarizationManager",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "MLX is not available on iOS Simulator. Please use a real device to test MLX functionality."]
        )
        #else
        // Check device compatibility
        guard DeviceCapabilities.supportsMLX else {
            let errorMsg = DeviceCapabilities.mlxUnsupportedReason
            logger.error("❌ \(errorMsg)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 20,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMsg,
                    NSLocalizedFailureReasonErrorKey: "Device: \(DeviceCapabilities.deviceModelName)"
                ]
            )
        }

        // Log memory before inference
        let memoryBefore = GPU.snapshot()
        logger.info("💾 Memory before inference - Active: \(memoryBefore.activeMemory / 1024 / 1024)MB, Cache: \(memoryBefore.cacheMemory / 1024 / 1024)MB")

        guard !text.isEmpty else {
            logger.error("❌ Cannot send empty prompt")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot send empty prompt"]
            )
        }

        // Ensure model is loaded
        if modelContainer == nil {
            logger.info("⏳ Model not loaded, loading now...")
            try await loadModel { _ in }
        }

        guard let container = modelContainer else {
            logger.error("❌ Model container is nil after loading attempt")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load model"]
            )
        }

        // Send text directly as prompt (no summarization template)
        let prompt = text

        logger.info("📝 Sending direct prompt to \(self.selectedModel.displayName)")

        do {
            // Prepare generation parameters optimized for selected model
            let params = self.selectedModel.generationParams
            let generateParameters = GenerateParameters(
                maxTokens: params.maxTokens,
                temperature: params.temperature,
                topP: params.topP
            )

            let input = UserInput(prompt: prompt)
            let stopSequences = self.selectedModel.stopSequences

            // Run inference
            let result = try await container.perform { [input, stopSequences] context in
                let input = try await context.processor.prepare(input: input)

                return try MLXLMCommon.generate(
                    input: input,
                    parameters: generateParameters,
                    context: context
                ) { tokens in
                    // Stop if we've generated enough tokens
                    if let maxTokens = generateParameters.maxTokens, tokens.count >= maxTokens {
                        return .stop
                    }

                    // Check for stop sequences in generated text
                    let generatedText = context.tokenizer.decode(tokens: tokens)
                    for stopSeq in stopSequences {
                        if generatedText.contains(stopSeq) {
                            return .stop
                        }
                    }

                    return .more
                }
            }

            // Clean up output by removing stop sequences
            var response = result.output
            for stopSeq in stopSequences {
                if let range = response.range(of: stopSeq) {
                    response = String(response[..<range.lowerBound])
                }
            }
            response = response.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("✅ Response generated, length: \(response.count)")
            logger.info("📋 Response: \(response)")

            // CRITICAL: Clear GPU cache after inference to free memory
            GPU.clearCache()

            // Log memory after cleanup
            let memoryAfter = GPU.snapshot()
            logger.info("💾 Memory after cleanup - Active: \(memoryAfter.activeMemory / 1024 / 1024)MB, Cache: \(memoryAfter.cacheMemory / 1024 / 1024)MB")

            let delta = memoryBefore.delta(memoryAfter)
            logger.info("📊 Memory delta - Active: \(delta.activeMemory / 1024 / 1024)MB, Cache: \(delta.cacheMemory / 1024 / 1024)MB")

            return response

        } catch {
            // Clear cache even on error to prevent memory leaks
            GPU.clearCache()

            logger.error("❌ Failed to generate response: \(error.localizedDescription)")
            throw NSError(
                domain: "MLXSummarizationManager",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate response with \(self.selectedModel.displayName)",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        #endif
    }

    /// Switch to a different model
    /// - Parameter model: The new model to use
    /// - Note: This will unload the current model and require loading the new one
    func switchModel(_ model: MLXModel) {
        logger.info("🔄 Switching model from \(self.selectedModel.displayName) to \(model.displayName)")

        // Unload current model
        if modelContainer != nil {
            unloadModel()
        }

        // Update selected model
        selectedModel = model

        #if !targetEnvironment(simulator)
        // Update memory limits for new model
        GPU.set(cacheLimit: model.cacheLimitBytes)
        GPU.set(memoryLimit: model.memoryLimitBytes, relaxed: false)

        logger.info("💾 Memory limits updated - Cache: \(model.cacheLimitBytes / 1024 / 1024)MB, Total: \(model.memoryLimitBytes / 1024 / 1024)MB")
        logger.info("📦 New model: \(model.displayName) (\(model.parameters)M params, ~\(model.sizeInMB)MB)")
        #endif

        logger.info("✅ Model switched successfully. Will load on next inference.")
    }

    /// Unload the model to free memory
    func unloadModel() {
        logger.info("🧹 Unloading model")

        #if !targetEnvironment(simulator)
        let memoryBefore = GPU.snapshot()
        logger.info("💾 Memory before unload - Active: \(memoryBefore.activeMemory / 1024 / 1024)MB, Cache: \(memoryBefore.cacheMemory / 1024 / 1024)MB")
        #endif

        // Release model container
        modelContainer = nil

        #if !targetEnvironment(simulator)
        // Aggressively clear all GPU caches
        GPU.clearCache()
        #endif

        // Reset download state (model stays cached on disk)
        downloadState = .downloaded  // Keep as downloaded, not notDownloaded

        #if !targetEnvironment(simulator)
        let memoryAfter = GPU.snapshot()
        logger.info("💾 Memory after unload - Active: \(memoryAfter.activeMemory / 1024 / 1024)MB, Cache: \(memoryAfter.cacheMemory / 1024 / 1024)MB")

        let freedMemory = memoryBefore.activeMemory - memoryAfter.activeMemory
        logger.info("✅ Model unloaded - Freed \(freedMemory / 1024 / 1024)MB")
        #endif
    }

    /// Handle memory warning - free as much memory as possible
    func handleMemoryWarning() {
        logger.warning("⚠️ Memory warning received - emergency cleanup")

        #if !targetEnvironment(simulator)
        let memoryBefore = GPU.snapshot()
        logger.warning("💾 Memory before cleanup - Active: \(memoryBefore.activeMemory / 1024 / 1024)MB, Cache: \(memoryBefore.cacheMemory / 1024 / 1024)MB, Peak: \(memoryBefore.peakMemory / 1024 / 1024)MB")
        #endif

        // Unload everything
        modelContainer = nil

        #if !targetEnvironment(simulator)
        GPU.clearCache()

        // Reset peak memory counter
        GPU.resetPeakMemory()

        let memoryAfter = GPU.snapshot()
        logger.warning("💾 Memory after cleanup - Active: \(memoryAfter.activeMemory / 1024 / 1024)MB, Cache: \(memoryAfter.cacheMemory / 1024 / 1024)MB")

        let freed = memoryBefore.activeMemory + memoryBefore.cacheMemory - memoryAfter.activeMemory - memoryAfter.cacheMemory
        logger.warning("✅ Emergency cleanup complete - Freed ~\(freed / 1024 / 1024)MB")
        #endif
    }

    /// Reset and clear cached model (for debugging/testing)
    func resetModel() {
        logger.warning("🔄 Resetting model cache")

        // Unload model from memory
        unloadModel()

        // Clear download state
        downloadState = .notDownloaded

        logger.info("✅ Model reset complete - will need to re-download")
    }

    /// Get the directory where models are stored
    func getModelCacheDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Use app-specific directory: ~/Library/Application Support/dev.andrefrelicot.llmvoice/models/
        let modelDir = appSupport
            .appendingPathComponent("dev.andrefrelicot.llmvoice")
            .appendingPathComponent("models")
            .appendingPathComponent("huggingface")

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: modelDir.path) {
            try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        }

        return modelDir
    }

    /// Clear all cached model files
    func clearModelCache() throws {
        logger.warning("🗑️ Clearing model cache files")

        guard let cacheDir = getModelCacheDirectory() else {
            logger.error("❌ Could not find cache directory")
            throw NSError(domain: "MLXSummarizationManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cache directory not found"])
        }

        // Unload model first
        unloadModel()

        // Remove cache directory
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            do {
                try FileManager.default.removeItem(at: cacheDir)
                logger.info("✅ Model cache cleared: \(cacheDir.path)")
            } catch {
                logger.error("❌ Failed to remove cache: \(error.localizedDescription)")
                throw error
            }
        }

        // Reset state
        downloadState = .notDownloaded
    }
}
