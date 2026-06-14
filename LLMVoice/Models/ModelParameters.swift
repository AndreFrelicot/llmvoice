//
//  ModelParameters.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-12
//

import Foundation

/// Custom parameters for a specific model
struct ModelParameters: Codable {
    var prompt: String
    var temperature: Float
    var topP: Float
    var maxTokens: Int

    /// Get the default parameters for a specific model
    static func defaults(for model: MLXModel) -> ModelParameters {
        let params = model.generationParams
        return ModelParameters(
            prompt: model.formatPrompt(text: "{{text}}"),
            temperature: params.temperature,
            topP: params.topP,
            maxTokens: params.maxTokens
        )
    }
}

/// Manager for storing and retrieving custom model parameters
@MainActor
class ModelParametersManager: ObservableObject {
    private let userDefaultsKey = "dev.andrefrelicot.llmvoice.modelParameters"

    @Published private var parameters: [String: ModelParameters] = [:]

    init() {
        loadParameters()
    }

    /// Get parameters for a model (returns defaults if not customized)
    func getParameters(for model: MLXModel) -> ModelParameters {
        if let stored = parameters[model.rawValue] {
            return stored
        }
        return ModelParameters.defaults(for: model)
    }

    /// Save parameters for a model
    func saveParameters(_ params: ModelParameters, for model: MLXModel) {
        parameters[model.rawValue] = params
        persistParameters()
    }

    /// Reset parameters for a model to defaults
    func resetParameters(for model: MLXModel) {
        parameters.removeValue(forKey: model.rawValue)
        persistParameters()
    }

    /// Check if model has custom parameters
    func hasCustomParameters(for model: MLXModel) -> Bool {
        return parameters[model.rawValue] != nil
    }

    // MARK: - Private

    private func loadParameters() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              var decoded = try? JSONDecoder().decode([String: ModelParameters].self, from: data) else {
            return
        }

        var migratedLegacyTokenLimits = false
        let legacyTokenLimits = Set([2_000, 3_000, 4_000, 6_000])
        for (modelID, params) in decoded {
            guard let model = MLXModel(rawValue: modelID),
                  model.isOnDeviceMLX,
                  legacyTokenLimits.contains(params.maxTokens) else {
                continue
            }

            var updatedParams = params
            updatedParams.maxTokens = model.maxTokenLimit
            decoded[modelID] = updatedParams
            migratedLegacyTokenLimits = true
        }

        parameters = decoded

        if migratedLegacyTokenLimits {
            persistParameters()
        }
    }

    private func persistParameters() {
        guard let encoded = try? JSONEncoder().encode(parameters) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }
}
