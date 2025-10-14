//
//  VoiceTranscriptionApp.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import SwiftUI
import os.log

@main   
struct LLMVoiceApp: App {
    private let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "App")

    init() {
        logger.info("🚀 LLMVoice initializing")
        logger.info("📱 iOS Version: \(UIDevice.current.systemVersion)")
        logger.info("📦 Device Model: \(UIDevice.current.model)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    logger.info("✅ ContentView appeared")
                }
        }
    }
}
