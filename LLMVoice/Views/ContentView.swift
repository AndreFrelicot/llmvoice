//
//  ContentView.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = RecordingViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLanguagePicker = false
    @State private var showModelPicker = false
    @State private var showModelDownload = false
    @State private var showSettings = false
    @State private var editableTranscription = ""
    @State private var speechTranscriberSupported: Bool?
    @State private var supportedLocales: [Locale] = []
    @State private var isButtonReduced = false
    @State private var isTranscriptionExpanded = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Speech transcription compatibility warning
                    if let supported = speechTranscriberSupported, !supported {
                        SpeechTranscriberUnsupportedBanner()
                    }

                    // MLX compatibility warning banner
                    if !DeviceCapabilities.supportsMLX {
                        MLXUnsupportedBanner()
                    }

                    // Model loading banner
                    if viewModel.isLoadingModel {
                        ModelLoadingBanner(
                            modelName: viewModel.selectedModel.displayName,
                            progress: viewModel.modelLoadProgress
                        )
                    }

                    // Transcription area
                    TranscriptionView(
                        finalizedText: viewModel.finalizedTranscription,
                        volatileText: viewModel.volatileTranscription,
                        editableText: $editableTranscription,
                        isRecording: viewModel.isRecording,
                        isLoadingModel: viewModel.isLoadingModel,
                        isResolving: viewModel.isResolvingTranscription,
                        isButtonReduced: isButtonReduced,
                        isExpanded: $isTranscriptionExpanded,
                        onSummarize: {
                            Task {
                                await viewModel.summarizeText(editableTranscription)
                            }
                        },
                        onSendPrompt: {
                            Task {
                                await viewModel.sendDirectPrompt(editableTranscription)
                            }
                        },
                        onToggleRecording: {
                            if isButtonReduced {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isButtonReduced = false
                                }
                            }
                            viewModel.toggleRecording()
                        }
                    )
                    .frame(maxHeight: isTranscriptionExpanded ? 408 : 240)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTranscriptionExpanded)
                    .onChange(of: viewModel.finalizedTranscription) { _, newValue in
                        // Update editable text when recording produces new transcription
                        // OR when resolving volatile text after stop
                        if viewModel.isRecording || viewModel.isResolvingTranscription {
                            editableTranscription = newValue
                        }
                    }

                    Divider()

                    // Summaries list
                    SummariesListView(
                        summaries: viewModel.summaries,
                        isProcessing: viewModel.isProcessingSummary,
                        onDelete: viewModel.deleteSummary,
                        streamingState: viewModel.streamingState,
                        showMetrics: viewModel.showMetrics,
                        onScroll: { offset in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                // Reduce button if scrolling down more than 50 points
                                isButtonReduced = offset > 50
                            }
                        },
                        onCancel: {
                            viewModel.cancelGeneration()
                        }
                    )
                }
                .toolbar {
                    // Language picker
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showLanguagePicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(viewModel.selectedLanguage.flag)
                                Text(viewModel.selectedLanguage.name)
                                    .font(.caption)
                            }
                        }
                        .disabled(viewModel.isRecording)
                    }

                    // Model picker
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showModelPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "brain.filled.head.profile")
                                Text(viewModel.selectedModel.displayName)
                                    .font(.caption)
                            }
                        }
                        .disabled(viewModel.isRecording)
                    }

                    // Clear all button
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !viewModel.summaries.isEmpty {
                            Button(role: .destructive) {
                                viewModel.clearAllSummaries()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        }
                    }

                    // Settings button
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "line.3.horizontal")
                        }
                    }
                }

                // Floating record button (only show when not reduced)
                if !isButtonReduced {
                    VStack {
                        Spacer()

                        FloatingRecordButton(
                            isRecording: viewModel.isRecording,
                            isResolving: viewModel.isResolvingTranscription,
                            isDisabled: viewModel.isLoadingModel,
                            isReduced: false,
                            action: {
                                viewModel.toggleRecording()
                            }
                        )
                        .padding(.bottom, 30)
                        .transition(.scale.combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isButtonReduced)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    // Error will be dismissed
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Handle app lifecycle changes
                switch newPhase {
                case .background:
                    // App entered background - cancel any ongoing generation
                    // iOS doesn't allow Metal/GPU operations in background
                    viewModel.cancelGenerationOnBackground()
                case .active:
                    // App became active - model is still loaded and ready
                    break
                case .inactive:
                    // App is transitioning
                    break
                @unknown default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                // Handle memory warnings aggressively
                viewModel.handleMemoryWarning()
            }
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerView(selectedLanguage: $viewModel.selectedLanguage)
            }
            .fullScreenCover(isPresented: $showModelPicker) {
                if #available(iOS 26.0, *) {
                    ModelPickerView(selectedModel: $viewModel.selectedModel)
                } else {
                    Text("Model picker requires iOS 26.0 or later")
                        .padding()
                }
            }
            .sheet(isPresented: $showModelDownload) {
                ModelDownloadView(
                    isPresented: $showModelDownload,
                    speechModelReady: viewModel.speechModelReady,
                    llmModelReady: viewModel.llmModelReady,
                    llmDownloadProgress: viewModel.modelDownloadProgress,
                    selectedModel: viewModel.selectedModel,
                    onDownloadModels: {
                        Task {
                            await viewModel.downloadModels()
                        }
                    },
                    onClearCache: {
                        do {
                            try viewModel.clearModelCache()
                            viewModel.checkModelReadiness()
                        } catch {
                            viewModel.setErrorMessage("Failed to clear cache: \(error.localizedDescription)")
                        }
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    showModelDownload: $showModelDownload,
                    showModelPicker: $showModelPicker,
                    speechModelReady: viewModel.speechModelReady,
                    llmModelReady: viewModel.llmModelReady,
                    modelCacheDirectory: viewModel.getModelCacheDirectory(),
                    onClearCache: {
                        do {
                            try viewModel.clearModelCache()
                            viewModel.checkModelReadiness()
                        } catch {
                            viewModel.setErrorMessage("Failed to clear cache: \(error.localizedDescription)")
                        }
                    }
                )
            }
            .onAppear {
                // Check if models need to be downloaded
                viewModel.checkModelReadiness()
                if !viewModel.llmModelReady {
                    showModelDownload = true
                }

                // Check SpeechTranscriber support
                if #available(iOS 26.0, *) {
                    Task {
                        let (isSupported, locales) = await DeviceCapabilities.checkSpeechTranscriberSupport()
                        await MainActor.run {
                            speechTranscriberSupported = isSupported
                            supportedLocales = locales
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Language Picker View

struct LanguagePickerView: View {
    @Binding var selectedLanguage: TranscriptionLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(TranscriptionLanguage.availableLanguages) { language in
                Button {
                    selectedLanguage = language
                    dismiss()
                } label: {
                    HStack {
                        Text(language.flag)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.name)
                                .font(.body)
                            Text(language.localeIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if language == selectedLanguage {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .tint(.primary)
            }
            .navigationTitle("Select Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Transcription View

struct TranscriptionView: View {
    let finalizedText: String
    let volatileText: String
    @Binding var editableText: String
    let isRecording: Bool
    let isLoadingModel: Bool
    let isResolving: Bool
    let isButtonReduced: Bool
    @Binding var isExpanded: Bool
    let onSummarize: () -> Void
    let onSendPrompt: () -> Void
    let onToggleRecording: () -> Void

    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header with clear and keyboard buttons
            HStack {
                Image(systemName: isRecording ? "waveform" : "text.bubble")
                    .foregroundStyle(isRecording ? .red : .secondary)
                    .symbolEffect(.pulse, isActive: isRecording)

                Text(isRecording ? "Recording..." : "Transcription/prompt")
                    .font(.headline)
                    .foregroundStyle(isRecording ? .red : .primary)

                Spacer()

                // Clear button
                if !editableText.isEmpty && !isRecording {
                    Button {
                        editableText = ""
                        isTextEditorFocused = false
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }

                // Keyboard dismiss button
                if isTextEditorFocused {
                    Button {
                        isTextEditorFocused = false
                    } label: {
                        Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)

            // Editable transcription area - always visible
            VStack(spacing: 0) {
                // TextEditor for editable transcription
                if isRecording {
                    // During recording: show finalized + volatile (read-only) with expand button
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if !finalizedText.isEmpty {
                                    Text(finalizedText)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }

                                if !volatileText.isEmpty {
                                    (Text(!finalizedText.isEmpty ? " " : "") + Text(volatileText))
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .opacity(0.6)
                                }

                                if finalizedText.isEmpty && volatileText.isEmpty {
                                    Text("Listening...")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .opacity(0.6)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Expand/collapse button (also visible during recording)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        .padding(8)
                    }
                } else {
                    // After recording: editable TextEditor with expand button
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $editableText)
                            .font(.body)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemBackground))
                            .focused($isTextEditorFocused)

                        // Expand/collapse button
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        .padding(8)
                    }
                }

                // Action buttons
                if !isRecording && !editableText.isEmpty {
                    Divider()

                    HStack(spacing: 12) {
                        // Show reduced record button when scrolled
                        if isButtonReduced {
                            Button {
                                onToggleRecording()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(isLoadingModel ? Color.gray : (isResolving ? Color.orange : (isRecording ? Color.red : Color.blue)))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white)
                                        .opacity(isLoadingModel ? 0.5 : 1.0)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingModel)
                        }

                        Button {
                            onSummarize()
                        } label: {
                            if isButtonReduced {
                                Label("Summarize", systemImage: "sparkles")
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                            } else {
                                Label("Summarize", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isLoadingModel)

                        Button {
                            onSendPrompt()
                        } label: {
                            if isButtonReduced {
                                Label("Send Prompt", systemImage: "paperplane")
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                            } else {
                                Label("Send Prompt", systemImage: "paperplane")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(isLoadingModel)
                    }
                    .padding()
                } else if isButtonReduced {
                    // Show reduced record button even when no text
                    Divider()

                    HStack {
                        Button {
                            onToggleRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(isLoadingModel ? Color.gray : (isResolving ? Color.orange : (isRecording ? Color.red : Color.blue)))
                                    .frame(width: 50, height: 50)
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .opacity(isLoadingModel ? 0.5 : 1.0)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingModel)

                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isRecording ? Color.red.opacity(0.5) : Color.blue.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

// MARK: - Summaries List View

struct SummariesListView: View {
    let summaries: [Summary]
    let isProcessing: Bool
    let onDelete: (Summary) -> Void
    let streamingState: StreamingState
    let showMetrics: Bool
    var onScroll: ((CGFloat) -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        Group {
            if summaries.isEmpty && !isProcessing && !streamingState.isStreaming {
                ContentUnavailableView(
                    "No Summaries",
                    systemImage: "doc.text"
                )
            } else {
                ScrollViewReader { proxy in
                    List {

                        // Streaming preview (while generating)
                    if streamingState.isStreaming || (isProcessing && !streamingState.partialText.isEmpty) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                                    .symbolEffect(.pulse, isActive: true)
                                    .padding(.trailing, 4)
                                Text("Generating...")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(streamingState.metrics.totalTokens) tokens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                // Cancel button
                                if let onCancel = onCancel {
                                    Button {
                                        onCancel()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Metrics overlay (at the top)
                            if showMetrics {
                                StreamingMetricsView(metrics: streamingState.metrics)
                            }

                            // Streaming text
                            Text(streamingState.partialText.isEmpty ? "Starting generation..." : streamingState.partialText)
                                .font(.callout)
                                .foregroundStyle(streamingState.partialText.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color(.systemGroupedBackground))
                    } else if isProcessing {
                        // Fallback: No streaming text yet
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                                .symbolEffect(.rotate, isActive: true)
                                .padding(.trailing, 8)
                            Text("Preparing model...")
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color(.systemGroupedBackground))
                    }

                    // Performance metrics for most recent summary (if available and showMetrics is true)
                    if showMetrics && !streamingState.isStreaming && streamingState.metrics.isComplete && !summaries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "chart.xyaxis.line")
                                    .foregroundStyle(.green)
                                    .padding(.trailing, 4)
                                Text("Generation Complete")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(streamingState.metrics.totalTokens) tokens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            StreamingMetricsView(metrics: streamingState.metrics)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color(.systemGroupedBackground))
                    }

                        // Completed summaries
                        ForEach(summaries) { summary in
                            SummaryRow(summary: summary)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        onDelete(summary)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        // Return the Y offset of the scroll view
                        return geometry.contentOffset.y
                    } action: { oldValue, newValue in
                        // Fire callback with absolute offset
                        let offset = abs(newValue)
                        onScroll?(offset)
                    }
                }
            }
        }
    }
}

// MARK: - SpeechTranscriber Unsupported Banner

struct SpeechTranscriberUnsupportedBanner: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main banner
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speech Recognition Not Supported")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text("Tap for details")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color.red.opacity(0.1))

            // Expandable details
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    // Device info
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Device: \(DeviceCapabilities.deviceModelName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text("No locales supported by SpeechTranscriber")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Explanation
                    Text(DeviceCapabilities.speechTranscriberUnsupportedReason)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .background(Color.red.opacity(0.05))
            }
        }
        .background(Color.red.opacity(0.1))
    }
}

// MARK: - Model Loading Banner

struct ModelLoadingBanner: View {
    let modelName: String
    let progress: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.9)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Loading Model")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if progress > 0 && progress < 1 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            // Progress bar
            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.blue.opacity(0.1))
    }
}

// MARK: - MLX Unsupported Banner

struct MLXUnsupportedBanner: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main banner
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("MLX Not Supported")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text("Tap for details")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color.orange.opacity(0.1))

            // Expandable details
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    // Device info
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Device: \(DeviceCapabilities.deviceModelName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text("Missing: air.simd_sum, rmsfloat16")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Explanation
                    Text(DeviceCapabilities.mlxUnsupportedReason)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .background(Color.orange.opacity(0.05))
            }
        }
        .background(Color.orange.opacity(0.1))
    }
}

#Preview {
    ContentView()
}
