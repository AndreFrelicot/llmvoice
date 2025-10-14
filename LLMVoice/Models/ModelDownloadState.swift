//
//  ModelDownloadState.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import Foundation

/// Represents the download state of an ML model
enum ModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)
}
