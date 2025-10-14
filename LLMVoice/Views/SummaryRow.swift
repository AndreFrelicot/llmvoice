//
//  SummaryRow.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import SwiftUI
import WebKit

struct SummaryRow: View {
    let summary: Summary

    @State private var isExpanded = false
    @State private var showHTMLPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with timestamp, computation time, and model
            HStack {
                Label {
                    Text(summary.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let computationTime = summary.computationTime {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label {
                        Text(formatComputationTime(computationTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let modelUsed = summary.modelUsed {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label {
                        Text(modelUsed)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .foregroundStyle(.blue)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }

            // HTML/SVG Preview button
            if summary.containsHTMLOrSVG {
                Button {
                    showHTMLPreview = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: summary.hasInvalidSVG ? "exclamationmark.triangle.fill" : "safari")
                            .foregroundStyle(summary.hasInvalidSVG ? .orange : .blue)
                        Text(summary.hasInvalidSVG ? "Preview (Invalid SVG)" : "Preview HTML/SVG")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(summary.hasInvalidSVG ? .orange : .blue)
                .controlSize(.small)
            }

            // Summary content
            VStack(alignment: .leading, spacing: 8) {
                Label("", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(summary.content)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)

            // Original transcription (collapsible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Label("Original Transcription", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(summary.originalTranscription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showHTMLPreview) {
            if let htmlContent = summary.extractedHTMLContent {
                HTMLPreviewView(htmlContent: htmlContent)
            } else {
                Text("Unable to extract HTML/SVG content")
                    .padding()
            }
        }
    }

    /// Format computation time for display
    private func formatComputationTime(_ seconds: TimeInterval) -> String {
        if seconds < 1.0 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60.0 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - HTML WebView Components

/// A SwiftUI wrapper for WKWebView to display HTML content
struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Suppress system logs and warnings
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.backgroundColor = .white
        webView.backgroundColor = .white
        webView.isOpaque = true

        // Allow inline media playback and better rendering
        webView.configuration.allowsInlineMediaPlayback = true

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        #if DEBUG
        print("📄 Loading HTML content:")
        print(htmlContent)
        print("---")
        #endif

        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            #if DEBUG
            print("✅ WebView finished loading")
            #endif
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("❌ WebView failed to load: \(error.localizedDescription)")
            #endif
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("❌ WebView provisional navigation failed: \(error.localizedDescription)")
            #endif
        }
    }
}

/// Sheet view for previewing HTML/SVG content
struct HTMLPreviewView: View {
    let htmlContent: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HTMLWebView(htmlContent: htmlContent)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        SummaryRow(summary: Summary(
            content: "Discussed project timeline, reviewed budget allocation, and assigned tasks to team members for the next quarter.",
            originalTranscription: "In today's meeting we discussed the project timeline and the various milestones that we need to achieve. We also reviewed the budget allocation for the next quarter and made sure everyone is on the same page regarding their responsibilities and the tasks they need to complete.",
            computationTime: 2.3,
            modelUsed: "Llama 3.2 (1B)"
        ))

        SummaryRow(summary: Summary(
            content: "Brainstormed new feature ideas based on user feedback and scheduled a follow-up meeting for next week.",
            originalTranscription: "The team gathered to brainstorm new feature ideas based on recent user feedback. We prioritized the most requested features and decided to schedule a follow-up meeting next week to discuss implementation details.",
            computationTime: 1.7,
            modelUsed: "Gemma 3 (1B)"
        ))

        SummaryRow(summary: Summary(
            content: "Quick test summary with fast computation time.",
            originalTranscription: "This is a short test transcription.",
            computationTime: 0.45,
            modelUsed: "Qwen2.5 (0.5B)"
        ))
    }
    .listStyle(.insetGrouped)
}
