//
//  ModelDownloadManager.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-10
//

import Foundation
import SwiftUI
import os.log

/// Download state for a specific model
enum ModelDownloadStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case error(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var progress: Double {
        if case .downloading(let progress) = self { return progress }
        return 0.0
    }
}

/// Manages downloads for multiple MLX models concurrently
@MainActor
@Observable
final class ModelDownloadManager {
    private let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "ModelDownloadManager")

    // Track download status for each model
    private(set) var downloadStates: [MLXModel: ModelDownloadStatus] = [:]

    // Active download tasks
    private var downloadTasks: [MLXModel: Task<Void, Never>] = [:]

    // UserDefaults key for tracking downloaded models
    private let downloadedModelsKey = "dev.andrefrelicot.llmvoice.downloadedModels"

    init() {
        // Initialize all models as not downloaded
        for model in MLXModel.allCases {
            downloadStates[model] = .notDownloaded
        }

        // Check which models are already downloaded
        checkDownloadedModels()
    }

    // MARK: - Persistent Storage

    /// Get set of model IDs that were successfully downloaded
    private func getDownloadedModelFlags() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: downloadedModelsKey) ?? []
        return Set(array)
    }

    /// Mark a model as downloaded in persistent storage
    private func setModelDownloaded(_ model: MLXModel) {
        var downloaded = getDownloadedModelFlags()
        downloaded.insert(model.rawValue)
        UserDefaults.standard.set(Array(downloaded), forKey: downloadedModelsKey)
        logger.info("💾 Saved download flag for \(model.displayName)")
    }

    /// Remove download flag for a model in persistent storage
    private func clearModelDownloaded(_ model: MLXModel) {
        var downloaded = getDownloadedModelFlags()
        downloaded.remove(model.rawValue)
        UserDefaults.standard.set(Array(downloaded), forKey: downloadedModelsKey)
        logger.info("💾 Cleared download flag for \(model.displayName)")
    }

    /// Check if model has a download flag set
    private func hasDownloadFlag(_ model: MLXModel) -> Bool {
        return getDownloadedModelFlags().contains(model.rawValue)
    }

    /// Check which models are already downloaded
    func checkDownloadedModels() {
        logger.info("🔍 ========== CHECKING MODEL DOWNLOAD STATUS ==========")

        // Log model directory for debugging
        if let modelDir = getModelDirectory() {
            logger.info("📂 Model directory: \(modelDir.path)")

            // Check if directory exists
            var isDirectory: ObjCBool = false
            let dirExists = FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDirectory)
            logger.info("📂 Directory exists: \(dirExists), is directory: \(isDirectory.boolValue)")

            // List what's actually in the directory
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path) {
                logger.info("📋 Directory contents (\(contents.count) items):")
                for item in contents {
                    logger.info("   - \(item)")
                }
            } else {
                logger.info("📋 Directory is empty or doesn't exist")
            }
        } else {
            logger.error("❌ Could not get model directory")
        }

        // Log persisted download flags
        let downloadedFlags = getDownloadedModelFlags()
        logger.info("💾 Persisted download flags: \(downloadedFlags)")

        // Check each model
        logger.info("🔍 Checking each model...")
        for model in MLXModel.allCases {
            logger.info("─────────────────────────────────────")
            logger.info("🔍 Checking model: \(model.displayName)")
            logger.info("   Raw value: \(model.rawValue)")
            logger.info("   HuggingFace ID: \(model.huggingFaceID)")
            logger.info("   Is on-device MLX: \(model.isOnDeviceMLX)")

            let filesExist = isModelDownloaded(model)
            let hasFlag = hasDownloadFlag(model)

            logger.info("   Files exist: \(filesExist)")
            logger.info("   Has flag: \(hasFlag)")

            // Model is considered downloaded if either:
            // 1. Files exist on disk (filesystem check)
            // 2. We have a persistent flag indicating it was downloaded
            // This handles cases where files might be temporarily unavailable
            let isDownloaded = filesExist || hasFlag

            if isDownloaded {
                downloadStates[model] = .downloaded
                logger.info("   ✅ Model \(model.displayName) is DOWNLOADED (files: \(filesExist), flag: \(hasFlag))")

                // If we have a flag but no files, the files may have been cleared externally
                if hasFlag && !filesExist {
                    logger.warning("   ⚠️ Model \(model.displayName) has download flag but files are missing")
                }
            } else {
                downloadStates[model] = .notDownloaded
                logger.info("   ⚠️ Model \(model.displayName) is NOT downloaded")
            }
        }

        logger.info("🔍 ========== FINISHED CHECKING MODEL STATUS ==========")
    }

    /// Check if a model is already downloaded
    private func isModelDownloaded(_ model: MLXModel) -> Bool {
        logger.info("      🔎 isModelDownloaded() called for: \(model.displayName)")

        // Check if model files exist in bundle or Application Support

        // First check if bundled (for NuExtract)
        if let bundledName = model.bundledFolderName {
            logger.info("      📦 Checking for bundled model: \(bundledName)")

            // Check bundle root (Xcode fileSystemSynchronizedGroups places files here)
            if let bundleURL = Bundle.main.resourceURL {
                let bundledModelPath = bundleURL.appendingPathComponent(bundledName)
                logger.info("      🔎 Checking bundle root: \(bundledModelPath.path)")
                if FileManager.default.fileExists(atPath: bundledModelPath.path) {
                    logger.info("      ✅ Found bundled model at: \(bundledModelPath.path)")
                    return true
                } else {
                    logger.info("      ❌ Not found at bundle root")
                }
            }

            // Also check traditional resource path
            if let bundlePath = Bundle.main.path(forResource: bundledName, ofType: nil) {
                logger.info("      🔎 Checking traditional resource path: \(bundlePath)")
                if FileManager.default.fileExists(atPath: bundlePath) {
                    logger.info("      ✅ Found bundled model at resource path: \(bundlePath)")
                    return true
                } else {
                    logger.info("      ❌ Not found at resource path")
                }
            }

            logger.info("      ❌ Bundled model not found")
        } else {
            logger.info("      ℹ️ Not a bundled model")
        }

        // Check Application Support directory
        // Models stored in: ~/Library/Application Support/dev.andrefrelicot.llmvoice/models/huggingface/models--{org}--{model}/
        guard let modelDir = getModelDirectory() else {
            logger.warning("      ⚠️ Could not get model directory")
            return false
        }

        logger.info("      📂 Model directory: \(modelDir.path)")
        logger.info("      🔎 Possible cache patterns: \(model.possibleCachePatterns)")

        // Check all possible patterns (handles case sensitivity)
        for (index, pattern) in model.possibleCachePatterns.enumerated() {
            let modelPath = modelDir.appendingPathComponent(pattern)
            logger.info("      🔎 [\(index + 1)/\(model.possibleCachePatterns.count)] Checking pattern: \(pattern)")
            logger.info("      🔎 Full path: \(modelPath.path)")

            // Check if model directory exists and contains required files
            var isDirectory: ObjCBool = false
            let dirExists = FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory)

            logger.info("      📁 Directory exists: \(dirExists), is directory: \(isDirectory.boolValue)")

            if dirExists && isDirectory.boolValue {
                logger.info("      📁 Directory confirmed at: \(modelPath.path)")

                // List contents of the directory
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelPath.path) {
                    logger.info("      📋 Directory contains \(contents.count) items:")
                    for item in contents.prefix(10) {  // Show first 10 items
                        logger.info("         - \(item)")
                    }
                    if contents.count > 10 {
                        logger.info("         ... and \(contents.count - 10) more items")
                    }
                }

                // Verify essential model files exist (config.json and model files)
                let configPath = modelPath.appendingPathComponent("config.json")
                let hasConfig = FileManager.default.fileExists(atPath: configPath.path)

                logger.info("      🔎 Checking for config.json at: \(configPath.path)")
                logger.info("      📄 config.json exists: \(hasConfig)")

                if hasConfig {
                    logger.info("      ✅ Model FOUND at: \(modelPath.path)")
                    return true
                } else {
                    logger.warning("      ⚠️ Model directory exists but missing config.json")
                }
            } else {
                logger.info("      ❌ Directory does not exist or is not a directory")
            }
        }

        logger.info("      ❌ Model \(model.displayName) NOT found after checking all patterns")
        return false
    }

    /// Download a model
    func downloadModel(_ model: MLXModel) {
        guard downloadStates[model] != .downloading(progress: 0) else {
            logger.warning("⚠️ Model \(model.displayName) is already downloading")
            return
        }

        logger.info("📥 Starting download for \(model.displayName)")
        logger.info("📥 HuggingFace ID: \(model.huggingFaceID)")

        // Log expected download location
        if let modelDir = getModelDirectory(), let firstPattern = model.possibleCachePatterns.first {
            let expectedPath = modelDir.appendingPathComponent(firstPattern)
            logger.info("📥 Expected download path: \(expectedPath.path)")
        }

        downloadStates[model] = .downloading(progress: 0.0)

        // Create download task
        let task = Task { @MainActor in
            do {
                // Create a temporary MLX manager for this model to trigger download
                let mlxManager = MLXSummarizationManager(model: model)

                // Load the model, which will download it if needed
                try await mlxManager.loadModel { [weak self] progress in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.downloadStates[model] = .downloading(progress: progress)

                        if progress.truncatingRemainder(dividingBy: 0.1) < 0.01 {
                            self.logger.info("📥 \(model.displayName): \(Int(progress * 100))%")
                        }
                    }
                }

                // Download complete
                logger.info("✅ \(model.displayName) downloaded successfully")

                // Log what's actually in the directory now
                if let modelDir = getModelDirectory() {
                    if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path) {
                        logger.info("📋 Directory contents after download (\(contents.count) items): \(contents)")
                    }

                    // Check each possible pattern
                    for pattern in model.possibleCachePatterns {
                        let modelPath = modelDir.appendingPathComponent(pattern)
                        if FileManager.default.fileExists(atPath: modelPath.path) {
                            logger.info("✅ Model found at: \(modelPath.path)")
                        } else {
                            logger.info("❌ Model NOT found at: \(modelPath.path)")
                        }
                    }
                }

                // Save persistent flag that model was successfully downloaded
                setModelDownloaded(model)

                downloadStates[model] = .downloaded
                downloadTasks[model] = nil

            } catch {
                logger.error("❌ Failed to download \(model.displayName): \(error.localizedDescription)")
                downloadStates[model] = .error(error.localizedDescription)
                downloadTasks[model] = nil
            }
        }

        downloadTasks[model] = task
    }

    /// Cancel a download
    func cancelDownload(_ model: MLXModel) {
        logger.info("🛑 Canceling download for \(model.displayName)")

        if let task = downloadTasks[model] {
            task.cancel()
            downloadTasks[model] = nil
            downloadStates[model] = .notDownloaded
        }
    }

    /// Delete a downloaded model
    func deleteModel(_ model: MLXModel) {
        logger.info("🗑️ ========== DELETING MODEL ==========")
        logger.info("🗑️ Model: \(model.displayName)")

        // Don't delete bundled models
        if model.bundledFolderName != nil {
            logger.warning("⚠️ Cannot delete bundled model \(model.displayName)")
            return
        }

        guard let modelDir = getModelDirectory() else {
            logger.error("❌ Could not get model directory")
            return
        }

        logger.info("🗑️ Model directory: \(modelDir.path)")
        logger.info("🗑️ Possible cache patterns: \(model.possibleCachePatterns)")

        // Find which pattern actually exists on disk
        var pathToDelete: URL?
        for pattern in model.possibleCachePatterns {
            let modelPath = modelDir.appendingPathComponent(pattern)
            logger.info("🗑️ Checking if exists: \(modelPath.path)")

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    logger.info("🗑️ ✅ Found directory to delete: \(modelPath.path)")
                    pathToDelete = modelPath
                    break
                } else {
                    logger.info("🗑️ ⚠️ Path exists but is not a directory: \(modelPath.path)")
                }
            } else {
                logger.info("🗑️ ❌ Path does not exist: \(modelPath.path)")
            }
        }

        guard let pathToDelete = pathToDelete else {
            logger.error("❌ Could not find model directory to delete for \(model.displayName)")
            logger.error("   Checked patterns: \(model.possibleCachePatterns)")

            // Clear the flag anyway since files don't exist
            clearModelDownloaded(model)
            downloadStates[model] = .notDownloaded
            return
        }

        logger.info("🗑️ Attempting to delete: \(pathToDelete.path)")

        do {
            try FileManager.default.removeItem(at: pathToDelete)
            logger.info("✅ Successfully deleted files for \(model.displayName)")

            // Clear the persistent download flag
            clearModelDownloaded(model)

            downloadStates[model] = .notDownloaded
            logger.info("✅ Deletion complete for \(model.displayName)")
        } catch {
            logger.error("❌ Failed to delete \(model.displayName): \(error.localizedDescription)")
            logger.error("   Attempted path: \(pathToDelete.path)")
            logger.error("   Error: \(error)")
        }

        logger.info("🗑️ ========== DELETION FINISHED ==========")
    }

    /// Get the directory where models are stored
    private func getModelDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Use app-specific directory: ~/Library/Application Support/dev.andrefrelicot.llmvoice/models/huggingface/
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

    /// Get status for a model
    func getStatus(_ model: MLXModel) -> ModelDownloadStatus {
        return downloadStates[model] ?? .notDownloaded
    }

    /// Clear all downloaded models (excluding bundled models)
    func clearAllModels() {
        logger.warning("🗑️ ========== CLEARING ALL MODELS ==========")

        guard let modelDir = getModelDirectory() else {
            logger.error("❌ Could not get model directory")
            return
        }

        var deletedCount = 0
        var failedCount = 0

        // Delete each downloaded model (except bundled ones)
        for model in MLXModel.allCases {
            logger.info("🗑️ Processing model: \(model.displayName)")

            // Skip bundled models
            if model.bundledFolderName != nil {
                logger.info("   ⏭️ Skipping bundled model")
                continue
            }

            // Only try to delete if model is downloaded
            guard case .downloaded = downloadStates[model] else {
                logger.info("   ⏭️ Model not downloaded, skipping")
                continue
            }

            // Find which pattern actually exists on disk
            var pathToDelete: URL?
            for pattern in model.possibleCachePatterns {
                let modelPath = modelDir.appendingPathComponent(pattern)

                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    pathToDelete = modelPath
                    break
                }
            }

            guard let pathToDelete = pathToDelete else {
                logger.warning("   ⚠️ Could not find model directory for \(model.displayName)")
                // Clear the flag anyway since files don't exist
                clearModelDownloaded(model)
                downloadStates[model] = .notDownloaded
                continue
            }

            logger.info("   🗑️ Deleting: \(pathToDelete.path)")

            do {
                try FileManager.default.removeItem(at: pathToDelete)
                clearModelDownloaded(model)
                downloadStates[model] = .notDownloaded
                deletedCount += 1
                logger.info("   ✅ Successfully deleted \(model.displayName)")
            } catch {
                failedCount += 1
                logger.error("   ❌ Failed to delete \(model.displayName): \(error.localizedDescription)")
            }
        }

        logger.info("🗑️ ========== CLEAR ALL COMPLETE ==========")
        logger.info("✅ Deleted: \(deletedCount) models")
        if failedCount > 0 {
            logger.error("❌ Failed: \(failedCount) models")
        }
    }
}
