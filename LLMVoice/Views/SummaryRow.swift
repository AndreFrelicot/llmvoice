//
//  SummaryRow.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import Foundation
import SwiftUI
import WebKit

struct SummaryRow: View {
    let summary: Summary

    @State private var isCompact = true
    @State private var showsOriginalTranscription = false
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
                        showsOriginalTranscription.toggle()
                    }
                } label: {
                    Image(systemName: "text.quote")
                        .foregroundStyle(showsOriginalTranscription ? .blue : .secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsOriginalTranscription ? "Hide original transcription" : "Show original transcription")
                .help(showsOriginalTranscription ? "Hide original transcription" : "Show original transcription")

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isCompact.toggle()
                    }
                } label: {
                    Image(systemName: isCompact ? "chevron.down.circle" : "chevron.up.circle.fill")
                        .foregroundStyle(.blue)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompact ? "Expand summary" : "Compact summary")
                .help(isCompact ? "Expand summary" : "Compact summary")
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
                    .lineLimit(isCompact ? 3 : nil)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)

            // Original transcription (collapsible)
            if showsOriginalTranscription {
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

private enum HTMLPreviewMode: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case source = "Source"
    case console = "Console"
    case analyzer = "Analyze"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .preview:
            return "safari"
        case .source:
            return "chevron.left.forwardslash.chevron.right"
        case .console:
            return "terminal"
        case .analyzer:
            return "stethoscope"
        }
    }
}

private enum HTMLSourceMode: String, CaseIterable, Identifiable {
    case rendered = "DOM"
    case input = "Input"

    var id: String { rawValue }
}

private enum HTMLConsoleLevel: String, Equatable {
    case debug
    case log
    case info
    case warning
    case error

    static func from(_ rawValue: String) -> HTMLConsoleLevel {
        switch rawValue.lowercased() {
        case "debug":
            return .debug
        case "info":
            return .info
        case "warn", "warning":
            return .warning
        case "error":
            return .error
        default:
            return .log
        }
    }

    var iconName: String {
        switch self {
        case .debug:
            return "ladybug"
        case .log:
            return "text.alignleft"
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .debug:
            return .purple
        case .log:
            return .secondary
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct HTMLConsoleMessage: Identifiable, Equatable {
    let id = UUID()
    let level: HTMLConsoleLevel
    let message: String
    let source: String?
    let line: Int?
    let column: Int?
    let timestamp: Date

    init(
        level: HTMLConsoleLevel,
        message: String,
        source: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.level = level
        self.message = message
        self.source = source
        self.line = line
        self.column = column
        self.timestamp = timestamp
    }
}

private enum HTMLIssueSeverity: Int, Equatable {
    case info = 0
    case warning = 1
    case error = 2

    var title: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }

    var iconName: String {
        switch self {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    func takingPriority(over other: HTMLIssueSeverity?) -> HTMLIssueSeverity {
        guard let other else { return self }
        return rawValue >= other.rawValue ? self : other
    }
}

private struct HTMLAnalysisIssue: Identifiable, Equatable {
    let id = UUID()
    let severity: HTMLIssueSeverity
    let message: String
    let line: Int?
    let detail: String?
}

private enum HTMLDiagnostics {
    static func analyze(
        inputSource: String,
        renderedSource: String,
        consoleMessages: [HTMLConsoleMessage]
    ) -> [HTMLAnalysisIssue] {
        var issues: [HTMLAnalysisIssue] = []
        let trimmedSource = inputSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedSource = inputSource.lowercased()

        if trimmedSource.isEmpty {
            issues.append(HTMLAnalysisIssue(
                severity: .error,
                message: "No HTML content found",
                line: nil,
                detail: "The extracted block is empty, so the preview cannot render anything."
            ))
        }

        if let line = firstLine(containing: "```", in: inputSource) {
            issues.append(HTMLAnalysisIssue(
                severity: .warning,
                message: "Markdown code fence found",
                line: line,
                detail: "Remove ```html / ``` fences before sending content to WebKit."
            ))
        }

        if lowercasedSource.contains("&lt;html") || lowercasedSource.contains("&lt;svg") || lowercasedSource.contains("&lt;div") {
            issues.append(HTMLAnalysisIssue(
                severity: .warning,
                message: "Escaped HTML detected",
                line: firstLine(containing: "&lt;", in: lowercasedSource),
                detail: "The model may have returned encoded markup. Decode entities before previewing."
            ))
        }

        if lowercasedSource.contains("<script") && !lowercasedSource.contains("</script>") {
            issues.append(HTMLAnalysisIssue(
                severity: .error,
                message: "Unclosed script tag",
                line: firstLine(containing: "<script", in: lowercasedSource),
                detail: "An open script tag can make the rest of the document disappear."
            ))
        }

        if lowercasedSource.contains("<style") && !lowercasedSource.contains("</style>") {
            issues.append(HTMLAnalysisIssue(
                severity: .error,
                message: "Unclosed style tag",
                line: firstLine(containing: "<style", in: lowercasedSource),
                detail: "An open style tag can consume the remaining HTML as CSS."
            ))
        }

        if lowercasedSource.contains("<svg") && !lowercasedSource.contains("</svg>") {
            issues.append(HTMLAnalysisIssue(
                severity: .warning,
                message: "SVG tag may be incomplete",
                line: firstLine(containing: "<svg", in: lowercasedSource),
                detail: "Inline SVG should usually include a closing </svg> tag."
            ))
        }

        if lowercasedSource.contains("display:none")
            || lowercasedSource.contains("visibility:hidden")
            || lowercasedSource.contains("opacity:0") {
            issues.append(HTMLAnalysisIssue(
                severity: .warning,
                message: "CSS may hide the rendered content",
                line: firstLine(containingAny: ["display:none", "visibility:hidden", "opacity:0"], in: lowercasedSource),
                detail: "Hidden root containers are a common cause of an apparently blank preview."
            ))
        }

        if hasExternalResource(in: lowercasedSource) {
            issues.append(HTMLAnalysisIssue(
                severity: .info,
                message: "External resource reference found",
                line: firstLine(containingAny: ["src=\"http", "src='http", "href=\"http", "href='http"], in: lowercasedSource),
                detail: "Images, scripts, stylesheets, or fonts loaded from the network can fail or be blocked."
            ))
        }

        issues.append(contentsOf: unbalancedTagIssues(in: inputSource))

        for message in consoleMessages where message.level == .error || message.level == .warning {
            issues.append(HTMLAnalysisIssue(
                severity: message.level == .error ? .error : .warning,
                message: "Runtime \(message.level.rawValue)",
                line: message.line,
                detail: message.message
            ))
        }

        if !renderedSource.isEmpty {
            let renderedLowercase = renderedSource.lowercased()
            if renderedLowercase.contains("<body></body>") || renderedLowercase.contains("<body>\n</body>") {
                issues.append(HTMLAnalysisIssue(
                    severity: .warning,
                    message: "Rendered DOM body is empty",
                    line: nil,
                    detail: "WebKit loaded the document, but the interpreted body has no visible content."
                ))
            }
        }

        return issues
    }

    private static func firstLine(containing needle: String, in source: String) -> Int? {
        for (index, line) in source.components(separatedBy: .newlines).enumerated() where line.contains(needle) {
            return index + 1
        }
        return nil
    }

    private static func firstLine(containingAny needles: [String], in source: String) -> Int? {
        for needle in needles {
            if let line = firstLine(containing: needle, in: source) {
                return line
            }
        }
        return nil
    }

    private static func hasExternalResource(in source: String) -> Bool {
        source.contains("src=\"http")
            || source.contains("src='http")
            || source.contains("href=\"http")
            || source.contains("href='http")
    }

    private static func unbalancedTagIssues(in source: String) -> [HTMLAnalysisIssue] {
        let pattern = #"<\s*(/)?\s*([a-zA-Z][a-zA-Z0-9:-]*)\b[^>]*?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let voidTags: Set<String> = [
            "area", "base", "br", "circle", "col", "embed", "hr", "img", "input",
            "line", "link", "meta", "param", "path", "polygon", "polyline", "rect",
            "source", "stop", "track", "use", "wbr"
        ]

        var stack: [(name: String, line: Int)] = []
        var issues: [HTMLAnalysisIssue] = []
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)

        for match in regex.matches(in: source, range: nsRange) {
            guard let fullRange = Range(match.range(at: 0), in: source),
                  let tagRange = Range(match.range(at: 2), in: source) else {
                continue
            }

            let rawTag = String(source[fullRange])
            let tag = String(source[tagRange]).lowercased()
            let line = lineNumber(for: fullRange.lowerBound, in: source)

            if rawTag.hasPrefix("<!") || rawTag.hasPrefix("<?") || rawTag.hasSuffix("/>") || voidTags.contains(tag) {
                continue
            }

            let isClosingTag = match.range(at: 1).location != NSNotFound
            if isClosingTag {
                if stack.last?.name == tag {
                    stack.removeLast()
                } else {
                    issues.append(HTMLAnalysisIssue(
                        severity: .warning,
                        message: "Closing tag without matching opener",
                        line: line,
                        detail: "Found </\(tag)> but the current open tag stack does not match."
                    ))
                }
            } else {
                stack.append((name: tag, line: line))
            }
        }

        for tag in stack.suffix(5) {
            issues.append(HTMLAnalysisIssue(
                severity: .warning,
                message: "Possibly unclosed tag",
                line: tag.line,
                detail: "The analyzer did not find a matching </\(tag.name)> tag."
            ))
        }

        return issues
    }

    private static func lineNumber(for index: String.Index, in source: String) -> Int {
        source[..<index].reduce(1) { partialResult, character in
            character == "\n" ? partialResult + 1 : partialResult
        }
    }
}

/// A SwiftUI wrapper for WKWebView to display HTML content and collect debug output.
private struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let onConsoleMessage: (HTMLConsoleMessage) -> Void
    let onRenderedSourceChange: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "llmvoiceConsole")
        userContentController.addUserScript(WKUserScript(
            source: Self.consoleCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        configuration.userContentController = userContentController
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
        guard context.coordinator.loadedHTML != htmlContent else { return }

        context.coordinator.loadedHTML = htmlContent
        onRenderedSourceChange("")
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onConsoleMessage: onConsoleMessage,
            onRenderedSourceChange: onRenderedSourceChange
        )
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "llmvoiceConsole")
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedHTML: String?
        private let onConsoleMessage: (HTMLConsoleMessage) -> Void
        private let onRenderedSourceChange: (String) -> Void

        init(
            onConsoleMessage: @escaping (HTMLConsoleMessage) -> Void,
            onRenderedSourceChange: @escaping (String) -> Void
        ) {
            self.onConsoleMessage = onConsoleMessage
            self.onRenderedSourceChange = onRenderedSourceChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onConsoleMessage(HTMLConsoleMessage(level: .info, message: "WebView finished loading"))
            captureRenderedSource(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onConsoleMessage(HTMLConsoleMessage(level: .error, message: "Navigation failed: \(error.localizedDescription)"))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onConsoleMessage(HTMLConsoleMessage(level: .error, message: "Provisional navigation failed: \(error.localizedDescription)"))
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "llmvoiceConsole",
                  let body = message.body as? [String: Any] else {
                return
            }

            let rawLine = (body["line"] as? NSNumber)?.intValue ?? 0
            let rawColumn = (body["column"] as? NSNumber)?.intValue ?? 0

            onConsoleMessage(HTMLConsoleMessage(
                level: HTMLConsoleLevel.from(body["level"] as? String ?? "log"),
                message: body["message"] as? String ?? "",
                source: body["source"] as? String,
                line: rawLine > 0 ? rawLine : nil,
                column: rawColumn > 0 ? rawColumn : nil
            ))
        }

        private func captureRenderedSource(from webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''") { [onRenderedSourceChange] result, error in
                if let error {
                    self.onConsoleMessage(HTMLConsoleMessage(
                        level: .error,
                        message: "Could not read rendered DOM: \(error.localizedDescription)"
                    ))
                    return
                }

                onRenderedSourceChange(result as? String ?? "")
            }
        }
    }

    private static let consoleCaptureScript = """
    (function() {
      if (window.__llmVoiceConsoleInstalled) { return; }
      window.__llmVoiceConsoleInstalled = true;

      function serialize(value) {
        try {
          if (value instanceof Error) {
            return value.name + ': ' + value.message;
          }
          if (typeof value === 'object') {
            return JSON.stringify(value);
          }
          return String(value);
        } catch (error) {
          return String(value);
        }
      }

      function post(level, args, source, line, column) {
        try {
          window.webkit.messageHandlers.llmvoiceConsole.postMessage({
            level: level,
            message: Array.prototype.slice.call(args).map(serialize).join(' '),
            source: source || '',
            line: line || 0,
            column: column || 0
          });
        } catch (error) {}
      }

      ['debug', 'log', 'info', 'warn', 'error'].forEach(function(level) {
        var original = console[level];
        console[level] = function() {
          post(level, arguments);
          if (original) {
            original.apply(console, arguments);
          }
        };
      });

      window.addEventListener('error', function(event) {
        post('error', [event.message], event.filename, event.lineno, event.colno);
      });

      window.addEventListener('unhandledrejection', function(event) {
        post('error', ['Unhandled promise rejection', event.reason]);
      });
    })();
    """
}

/// Sheet view for previewing HTML/SVG content
struct HTMLPreviewView: View {
    let htmlContent: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: HTMLPreviewMode = .preview
    @State private var selectedSourceMode: HTMLSourceMode = .rendered
    @State private var consoleMessages: [HTMLConsoleMessage] = []
    @State private var renderedSource = ""
    @State private var reloadID = UUID()

    private var analysisIssues: [HTMLAnalysisIssue] {
        HTMLDiagnostics.analyze(
            inputSource: htmlContent,
            renderedSource: renderedSource,
            consoleMessages: consoleMessages
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Preview Mode", selection: $selectedMode) {
                    ForEach(HTMLPreviewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

                Divider()

                Group {
                    switch selectedMode {
                    case .preview:
                        HTMLWebView(
                            htmlContent: htmlContent,
                            onConsoleMessage: appendConsoleMessage,
                            onRenderedSourceChange: updateRenderedSource
                        )
                        .id(reloadID)
                        .ignoresSafeArea(edges: .bottom)

                    case .source:
                        HTMLSourceView(
                            inputSource: htmlContent,
                            renderedSource: renderedSource,
                            selectedSourceMode: $selectedSourceMode,
                            issues: analysisIssues
                        )

                    case .console:
                        HTMLConsoleView(messages: consoleMessages)

                    case .analyzer:
                        HTMLAnalyzerView(issues: analysisIssues)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        reloadPreview()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload preview")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func appendConsoleMessage(_ message: HTMLConsoleMessage) {
        consoleMessages.append(message)
    }

    private func updateRenderedSource(_ source: String) {
        guard renderedSource != source else { return }
        renderedSource = source
    }

    private func reloadPreview() {
        consoleMessages.removeAll()
        renderedSource = ""
        selectedMode = .preview
        reloadID = UUID()
    }
}

private struct HTMLSourceView: View {
    let inputSource: String
    let renderedSource: String
    @Binding var selectedSourceMode: HTMLSourceMode
    let issues: [HTMLAnalysisIssue]

    private var displayedSource: String {
        switch selectedSourceMode {
        case .rendered:
            return renderedSource.isEmpty ? inputSource : renderedSource
        case .input:
            return inputSource
        }
    }

    private var title: String {
        switch selectedSourceMode {
        case .rendered:
            return renderedSource.isEmpty ? "Rendered DOM unavailable, showing input" : "Rendered DOM"
        case .input:
            return "Input source"
        }
    }

    private var lineSeverities: [Int: HTMLIssueSeverity] {
        issues.reduce(into: [:]) { result, issue in
            guard let line = issue.line else { return }
            result[line] = issue.severity.takingPriority(over: result[line])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Source", selection: $selectedSourceMode) {
                    ForEach(HTMLSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer()

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            SourceCodeView(source: displayedSource, lineSeverities: lineSeverities)
        }
    }
}

private struct SourceCodeView: View {
    let source: String
    let lineSeverities: [Int: HTMLIssueSeverity]

    private var lines: [String] {
        let splitLines = source.components(separatedBy: .newlines)
        return splitLines.isEmpty ? [""] : splitLines
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let lineNumber = index + 1
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(lineNumber)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)

                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .textSelection(.enabled)
                        }
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(lineSeverities[lineNumber]?.tint.opacity(0.14) ?? .clear)
                    }
                }
                .frame(
                    minWidth: geometry.size.width,
                    minHeight: geometry.size.height,
                    alignment: .topLeading
                )
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.background)
    }
}

private struct HTMLConsoleView: View {
    let messages: [HTMLConsoleMessage]

    var body: some View {
        if messages.isEmpty {
            ContentUnavailableView(
                "No Console Messages",
                systemImage: "terminal",
                description: Text("JavaScript logs, warnings, and runtime errors will appear here.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: message.level.iconName)
                                .foregroundStyle(message.level.tint)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(message.level.rawValue.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(message.level.tint)

                                    Text(message.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if let line = message.line {
                                        Text("line \(line)\(message.column.map { ":\($0)" } ?? "")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(message.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.primary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(message.level.tint.opacity(0.10), in: .rect(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
    }
}

private struct HTMLAnalyzerView: View {
    let issues: [HTMLAnalysisIssue]

    var body: some View {
        if issues.isEmpty {
            ContentUnavailableView(
                "No Issues Found",
                systemImage: "checkmark.seal",
                description: Text("The static analyzer and captured runtime logs did not report problems.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: issue.severity.iconName)
                                .foregroundStyle(issue.severity.tint)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(issue.severity.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(issue.severity.tint)

                                    if let line = issue.line {
                                        Text("line \(line)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(issue.message)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)

                                if let detail = issue.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(issue.severity.tint.opacity(0.10), in: .rect(cornerRadius: 8))
                    }
                }
                .padding()
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
            content: "Brainstormed new feature ideas based on user feedback and scheduled a follow-up meeting for next week. The team identified onboarding, model download visibility, and summary editing as the most urgent improvements. The next discussion will focus on implementation order, expected complexity, and what should remain outside the first clean release.",
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
