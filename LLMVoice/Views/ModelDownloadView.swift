//
//  ModelDownloadView.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import SwiftUI

struct ModelDownloadView: View {
    @Binding var isPresented: Bool
    let speechModelReady: Bool
    let llmModelReady: Bool
    let llmDownloadProgress: Double
    let selectedModel: MLXModel
    let onDownloadModels: () -> Void
    let onClearCache: (() -> Void)?

    @State private var showClearConfirmation = false
    @State private var clearError: String?
    @State private var downloadFailed = false

    private var allModelsReady: Bool {
        speechModelReady && llmModelReady
    }

    private var isDownloading: Bool {
        llmDownloadProgress > 0 && llmDownloadProgress < 1.0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: allModelsReady ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(allModelsReady ? .green : .blue)
                        .symbolEffect(.pulse, isActive: !allModelsReady && llmDownloadProgress == 0)

                    Text(allModelsReady ? "Setup Complete" : "Model Setup Required")
                        .font(.title2.bold())

                    if allModelsReady {
                        Text("All AI models are ready to use")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        VStack(spacing: 8) {
                            Text("Download AI models to enable voice transcription and intelligent summarization")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 16) {
                                Label("150-500 MB", systemImage: "internaldrive")
                                Label("WiFi recommended", systemImage: "wifi")
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 40)

                Spacer()

                // Model Status Cards
                VStack(spacing: 20) {
                    // Speech Recognition Model
                    ModelStatusCard(
                        title: "Speech Recognition",
                        subtitle: "Apple Speech Framework",
                        icon: "waveform",
                        iconColor: .blue,
                        isReady: speechModelReady,
                        progress: nil,
                        size: "Built-in",
                        description: nil
                    )

                    // LLM Model
                    ModelStatusCard(
                        title: "AI Language Model",
                        subtitle: selectedModel.displayName,
                        icon: "brain",
                        iconColor: .purple,
                        isReady: llmModelReady,
                        progress: llmDownloadProgress,
                        size: "\(selectedModel.sizeInMB) MB",
                        description: "Downloads once, cached permanently"
                    )
                }
                .padding(.horizontal)

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    if allModelsReady {
                        Button {
                            isPresented = false
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Continue to App")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        VStack(spacing: 12) {
                            Button {
                                downloadFailed = false
                                onDownloadModels()
                            } label: {
                                HStack {
                                    if isDownloading {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Downloading...")
                                            .fontWeight(.semibold)
                                    } else if downloadFailed {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry Download")
                                            .fontWeight(.semibold)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Download Models")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isDownloading ? Color.gray : (downloadFailed ? Color.orange : Color.blue))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isDownloading)

                            if isDownloading {
                                Text("This may take a few minutes on slower connections")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button("I'll Download Later") {
                                isPresented = false
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Clear cache button (only show if models are downloaded)
                    if llmModelReady, onClearCache != nil {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Model Cache")
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.red)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!allModelsReady)
        .alert("Clear Model Cache?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                onClearCache?()
            }
        } message: {
            Text("This will remove the downloaded model from your device. You'll need to download it again to use AI summarization. (150-500 MB depending on model)")
        }
        .alert("Error", isPresented: .constant(clearError != nil)) {
            Button("OK") {
                clearError = nil
            }
        } message: {
            if let error = clearError {
                Text(error)
            }
        }
    }
}

struct ModelStatusCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let isReady: Bool
    let progress: Double?
    let size: String
    let description: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(size)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if let description = description {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                // Status
                if isReady {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                } else if let progress = progress, progress > 0 {
                    VStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
            }
            .padding()

            // Progress Bar
            if let progress = progress, progress > 0, progress < 1.0 {
                VStack(spacing: 8) {
                    Divider()

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)

                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(iconColor)
                                .frame(width: geometry.size.width * progress, height: 8)
                                .animation(.linear, value: progress)
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

#Preview("Not Downloaded") {
    ModelDownloadView(
        isPresented: .constant(true),
        speechModelReady: true,
        llmModelReady: false,
        llmDownloadProgress: 0.0,
        selectedModel: .qwen25_05b,
        onDownloadModels: {},
        onClearCache: nil
    )
}

#Preview("Downloading") {
    ModelDownloadView(
        isPresented: .constant(true),
        speechModelReady: true,
        llmModelReady: false,
        llmDownloadProgress: 0.65,
        selectedModel: .gemma3_1b,
        onDownloadModels: {},
        onClearCache: nil
    )
}

#Preview("Ready") {
    ModelDownloadView(
        isPresented: .constant(true),
        speechModelReady: true,
        llmModelReady: true,
        llmDownloadProgress: 1.0,
        selectedModel: .llama32_1b,
        onDownloadModels: {},
        onClearCache: { print("Clear cache tapped") }
    )
}
