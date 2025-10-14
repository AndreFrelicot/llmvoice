    //
    //  DeviceCapabilities.swift
    //  VoiceTranscription
    //
    //  Created by André Frélicot on 2025-10-11
    //

import UIKit
import Speech
import os.log

/// Utilities for checking device capabilities
enum DeviceCapabilities {
    private static let logger = Logger(subsystem: "dev.andrefrelicot.llmvoice", category: "DeviceCapabilities")

    /// Check if the current device supports MLX Swift
    /// MLX requires iOS 16+ and specific Metal GPU capabilities
    /// Known compatible: iPhone 12 and later, iPad Pro with M1/M2, iPad Air 5th gen+
    /// Known incompatible: iPad Pro 2018 (A12X/A12Z), iPhone 11 and earlier
    static let supportsMLX: Bool = {
        #if targetEnvironment(simulator)
        // MLX not available on simulator
        return false
        #else

        // Check iOS version first
        guard #available(iOS 16.0, *) else {
            logger.warning("⚠️ MLX requires iOS 16+")
            return false
        }

        // Get device identifier
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0)
            }
        }

        guard let identifier = modelCode else {
            logger.warning("⚠️ Could not determine device model")
            return false
        }

        logger.info("📱 Device identifier: \(identifier)")

        // Parse device type and version
        // Format: iPhone12,1 or iPad8,1
        let components = identifier.split(separator: ",")
        guard let devicePart = components.first else { return false }

        // Extract device type and major version
        let deviceType = devicePart.prefix(while: { !$0.isNumber })
        let versionString = devicePart.drop(while: { !$0.isNumber })
        guard let majorVersion = Int(versionString) else { return false }

        logger.info("📱 Device type: \(deviceType), Major version: \(majorVersion)")

        // Check compatibility based on device type
        switch deviceType {
        case "iPhone":
            // iPhone 12 and later (iPhone13,x) support MLX
            // iPhone 11 and earlier do not
            let isCompatible = majorVersion >= 13
            if !isCompatible {
                logger.warning("⚠️ iPhone \(majorVersion) does not support MLX (requires iPhone 12+)")
            }
            return isCompatible

        case "iPad":
            // iPad Pro 2018 models (iPad8,x) with A12X/A12Z do NOT support MLX
            // These lack required Metal features (air.simd_sum, rmsfloat16)
            // iPad Pro 2020+ with A12Z and iPad Pro with M1/M2 DO support MLX

            // iPad8,x = iPad Pro 2018 (A12X/A12Z) - NOT compatible
            // iPad13,x = iPad Pro 2021 (M1) - compatible
            // iPad14,x = iPad Pro 2022 (M2) - compatible
            // iPad13,1/2 = iPad Air 5th gen (M1) - compatible

            if majorVersion == 8 {
                logger.warning("⚠️ iPad Pro 2018 (A12X/A12Z) does not support MLX")
                logger.warning("⚠️ Missing Metal features: air.simd_sum, rmsfloat16 kernel")
                return false
            }

            // M1/M2 iPads (version 13+) are compatible
            let isCompatible = majorVersion >= 13
            if !isCompatible {
                logger.warning("⚠️ iPad \(majorVersion) may not support MLX")
            }
            return isCompatible

        default:
            // Unknown device type - be conservative
            logger.warning("⚠️ Unknown device type: \(deviceType)")
            return false
        }
        #endif
    }()

    /// Get a user-friendly message explaining why MLX is not supported
    static var mlxUnsupportedReason: String {
        #if targetEnvironment(simulator)
        return "MLX requires a physical device with Metal GPU support. Please test on a real device."
        #else

        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0)
            }
        }

        guard let identifier = modelCode else {
            return "Could not determine device compatibility."
        }

        let components = identifier.split(separator: ",")
        guard let devicePart = components.first else {
            return "Device does not support MLX."
        }

        let deviceType = devicePart.prefix(while: { !$0.isNumber })
        let versionString = devicePart.drop(while: { !$0.isNumber })
        guard let majorVersion = Int(versionString) else {
            return "Device does not support MLX."
        }

        switch deviceType {
        case "iPhone":
            if majorVersion < 13 {
                return "MLX requires iPhone 12 or later. Your device (iPhone \(majorVersion)) does not have the required Metal GPU features."
            }
        case "iPad":
            if majorVersion == 8 {
                return "iPad Pro 2018 models do not support MLX due to missing Metal GPU features (air.simd_sum, rmsfloat16). MLX requires iPad Pro 2021 or later, or iPad Air 5th gen or later."
            } else if majorVersion < 13 {
                return "MLX requires iPad Pro 2021 (M1) or later, or iPad Air 5th gen or later. Your device may not have the required Metal GPU features."
            }
        default:
            break
        }

        return "Your device does not support the Metal GPU features required by MLX."
        #endif
    }

    /// Get device model name (human-readable)
    static var deviceModelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0)
            }
        }

        // Map common identifiers to names
        let modelMap: [String: String] = [
            // iPad Pro 2018
            "iPad8,1": "iPad Pro 11-inch (2018)",
            "iPad8,2": "iPad Pro 11-inch (2018)",
            "iPad8,3": "iPad Pro 11-inch (2018)",
            "iPad8,4": "iPad Pro 11-inch (2018)",
            "iPad8,5": "iPad Pro 12.9-inch (3rd gen, 2018)",
            "iPad8,6": "iPad Pro 12.9-inch (3rd gen, 2018)",
            "iPad8,7": "iPad Pro 12.9-inch (3rd gen, 2018)",
            "iPad8,8": "iPad Pro 12.9-inch (3rd gen, 2018)",

            // iPad Pro 2020
            "iPad8,9": "iPad Pro 11-inch (2nd gen, 2020)",
            "iPad8,10": "iPad Pro 11-inch (2nd gen, 2020)",
            "iPad8,11": "iPad Pro 12.9-inch (4th gen, 2020)",
            "iPad8,12": "iPad Pro 12.9-inch (4th gen, 2020)",

            // iPad Pro 2021 (M1)
            "iPad13,4": "iPad Pro 11-inch (3rd gen, M1)",
            "iPad13,5": "iPad Pro 11-inch (3rd gen, M1)",
            "iPad13,6": "iPad Pro 11-inch (3rd gen, M1)",
            "iPad13,7": "iPad Pro 11-inch (3rd gen, M1)",
            "iPad13,8": "iPad Pro 12.9-inch (5th gen, M1)",
            "iPad13,9": "iPad Pro 12.9-inch (5th gen, M1)",
            "iPad13,10": "iPad Pro 12.9-inch (5th gen, M1)",
            "iPad13,11": "iPad Pro 12.9-inch (5th gen, M1)",
        ]

        guard let code = modelCode else { return "Unknown" }
        return modelMap[code] ?? code
    }

    /// Check if SpeechTranscriber supports any locales on this device
    /// Returns tuple: (isSupported, supportedLocalesList)
    @available(iOS 26.0, *)
    static func checkSpeechTranscriberSupport() async -> (isSupported: Bool, locales: [Locale]) {
        logger.info("🔍 Checking SpeechTranscriber support on device")

        let supportedLocales = await SpeechTranscriber.supportedLocales
        logger.info("📋 SpeechTranscriber supported locales: \(supportedLocales.map { $0.identifier }.joined(separator: ", "))")

        let isSupported = !supportedLocales.isEmpty

        if !isSupported {
            logger.warning("⚠️ SpeechTranscriber does not support any locales on this device")
            logger.warning("⚠️ Device: \(deviceModelName)")
            logger.warning("⚠️ This may indicate hardware limitations similar to MLX")
        }

        return (isSupported, Array(supportedLocales))
    }

    /// Get a user-friendly message explaining why SpeechTranscriber is not supported
    static var speechTranscriberUnsupportedReason: String {
        let device = deviceModelName

        if device.contains("2018") {
            return "SpeechTranscriber API does not support any locales on \(device). This device lacks the hardware capabilities required for the new speech recognition features in iOS 26. Please use a newer device (iPhone 12+, iPad Pro 2021+, or iPad Air 5th gen+)."
        }

        return "SpeechTranscriber API does not support any locales on this device (\(device)). The new speech recognition features require specific hardware capabilities."
    }
}
