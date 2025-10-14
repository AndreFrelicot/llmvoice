//
//  StreamingMetricsView.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-11
//

import SwiftUI

/// Real-time performance metrics overlay for streaming text generation
struct StreamingMetricsView: View {
    let metrics: GenerationMetrics
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.caption)
                        .foregroundStyle(.blue)

                    Text("Performance Metrics")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Current TPS (always visible)
                    Text("\(metrics.formattedTPS) tok/s")
                        .font(.caption.monospacedDigit())
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemBackground))

            // Expanded metrics
            if isExpanded {
                Divider()

                VStack(spacing: 8) {
                    // Row 1: Tokens & Time
                    HStack(spacing: 16) {
                        MetricItem(
                            icon: "number",
                            label: "Tokens",
                            value: "\(metrics.totalTokens)",
                            color: .blue
                        )

                        Divider()
                            .frame(height: 30)

                        MetricItem(
                            icon: "clock",
                            label: "Time",
                            value: metrics.formattedTotalTime,
                            color: .orange
                        )

                        Divider()
                            .frame(height: 30)

                        MetricItem(
                            icon: "bolt",
                            label: "TTFT",
                            value: metrics.timeToFirstToken != nil
                                ? String(format: "%.2fs", metrics.timeToFirstToken!)
                                : "...",
                            color: .green
                        )
                    }

                    Divider()

                    // Row 2: Performance metrics
                    HStack(spacing: 16) {
                        MetricItem(
                            icon: "speedometer",
                            label: "Avg TPS",
                            value: metrics.formattedAvgTPS,
                            color: .purple
                        )

                        Divider()
                            .frame(height: 30)

                        MetricItem(
                            icon: "waveform.path",
                            label: "Peak TPS",
                            value: String(format: "%.1f", metrics.peakTokensPerSecond),
                            color: .pink
                        )

                        Divider()
                            .frame(height: 30)

                        MetricItem(
                            icon: "timer",
                            label: "Latency",
                            value: metrics.formattedAvgLatency,
                            color: .cyan
                        )
                    }

                    // Progress bar (if not complete)
                    if !metrics.isComplete, let remaining = metrics.estimatedTokensRemaining,
                       remaining > 0 {
                        let maxTokens = metrics.totalTokens + remaining
                        VStack(spacing: 4) {
                            ProgressView(value: Double(metrics.totalTokens), total: Double(maxTokens))
                                .progressViewStyle(.linear)
                                .tint(.blue)

                            HStack {
                                Text("Progress: \(Int(Double(metrics.totalTokens) / Double(maxTokens) * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let eta = metrics.estimatedTimeRemaining {
                                    Text("ETA: \(String(format: "%.1fs", eta))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Model name
                    if !metrics.modelName.isEmpty {
                        HStack {
                            Image(systemName: "brain.filled.head.profile")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(metrics.modelName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

/// Individual metric item
struct MetricItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Streaming state
        StreamingMetricsView(metrics: GenerationMetrics(
            totalTokens: 145,
            tokensPerSecond: 23.5,
            averageTokensPerSecond: 21.2,
            timeToFirstToken: 0.42,
            totalGenerationTime: 6.85,
            averageTokenLatency: 0.047,
            peakTokensPerSecond: 28.3,
            estimatedTokensRemaining: 55,
            estimatedTimeRemaining: 2.6,
            isComplete: false,
            modelName: "Qwen2.5 (0.5B)"
        ))

        // Completed state
        StreamingMetricsView(metrics: GenerationMetrics(
            totalTokens: 200,
            tokensPerSecond: 0,
            averageTokensPerSecond: 22.1,
            timeToFirstToken: 0.38,
            totalGenerationTime: 9.05,
            averageTokenLatency: 0.045,
            peakTokensPerSecond: 29.7,
            isComplete: true,
            modelName: "Qwen2.5 (0.5B)"
        ))
    }
    .padding()
}
