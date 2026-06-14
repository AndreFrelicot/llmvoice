//
//  TranscriptionManager.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

@preconcurrency import AVFoundation
import Foundation
import Speech
import os.log

/// Manages speech-to-text transcription using SpeechAnalyzer and SpeechTranscriber
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class TranscriptionManager {
    private let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "TranscriptionManager")
    nonisolated private static let bufferLogger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "TranscriptionManager.Buffer")
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    nonisolated(unsafe) private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognitionTask: Task<Void, Never>?
    nonisolated(unsafe) private var analyzerFormat: AVAudioFormat?
    private let bufferConverter = BufferConverter()
    nonisolated(unsafe) private var bufferCount: Int = 0
    private var startTime: Date?
    private var firstResultTime: Date?
    nonisolated(unsafe) private var firstBufferLogged = false
    private var isStartingTranscription = false
    private var isTranscriptionActive = false

    init() {
        logger.info("📝 TranscriptionManager initialized")
    }

    /// Start real-time transcription
    /// - Parameters:
    ///   - locale: The locale/language to use for transcription
    ///   - onResult: Callback with transcribed text and whether it's final
    func startTranscription(locale: Locale, onResult: @escaping (String, Bool) -> Void) async throws {
        logger.info("🚀 startTranscription() called with locale: \(locale.identifier)")
        guard !isStartingTranscription && !isTranscriptionActive && analyzer == nil && inputBuilder == nil else {
            logger.warning("⚠️ Ignoring startTranscription because an analyzer is already active")
            throw NSError(
                domain: "TranscriptionManager",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "Speech transcription is already starting or active"]
            )
        }

        isStartingTranscription = true
        defer {
            if !isTranscriptionActive {
                resetTranscriptionResources()
                isStartingTranscription = false
            }
        }

        bufferCount = 0
        startTime = Date()
        firstResultTime = nil
        firstBufferLogged = false

        logger.info("🔐 Checking speech recognition authorization")
        // Check current authorization status
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        logger.info("📊 Current auth status: \(authStatus.rawValue)")

        if authStatus == .notDetermined {
            logger.info("⚠️ Authorization not determined, requesting...")
            let authorized = await requestAuthorization()
            guard authorized else {
                logger.error("❌ Speech recognition authorization denied")
                throw NSError(
                    domain: "TranscriptionManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Speech recognition authorization denied"]
                )
            }
            logger.info("✅ Speech recognition authorized")
        } else if authStatus != .authorized {
            logger.error("❌ Speech recognition not authorized: \(authStatus.rawValue)")
            throw NSError(
                domain: "TranscriptionManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized. Please enable in Settings."]
            )
        } else {
            logger.info("✅ Speech recognition already authorized")
        }

        logger.info("📝 Creating SpeechTranscriber with locale: \(locale.identifier)")

        // Check if device supports SpeechTranscriber at all
        let (isSupported, supportedLocales) = await DeviceCapabilities.checkSpeechTranscriberSupport()

        if !isSupported {
            logger.error("❌ SpeechTranscriber not supported on this device")
            logger.error("❌ Device: \(DeviceCapabilities.deviceModelName)")
            throw NSError(
                domain: "TranscriptionManager",
                code: 10,
                userInfo: [
                    NSLocalizedDescriptionKey: DeviceCapabilities.speechTranscriberUnsupportedReason,
                    NSLocalizedFailureReasonErrorKey: "Device: \(DeviceCapabilities.deviceModelName)"
                ]
            )
        }

        logger.info("✅ Supported locales: \(supportedLocales.map { $0.identifier }.joined(separator: ", "))")

        guard supportedLocales.contains(locale) else {
            logger.error("❌ Locale \(locale.identifier) not supported")
            logger.error("💡 Available locales: \(supportedLocales.map { $0.identifier }.joined(separator: ", "))")
            throw NSError(
                domain: "TranscriptionManager",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Locale \(locale.identifier) is not supported on this device",
                    NSLocalizedFailureReasonErrorKey: "Available locales: \(supportedLocales.map { $0.identifier }.joined(separator: ", "))"
                ]
            )
        }

        // Create transcriber optimized for progressive/live transcription
        transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        logger.info("✅ SpeechTranscriber created with progressive transcription preset")

        // Check if locale assets are installed
        let installedLocales = await SpeechTranscriber.installedLocales
        logger.info("📥 Installed locales: \(installedLocales.map { $0.identifier }.joined(separator: ", "))")

        if !installedLocales.contains(locale) {
            logger.warning("⚠️ Locale \(locale.identifier) not installed, downloading assets...")
            try await downloadAndReserveAssets(for: transcriber!)
        } else {
            logger.info("✅ Locale \(locale.identifier) already installed")
            // Still need to reserve it
            try await reserveAssets(for: transcriber!)
        }

        guard let transcriber = transcriber else {
            logger.error("❌ Transcriber is nil after creation")
            throw NSError(
                domain: "TranscriptionManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create transcriber"]
            )
        }

        logger.info("🔍 Creating SpeechAnalyzer")
        // Create analyzer with transcriber module
        analyzer = SpeechAnalyzer(modules: [transcriber])
        logger.info("✅ SpeechAnalyzer created")

        logger.info("🎵 Getting best available audio format")
        // Get best audio format, use fallback if none available
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        if analyzerFormat == nil {
            logger.warning("⚠️ No best audio format available, using fallback format")
            // Create a standard format: 16kHz, mono, PCM float
            analyzerFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )
        }

        logger.info("✅ Audio format: \(String(describing: self.analyzerFormat))")

        logger.info("📡 Creating input stream")
        // Create input stream
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder
        logger.info("✅ Input stream created")

        logger.info("👂 Starting recognition task")
        // Start listening to transcription results
        recognitionTask = Task {
            do {
                self.logger.info("🎧 Waiting for transcription results...")
                for try await result in transcriber.results {
                    // Measure time to first result
                    if self.firstResultTime == nil, let start = self.startTime {
                        self.firstResultTime = Date()
                        let latency = self.firstResultTime!.timeIntervalSince(start)
                        #if DEBUG
                        print("⏱️ TIME TO FIRST RESULT: \(String(format: "%.2f", latency)) seconds")
                        #endif
                        self.logger.info("⏱️ Time to first result: \(String(format: "%.2f", latency))s")
                    }

                    let text = String(result.text.characters)
                    self.logger.debug("📝 Transcription result: \(text.prefix(50))... final: \(result.isFinal)")
                    await MainActor.run {
                        onResult(text, result.isFinal)
                    }
                }
                self.logger.info("✅ Transcription results stream completed")
            } catch {
                self.logger.error("❌ Transcription error: \(error.localizedDescription)")
            }
        }
        logger.info("✅ Recognition task started")

        logger.info("▶️ Starting analyzer with input sequence")
        // Start the analyzer
        do {
            try await analyzer?.start(inputSequence: inputSequence)
            isTranscriptionActive = true
            isStartingTranscription = false
            logger.info("✅ Analyzer started successfully")
        } catch {
            logger.error("❌ Failed to start analyzer: \(error.localizedDescription)")
            resetTranscriptionResources()
            isStartingTranscription = false
            isTranscriptionActive = false
            throw error
        }

        logger.info("✅ Transcription started successfully")
    }

    /// Process an audio buffer for transcription
    /// - Parameter buffer: The audio buffer to process
    nonisolated func processAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        bufferCount += 1

        // Log first buffer
        if !firstBufferLogged {
            firstBufferLogged = true
            #if DEBUG
            print("🎤 FIRST AUDIO BUFFER RECEIVED")
            #endif
            Self.bufferLogger.info("🎤 First audio buffer received at buffer #\(self.bufferCount)")
        }

        // Log every 100th buffer to avoid spam
        if bufferCount % 100 == 1 {
            Self.bufferLogger.debug("📦 Processing buffer #\(self.bufferCount): \(buffer.frameLength) frames")
        }

        // Access the continuation and format without MainActor isolation
        guard let builder = inputBuilder else {
            Self.bufferLogger.error("❌ Input builder is nil, buffer #\(self.bufferCount) dropped")
            return
        }

        guard let format = analyzerFormat else {
            Self.bufferLogger.error("❌ Analyzer format is nil, buffer #\(self.bufferCount) dropped")
            return
        }

        // Convert buffer to analyzer format if needed
        let convertedBuffer = try bufferConverter.convertBuffer(buffer, to: format)
        builder.yield(AnalyzerInput(buffer: convertedBuffer))

        if bufferCount % 100 == 1 {
            Self.bufferLogger.debug("✅ Buffer #\(self.bufferCount) yielded to analyzer")
        }
    }

    /// Stop transcription and clean up
    func stopTranscription() async {
        logger.info("🛑 ========== TranscriptionManager.stopTranscription() CALLED ==========")

        guard isStartingTranscription || isTranscriptionActive || analyzer != nil || inputBuilder != nil else {
            logger.warning("⚠️ stopTranscription ignored because no analyzer is active")
            return
        }

        isStartingTranscription = false
        isTranscriptionActive = false

        logger.info("📡 STEP 1: Finishing input stream...")
        inputBuilder?.finish()
        logger.info("✅ Input stream finished")

        logger.info("⏹️ STEP 2: Calling finalizeAndFinishThroughEndOfInput()...")
        logger.info("   • This should trigger final transcription callbacks")
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            logger.info("✅ finalizeAndFinishThroughEndOfInput() completed")
        } catch {
            logger.error("❌ finalizeAndFinishThroughEndOfInput() error: \(error.localizedDescription)")
        }

        // Give callbacks a moment to execute
        logger.info("⏳ Waiting 200ms for final callbacks to execute...")
        try? await Task.sleep(for: .milliseconds(200))
        logger.info("✅ Wait complete")

        logger.info("❌ STEP 3: Cancelling recognition task")
        recognitionTask?.cancel()
        logger.info("✅ Recognition task cancelled")

        logger.info("🧹 STEP 4: Cleaning up resources")
        resetTranscriptionResources()
        logger.info("✅ Resources cleaned up")

        logger.info("========== TranscriptionManager.stopTranscription() COMPLETE ==========")
    }

    /// Request speech recognition authorization (nonisolated to avoid queue assertion)
    nonisolated private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Download and reserve speech recognition assets for a transcriber
    private func downloadAndReserveAssets(for transcriber: SpeechTranscriber) async throws {
        logger.info("📦 Creating asset installation request for transcriber")

        // Create installation request
        let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])

        guard let installRequest = installRequest else {
            logger.info("ℹ️ No installation needed - assets may already be available")
            return
        }

        logger.info("⬇️ Starting asset download and installation...")
        // Download and install assets
        try await installRequest.downloadAndInstall()

        logger.info("✅ Assets downloaded and installed successfully")
    }

    /// Reserve speech recognition assets for a transcriber
    private func reserveAssets(for transcriber: SpeechTranscriber) async throws {
        logger.info("🔒 Reserving locale assets for transcriber")

        // Create installation request (which handles reservation for already-installed assets)
        let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])

        guard let installRequest = installRequest else {
            logger.info("ℹ️ No installation needed - assets already reserved")
            return
        }

        logger.info("📥 Ensuring assets are reserved...")
        // This will reserve the already-installed assets
        try await installRequest.downloadAndInstall()

        logger.info("✅ Assets reserved successfully")
    }

    private func resetTranscriptionResources() {
        inputBuilder?.finish()
        recognitionTask?.cancel()
        transcriber = nil
        analyzer = nil
        inputBuilder = nil
        recognitionTask = nil
        analyzerFormat = nil
    }
}

/// Helper class to convert audio buffers between formats
private final class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private let lock = NSLock()

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        lock.lock()
        defer { lock.unlock() }
        // If formats match, return original buffer
        if buffer.format == format {
            return buffer
        }

        // Create converter if needed or format changed
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }

        guard let converter = converter else {
            throw NSError(
                domain: "BufferConverter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]
            )
        }

        // Calculate output buffer size
        let outputFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: outputFrameCapacity
        ) else {
            throw NSError(
                domain: "BufferConverter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"]
            )
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            throw error
        }

        return outputBuffer
    }
}
