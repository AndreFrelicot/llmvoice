//
//  MLXModelConfig.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-10
//

import Foundation

/// Represents an AI language model configuration (Apple Intelligence or MLX models)
enum MLXModel: String, CaseIterable, Identifiable, Codable {
    case appleIntelligence = "apple-intelligence"
    case gemma3_1b = "gemma-3-1b"
    case gemma3_1b_qat = "gemma-3-1b-qat"
    case qwen25_05b = "qwen2.5-0.5b"
    case qwen3_06b = "qwen3-0.6b"
    case llama32_1b = "llama-3.2-1b"

    var id: String { rawValue }

    /// Whether this is an on-device model (vs cloud/Apple Intelligence)
    var isOnDeviceMLX: Bool {
        switch self {
        case .appleIntelligence:
            return false
        case .gemma3_1b, .gemma3_1b_qat, .qwen25_05b, .qwen3_06b, .llama32_1b:
            return true
        }
    }

    /// Display name for the model
    var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .gemma3_1b:
            return "Gemma 3 (1B)"
        case .gemma3_1b_qat:
            return "Gemma 3 QAT (1B)"
        case .qwen25_05b:
            return "Qwen2.5 (0.5B)"
        case .qwen3_06b:
            return "Qwen3 (0.6B)"
        case .llama32_1b:
            return "Llama 3.2 (1B)"
        }
    }

    /// HuggingFace model ID for downloading (MLX models only)
    var huggingFaceID: String {
        switch self {
        case .appleIntelligence:
            return ""  // No download needed for Apple Intelligence
        case .gemma3_1b:
            return "mlx-community/gemma-3-1b-it-4bit"
        case .gemma3_1b_qat:
            return "mlx-community/gemma-3-1b-it-qat-4bit"
        case .qwen25_05b:
            return "lmstudio-community/Qwen2.5-0.5B-Instruct-MLX-4bit"
        case .qwen3_06b:
            return "mlx-community/Qwen3-0.6B-4bit"
        case .llama32_1b:
            return "mlx-community/Llama-3.2-1B-Instruct-4bit"
        }
    }

    /// Model description
    var description: String {
        switch self {
        case .appleIntelligence:
            return "System AI model (requires iPhone 15 Pro or later)"
        case .gemma3_1b:
            return "140+ languages, 32k context (300MB)"
        case .gemma3_1b_qat:
            return "140+ languages, QAT 4-bit (733MB)"
        case .qwen25_05b:
            return "29+ languages, 32k context (150MB)"
        case .qwen3_06b:
            return "100+ languages, 32k context (335MB)"
        case .llama32_1b:
            return "8 languages (EN/ES/FR/DE/IT/PT/HI/TH) (500MB)"
        }
    }

    /// Number of parameters (in millions)
    var parameters: Int {
        switch self {
        case .appleIntelligence:
            return 0  // Not applicable
        case .gemma3_1b:
            return 1000  // 1B
        case .gemma3_1b_qat:
            return 1000  // 1B
        case .qwen25_05b:
            return 500  // 0.5B
        case .qwen3_06b:
            return 600  // 0.6B
        case .llama32_1b:
            return 1000  // 1B
        }
    }

    /// Approximate model size in MB (4-bit quantized)
    var sizeInMB: Int {
        switch self {
        case .appleIntelligence:
            return 0  // No local storage needed
        case .gemma3_1b:
            return 300
        case .gemma3_1b_qat:
            return 733
        case .qwen25_05b:
            return 150
        case .qwen3_06b:
            return 335
        case .llama32_1b:
            return 500
        }
    }

    /// GPU cache limit in bytes (MLX models only)
    var cacheLimitBytes: Int {
        switch self {
        case .appleIntelligence:
            return 0  // Not applicable
        case .qwen25_05b, .qwen3_06b:
            return 128 * 1024 * 1024  // 128MB for smallest model
        case .gemma3_1b, .gemma3_1b_qat, .llama32_1b:
            return 256 * 1024 * 1024  // 256MB for 1B models
        }
    }

    /// GPU memory limit in bytes (MLX models only)
    var memoryLimitBytes: Int {
        switch self {
        case .appleIntelligence:
            return 0  // Not applicable
        case .qwen25_05b, .qwen3_06b:
            return 768 * 1024 * 1024  // 768MB for smallest model
        case .gemma3_1b, .gemma3_1b_qat, .llama32_1b:
            return 1024 * 1024 * 1024  // 1GB for 1B models
        }
    }

    /// Generation parameters (MLX models only)
    var generationParams: ModelGenerationParameters {
        switch self {
        case .appleIntelligence:
            return ModelGenerationParameters(
                maxTokens: 0,  // Not applicable
                temperature: 0.0,
                topP: 0.0
            )
        case .gemma3_1b, .gemma3_1b_qat:
            return ModelGenerationParameters(
                maxTokens: 2000,
                temperature: 0.3,
                topP: 0.9
            )
        case .qwen25_05b:
            return ModelGenerationParameters(
                maxTokens: 2000,
                temperature: 0.7,
                topP: 0.9
            )
        case .qwen3_06b:
            return ModelGenerationParameters(
                maxTokens: 2000,
                temperature: 0.7,
                topP: 0.8
            )
        case .llama32_1b:
            return ModelGenerationParameters(
                maxTokens: 2000,
                temperature: 0.3,
                topP: 0.9
            )
        }
    }

    /// Format prompt for this model with custom template (MLX models only)
    func formatPrompt(text: String, customTemplate: String? = nil) -> String {
        // If custom template provided, use it
        if let template = customTemplate {
            return template.replacingOccurrences(of: "{{text}}", with: text)
        }

        // Otherwise use default template
        return defaultPromptTemplate(text: text)
    }

    /// Get default prompt template for this model (MLX models only)
    private func defaultPromptTemplate(text: String) -> String {
        switch self {
        case .appleIntelligence:
            return ""  // Not used for Apple Intelligence
        case .gemma3_1b, .gemma3_1b_qat:
            // Gemma 2/3 uses standard chat format with special tokens
            // Note: Must end with newline after <start_of_turn>model
            return """
            <bos><start_of_turn>user
            Please provide a concise summary of the following text in 2-3 sentences. Focus on the key points and main ideas:

            \(text)<end_of_turn>
            <start_of_turn>model
            """

        case .qwen25_05b:
            // Qwen2.5 uses ChatML format
            return """
            <|im_start|>system
            You are a helpful AI assistant. Your task is to summarize text concisely.<|im_end|>
            <|im_start|>user
            Summarize the following text in 2-3 clear sentences:

            \(text)<|im_end|>
            <|im_start|>assistant
            """

        case .qwen3_06b:
            // Qwen3 uses ChatML. The empty think block requests non-thinking mode,
            // keeping summaries concise and avoiding streamed <think> sections.
            return """
            <|im_start|>system
            You are a helpful AI assistant. Your task is to summarize text concisely.<|im_end|>
            <|im_start|>user
            Summarize the following text in 2-3 clear sentences:

            \(text)<|im_end|>
            <|im_start|>assistant
            <think>

            </think>

            """

        case .llama32_1b:
            // Llama 3.2 uses special token format
            return """
            <|start_header_id|>system<|end_header_id|>

            You are a helpful assistant that creates concise summaries.<|eot_id|><|start_header_id|>user<|end_header_id|>

            Please provide a concise summary of the following text in 2-3 sentences. Focus on the key points and main ideas:

            \(text)<|eot_id|><|start_header_id|>assistant<|end_header_id|>

            """
        }
    }

    /// Get bundled model folder name (if bundled)
    var bundledFolderName: String? {
        // No models are bundled by default
        return nil
    }

    /// Get all possible cache directory patterns to check
    /// (handles potential case normalization by HuggingFace/MLX)
    var possibleCachePatterns: [String] {
        let components = huggingFaceID.split(separator: "/")
        guard components.count == 2 else { return [] }

        let original = "models--\(components[0])--\(components[1])"
        let lowercase = original.lowercased()

        // Return both to be safe
        if original == lowercase {
            return [original]
        } else {
            return [original, lowercase]
        }
    }

    /// Stop sequences to halt generation (MLX models only)
    var stopSequences: [String] {
        switch self {
        case .appleIntelligence:
            return []  // Not used for Apple Intelligence
        case .gemma3_1b, .gemma3_1b_qat:
            return ["<end_of_turn>"]  // Gemma stop token
        case .qwen25_05b, .qwen3_06b:
            return ["<|im_end|>"]  // Qwen ChatML end token
        case .llama32_1b:
            return ["<|eot_id|>"]  // Llama end-of-turn token
        }
    }
}

/// Generation parameters for model inference
struct ModelGenerationParameters {
    let maxTokens: Int
    let temperature: Float
    let topP: Float
}
