//
//  AudioManager.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

@preconcurrency import AVFoundation
import Foundation
import os.log

/// Manages audio recording from the microphone using AVAudioEngine
/// Thread-safe: Audio engine operations run on their own threads
final class AudioManager: @unchecked Sendable {
    private let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "AudioManager")
    private let audioEngine = AVAudioEngine()
    private let recordingQueue = DispatchQueue(label: "dev.andrefrelicot.llmvoice.audio", qos: .userInitiated)
    private var isRecording = false

    init() {
        logger.info("🎧 AudioManager initialized")
    }

    /// Start streaming audio from the microphone
    /// - Parameter onBuffer: Callback with audio buffers
    func startAudioStream(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        logger.info("🎤 startAudioStream() called")
        guard !isRecording else {
            logger.warning("⚠️ Already recording, skipping")
            return
        }

        logger.info("🔧 Configuring audio session")
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        logger.info("✅ Audio session category set")

        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        logger.info("✅ Audio session activated")

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logger.info("📊 Recording format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount) channels")

        logger.info("🔌 Installing tap on audio input")
        // Install tap on audio input
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingFormat
        ) { buffer, _ in
            onBuffer(buffer)
        }

        logger.info("⚙️ Preparing audio engine")
        audioEngine.prepare()

        logger.info("▶️ Starting audio engine")
        try audioEngine.start()

        isRecording = true
        logger.info("✅ Audio stream started successfully")
    }

    /// Stop audio streaming
    func stopAudioStream() {
        logger.info("🛑 stopAudioStream() called")
        guard isRecording else {
            logger.warning("⚠️ Not recording, skipping")
            return
        }

        logger.info("⏹️ Stopping audio engine")
        audioEngine.stop()

        logger.info("🔌 Removing tap from input node")
        audioEngine.inputNode.removeTap(onBus: 0)

        logger.info("📴 Deactivating audio session")
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            logger.info("✅ Audio session deactivated")
        } catch {
            logger.error("❌ Failed to deactivate audio session: \(error.localizedDescription)")
        }

        isRecording = false
        logger.info("✅ Audio stream stopped successfully")
    }

    deinit {
        // AudioEngine cleanup happens automatically
        // AVAudioEngine is thread-safe and handles its own cleanup
    }
}
