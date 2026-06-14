//
//  ModelPickerView.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-10
//

import SwiftUI
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct ModelPickerView: View {
    @Binding var selectedModel: MLXModel
    @State private var downloadManager = ModelDownloadManager()
    @StateObject private var parametersManager = ModelParametersManager()
    @Environment(\.dismiss) private var dismiss

    // Check Apple Intelligence availability
    private var appleIntelligenceAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    // Check MLX compatibility
    private var mlxSupported: Bool {
        DeviceCapabilities.supportsMLX
    }

    var body: some View {
        NavigationStack {
            List {
                // Show warning if MLX is not supported
                if !mlxSupported {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            // Header
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("MLX Not Supported")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            // Device info
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Device: \(DeviceCapabilities.deviceModelName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                    Text("Missing Metal features: air.simd_sum, rmsfloat16")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            // Explanation
                            Text(DeviceCapabilities.mlxUnsupportedReason)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("")
                    }
                }

                Section("Available Models") {
                    ForEach(MLXModel.allCases) { model in
                        ModelRow(
                            model: model,
                            isSelected: model == selectedModel,
                            downloadStatus: model.isOnDeviceMLX ? downloadManager.getStatus(model) : .downloaded,
                            isAvailable: model == .appleIntelligence ? appleIntelligenceAvailable : (model.isOnDeviceMLX ? mlxSupported : true),
                            parametersManager: parametersManager,
                            onSelect: {
                                if model == .appleIntelligence && !appleIntelligenceAvailable {
                                    return
                                }
                                if model.isOnDeviceMLX && !mlxSupported {
                                    return
                                }
                                selectedModel = model
                                dismiss()
                            },
                            onDownload: {
                                downloadManager.downloadModel(model)
                            },
                            onCancelDownload: {
                                downloadManager.cancelDownload(model)
                            },
                            onDelete: {
                                downloadManager.deleteModel(model)
                            }
                        )
                        .disabled((model == .appleIntelligence && !appleIntelligenceAvailable) || (model.isOnDeviceMLX && !mlxSupported))
                }
                }
            }
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Check download status when sheet appears
                downloadManager.checkDownloadedModels()
            }
        }
    }
}

struct ModelRow: View {
    let model: MLXModel
    let isSelected: Bool
    let downloadStatus: ModelDownloadStatus
    let isAvailable: Bool
    @ObservedObject var parametersManager: ModelParametersManager
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var editedPrompt: String = ""
    @State private var editedTemperature: Float = 0.7
    @State private var editedTopP: Float = 0.9
    @State private var editedMaxTokens: Int = 2000

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Parameter editors (only for MLX models)
            if model.isOnDeviceMLX {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()

                    // Prompt editor
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Prompt Template")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            if parametersManager.hasCustomParameters(for: model) {
                                Button {
                                    parametersManager.resetParameters(for: model)
                                    loadParameters()
                                } label: {
                                    Text("Reset")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        Text("Use {{text}} as placeholder for input")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ZStack(alignment: .bottomTrailing) {
                            TextEditor(text: $editedPrompt)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 120)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color(uiColor: .systemBackground))
                                .onChange(of: editedPrompt) { _, newValue in
                                    saveParameters()
                                }

                            // Keyboard dismiss button
                            Button {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(uiColor: .separator), lineWidth: 1)
                        )
                    }

                    // Temperature slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.2f", editedTemperature))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $editedTemperature, in: 0...2, step: 0.1)
                            .onChange(of: editedTemperature) { _, newValue in
                                saveParameters()
                            }

                        Text("Higher values = more creative, Lower values = more focused")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Top P slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top P")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.2f", editedTopP))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $editedTopP, in: 0...1, step: 0.05)
                            .onChange(of: editedTopP) { _, newValue in
                                saveParameters()
                            }

                        Text("Limits token selection to cumulative probability threshold")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Max tokens slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Tokens")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(editedMaxTokens) / \(model.maxTokenLimit)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: Binding(
                            get: { Float(editedMaxTokens) },
                            set: { editedMaxTokens = min(Int($0), model.maxTokenLimit) }
                        ), in: 50...Float(model.maxTokenLimit), step: 50)
                        .onChange(of: editedMaxTokens) { _, newValue in
                            saveParameters()
                        }

                        Text("Maximum length of generated response")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    onSelect()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        // Model icon
                        Image(systemName: model == .appleIntelligence ? "apple.logo" : "brain.filled.head.profile")
                            .font(.title2)
                            .foregroundStyle(isSelected ? .blue : (isAvailable ? .secondary : Color.gray.opacity(0.5)))
                            .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    // Model name
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isAvailable ? .primary : Color.gray.opacity(0.5))

                        if !isAvailable {
                            Text(model == .appleIntelligence ? "Unavailable" : "Unsupported")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }

                    // Description
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(isAvailable ? .secondary : Color.gray.opacity(0.5))
                        .lineLimit(2)

                    // Model specs (only for MLX models)
                    if model.isOnDeviceMLX {
                        HStack(spacing: 12) {
                            Label("\(model.sizeInMB)MB", systemImage: "arrow.down.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Label("\(model.parameters)M", systemImage: "cpu")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                        .font(.title3)
                }
                    }
                }
                .tint(.primary)

                // Download controls and progress (only for MLX models)
                if model.isOnDeviceMLX {
                HStack(spacing: 12) {
                    switch downloadStatus {
                    case .notDownloaded:
                    Button {
                        onDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            ProgressView(value: progress, total: 1.0)
                                .progressViewStyle(.linear)

                            Button {
                                onCancelDownload()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .downloaded:
                    HStack(spacing: 8) {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        if model.bundledFolderName == nil {
                            Button {
                                onDelete()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        } else {
                            Label("Bundled", systemImage: "app.badge.checkmark")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }

                    case .error(let message):
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Error", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)

                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button {
                                onDownload()
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            }
        }
        .onAppear {
            loadParameters()
        }
    }

    private func loadParameters() {
        let params = parametersManager.getParameters(for: model)
        editedPrompt = params.prompt
        editedTemperature = params.temperature
        editedTopP = params.topP
        editedMaxTokens = min(params.maxTokens, model.maxTokenLimit)
    }

    private func saveParameters() {
        let params = ModelParameters(
            prompt: editedPrompt,
            temperature: editedTemperature,
            topP: editedTopP,
            maxTokens: editedMaxTokens
        )
        parametersManager.saveParameters(params, for: model)
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        ModelPickerView(selectedModel: .constant(.qwen25_05b))
    }
}
