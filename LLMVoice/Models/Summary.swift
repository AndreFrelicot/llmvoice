//
//  Summary.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import Foundation

/// Represents an AI-generated summary of a transcription
struct Summary: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let originalTranscription: String
    let timestamp: Date
    let computationTime: TimeInterval? // Time in seconds to generate the summary
    let modelUsed: String? // Name of the model used to generate the summary

    init(id: UUID = UUID(), content: String, originalTranscription: String, timestamp: Date = Date(), computationTime: TimeInterval? = nil, modelUsed: String? = nil) {
        self.id = id
        self.content = content
        self.originalTranscription = originalTranscription
        self.timestamp = timestamp
        self.computationTime = computationTime
        self.modelUsed = modelUsed
    }

    /// Checks if the content contains HTML, SVG, or CSS code blocks
    var containsHTMLOrSVG: Bool {
        content.contains("```html") ||
        content.contains("```svg") ||
        content.contains("```xml") ||
        content.contains("<svg") ||
        content.contains("```css")
    }

    /// Checks if the extracted SVG content is invalid
    var hasInvalidSVG: Bool {
        // Extract any SVG content
        var svgContent: String?

        if let svgRange = content.range(of: "```svg\\s*\\n([\\s\\S]*?)```", options: .regularExpression) {
            let match = String(content[svgRange])
            svgContent = match
                .replacingOccurrences(of: "```svg", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let xmlRange = content.range(of: "```xml\\s*\\n([\\s\\S]*?)```", options: .regularExpression) {
            let match = String(content[xmlRange])
            let cleaned = match
                .replacingOccurrences(of: "```xml", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.contains("<svg") {
                svgContent = cleaned
            }
        } else if let svgRange = content.range(of: "<svg[\\s\\S]*?</svg>", options: .regularExpression) {
            svgContent = String(content[svgRange])
        }

        if let svg = svgContent {
            return !isValidSVG(svg)
        }

        return false
    }

    /// Extracts CSS from ```css code blocks
    private var extractedCSS: String? {
        guard content.contains("```css") else { return nil }

        if let cssRange = content.range(of: "```css\\s*\\n([\\s\\S]*?)```", options: .regularExpression) {
            let match = String(content[cssRange])
            let cleaned = match
                .replacingOccurrences(of: "```css", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }

        return nil
    }

    /// Cleans malformed HTML/SVG content from LLM
    private func cleanHTMLContent(_ content: String) -> String {
        var cleaned = content

        // Remove nested DOCTYPE and html tags if they appear after the body tag
        if cleaned.contains("<body>") {
            // Extract everything after <body> until </body>
            if let bodyRange = cleaned.range(of: "<body>([\\s\\S]*?)</body>", options: .regularExpression) {
                let bodyContent = String(cleaned[bodyRange])
                    .replacingOccurrences(of: "<body>", with: "")
                    .replacingOccurrences(of: "</body>", with: "")

                // Remove any nested DOCTYPE/html tags from body content
                var bodyClean = bodyContent
                    .replacingOccurrences(of: "<!DOCTYPE html>", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "<html[^>]*>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "</html>", with: "", options: .caseInsensitive)

                // Fix quote issues after closing tags
                bodyClean = bodyClean.replacingOccurrences(of: "</path>\"", with: "</path>")
                bodyClean = bodyClean.replacingOccurrences(of: "</svg>\"", with: "</svg>")

                // Reconstruct with clean body
                if let headEndRange = cleaned.range(of: "</head>", options: .caseInsensitive) {
                    let beforeBody = String(cleaned[..<headEndRange.upperBound])
                    cleaned = beforeBody + "\n<body>\n" + bodyClean.trimmingCharacters(in: .whitespacesAndNewlines) + "\n</body>\n</html>"
                }
            }
        }

        return cleaned
    }

    /// Validates if SVG content has basic valid structure
    private func isValidSVG(_ svgContent: String) -> Bool {
        // Basic validation checks
        let hasOpeningTag = svgContent.contains("<svg")
        let hasClosingTag = svgContent.contains("</svg>")

        // Check for common invalid patterns that LLMs generate
        let hasInvalidFunctions = svgContent.contains("materialize(") ||
                                   svgContent.contains("function(") ||
                                   svgContent.contains("gradient(") // CSS gradient in SVG path

        // Check for malformed path commands (incomplete coordinates)
        let hasIncompletePathCommands = svgContent.range(of: "[MmLlHhVvCcSsQqTtAaZz]\\s*\\n", options: .regularExpression) != nil

        return hasOpeningTag && hasClosingTag && !hasInvalidFunctions && !hasIncompletePathCommands
    }

    /// Creates an error message HTML for invalid SVG
    private func createSVGErrorHTML(_ svgContent: String) -> String {
        let escapedSVG = svgContent
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    padding: 20px;
                    background-color: #f5f5f7;
                }
                .error-box {
                    background: #fff3cd;
                    border: 2px solid #ffc107;
                    border-radius: 8px;
                    padding: 16px;
                    margin-bottom: 20px;
                }
                .error-title {
                    color: #856404;
                    font-weight: 600;
                    margin-bottom: 8px;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }
                .error-message {
                    color: #856404;
                    margin-bottom: 12px;
                }
                .code-block {
                    background: #f8f9fa;
                    border: 1px solid #dee2e6;
                    border-radius: 4px;
                    padding: 12px;
                    overflow-x: auto;
                    font-family: 'SF Mono', Monaco, monospace;
                    font-size: 12px;
                    color: #212529;
                    white-space: pre-wrap;
                    word-break: break-all;
                }
            </style>
        </head>
        <body>
            <div class="error-box">
                <div class="error-title">
                    ⚠️ Invalid SVG Detected
                </div>
                <div class="error-message">
                    The LLM generated SVG code with invalid syntax. This SVG cannot be rendered by browsers.
                </div>
                <details>
                    <summary style="cursor: pointer; color: #856404; font-weight: 500; margin-bottom: 8px;">View Generated SVG Code</summary>
                    <div class="code-block">\(escapedSVG)</div>
                </details>
            </div>
        </body>
        </html>
        """
    }

    /// Extracts HTML/SVG content from code blocks or raw content and injects CSS if present
    var extractedHTMLContent: String? {
        guard containsHTMLOrSVG else { return nil }

        // Extract CSS if present
        let cssContent = extractedCSS

        // Try to extract from ```html code blocks
        if let htmlRange = content.range(of: "```html\\s*\\n([\\s\\S]*?)```", options: .regularExpression) {
            let match = String(content[htmlRange])
            let cleaned = match
                .replacingOccurrences(of: "```html", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let injected = injectCSS(into: cleaned, css: cssContent)
            return cleanHTMLContent(injected)
        }

        // Try to extract from ```svg code blocks
        if let svgRange = content.range(of: "```svg\\s*\\n([\\s\\S]*?)```", options: .regularExpression) {
            let match = String(content[svgRange])
            let cleaned = match
                .replacingOccurrences(of: "```svg", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate SVG
            if isValidSVG(cleaned) {
                return wrapSVGInHTML(cleaned, css: cssContent)
            } else {
                return createSVGErrorHTML(cleaned)
            }
        }

        // Try to extract from ```xml code blocks (SVG is often in xml blocks)
        if let xmlRange = content.range(of: "```xml\\s*\\n([\\s\\S]*?)```", options: .regularExpression) {
            let match = String(content[xmlRange])
            let cleaned = match
                .replacingOccurrences(of: "```xml", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Only process if it contains SVG
            if cleaned.contains("<svg") {
                // Validate SVG
                if isValidSVG(cleaned) {
                    return wrapSVGInHTML(cleaned, css: cssContent)
                } else {
                    return createSVGErrorHTML(cleaned)
                }
            }
        }

        // Check for raw SVG content
        if content.contains("<svg") {
            // Extract SVG tags
            if let svgRange = content.range(of: "<svg[\\s\\S]*?</svg>", options: .regularExpression) {
                let svgContent = String(content[svgRange])

                // Validate SVG
                if isValidSVG(svgContent) {
                    return wrapSVGInHTML(svgContent, css: cssContent)
                } else {
                    return createSVGErrorHTML(svgContent)
                }
            }
        }

        return nil
    }

    /// Injects CSS into existing HTML content
    private func injectCSS(into html: String, css: String?) -> String {
        // Check if HTML already has complete structure
        let hasDoctype = html.lowercased().contains("<!doctype")
        let hasHead = html.lowercased().contains("<head")

        // If it's a complete HTML document with head
        if hasDoctype && hasHead {
            if let css = css {
                // Inject CSS before closing </head>
                if let headCloseRange = html.range(of: "</head>", options: .caseInsensitive) {
                    var modifiedHTML = html
                    let styleTag = "\n    <style>\n        \(css)\n    </style>\n"
                    modifiedHTML.insert(contentsOf: styleTag, at: headCloseRange.lowerBound)
                    return modifiedHTML
                }
            }
            return html
        }

        // If it has head but no doctype
        if hasHead {
            let wrappedHTML = "<!DOCTYPE html>\n<html>\n\(html)\n</html>"
            if let css = css {
                if let headCloseRange = wrappedHTML.range(of: "</head>", options: .caseInsensitive) {
                    var modifiedHTML = wrappedHTML
                    let styleTag = "\n    <style>\n        \(css)\n    </style>\n"
                    modifiedHTML.insert(contentsOf: styleTag, at: headCloseRange.lowerBound)
                    return modifiedHTML
                }
            }
            return wrappedHTML
        }

        // No proper HTML structure - wrap everything
        let cssBlock = css.map {
            """

                <style>
                    \($0)
                </style>
            """
        } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">\(cssBlock)
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }

    /// Wraps SVG content in a basic HTML document with optional CSS injection
    private func wrapSVGInHTML(_ svgContent: String, css: String? = nil) -> String {
        let customStyles = css.map { cssValue in "\n                \(cssValue)" } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 20px;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    background-color: #f5f5f7;
                }
                svg {
                    max-width: 100%;
                    height: auto;
                }\(customStyles)
            </style>
        </head>
        <body>
            \(svgContent)
        </body>
        </html>
        """
    }
}
