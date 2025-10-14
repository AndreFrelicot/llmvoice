//
//  GenerationMetrics.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-11
//

import Foundation

/// Real-time metrics for LLM text generation
struct GenerationMetrics: Codable, Equatable {
    /// Total number of tokens generated so far
    var totalTokens: Int = 0

    /// Current tokens per second (instantaneous rate)
    var tokensPerSecond: Float = 0.0

    /// Average tokens per second over entire generation
    var averageTokensPerSecond: Float = 0.0

    /// Time to first token (TTFT) in seconds
    var timeToFirstToken: TimeInterval?

    /// Total generation time so far in seconds
    var totalGenerationTime: TimeInterval = 0.0

    /// Average time between tokens in milliseconds
    var averageTokenLatency: TimeInterval = 0.0

    /// Peak (maximum) tokens per second observed
    var peakTokensPerSecond: Float = 0.0

    /// Estimated tokens remaining (if max tokens is set)
    var estimatedTokensRemaining: Int?

    /// Estimated time remaining in seconds
    var estimatedTimeRemaining: TimeInterval?

    /// Whether generation is complete
    var isComplete: Bool = false

    /// Model name being used
    var modelName: String = ""

    /// Create initial metrics
    static func initial(modelName: String) -> GenerationMetrics {
        GenerationMetrics(modelName: modelName)
    }

    /// Format TPS for display
    var formattedTPS: String {
        String(format: "%.1f", tokensPerSecond)
    }

    /// Format average TPS for display
    var formattedAvgTPS: String {
        String(format: "%.1f", averageTokensPerSecond)
    }

    /// Format TTFT for display
    var formattedTTFT: String {
        guard let ttft = timeToFirstToken else { return "N/A" }
        return String(format: "%.2fs", ttft)
    }

    /// Format total time for display
    var formattedTotalTime: String {
        String(format: "%.2fs", totalGenerationTime)
    }

    /// Format average latency for display
    var formattedAvgLatency: String {
        String(format: "%.1fms", averageTokenLatency * 1000)
    }
}

/// Streaming state for progressive text generation
struct StreamingState: Equatable {
    /// Current partial text (updates in real-time)
    var partialText: String = ""

    /// Current generation metrics
    var metrics: GenerationMetrics = .initial(modelName: "")

    /// Whether streaming is active
    var isStreaming: Bool = false

    /// Any error that occurred
    var error: String?

    /// Create initial state
    static func initial(modelName: String) -> StreamingState {
        StreamingState(
            partialText: "",
            metrics: .initial(modelName: modelName),
            isStreaming: false
        )
    }
}
