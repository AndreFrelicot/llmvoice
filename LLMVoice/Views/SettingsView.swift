//
//  SettingsView.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showModelDownload: Bool
    @Binding var showModelPicker: Bool
    let speechModelReady: Bool
    let llmModelReady: Bool
    let modelCacheDirectory: String?
    let onClearCache: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Model Management Section
                Section {
                    // Model Status
                    HStack {
                        Label("Speech Recognition", systemImage: "waveform")
                        Spacer()
                        if speechModelReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    HStack {
                        Label("LLM Models", systemImage: "brain")
                        Spacer()
                        if llmModelReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    // Manage Models Button
                    Button {
                        showModelPicker = true
                        dismiss()
                    } label: {
                        HStack {
                            Label(llmModelReady ? "Manage Models" : "Download Models", systemImage: llmModelReady ? "gearshape" : "arrow.down.circle")
                            Spacer()
                            if !llmModelReady {
                                Text("Required")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Clear Cache Button
                    if llmModelReady {
                        Button(role: .destructive) {
                            onClearCache()
                        } label: {
                            HStack {
                                Label("Clear Model Cache", systemImage: "trash")
                                Spacer()
                                Text("~300 MB")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("AI Models")
                } footer: {
                    if let cacheDir = modelCacheDirectory {
                        Text("Models are stored at:\n\(cacheDir)")
                            .font(.caption2)
                    }
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://andrefrelicot.dev")!) {
                        HStack {
                            Label("andrefrelicot.dev", systemImage: "globe")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Link(destination: URL(string: "https://github.com/AndreFrelicot/llmvoice")!) {
                        HStack {
                            Label("github.com/AndreFrelicot/llmvoice", systemImage: "globe")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Link(destination: URL(string: "https://andrefrelicot.dev/legal/llmvoice/llmvoice-privacy-policy-en.html")!) {
                        HStack {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(
        showModelDownload: .constant(false),
        showModelPicker: .constant(false),
        speechModelReady: true,
        llmModelReady: true,
        modelCacheDirectory: "/Users/test/Library/Caches/huggingface",
        onClearCache: { print("Clear cache") }
    )
}
