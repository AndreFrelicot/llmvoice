# LLMVoice

Real-time voice transcription and AI summarization for iOS/macOS.

## Overview

LLMVoice combines Apple's latest speech recognition APIs with on-device LLM inference to transcribe and summarize voice recordings in real-time. Built for iOS 26+ using Swift 6, it runs entirely on-device with no network calls.

## Features

- **Real-time Transcription**: Progressive speech-to-text using iOS 26's SpeechTranscriber
- **Multi-language Support**: Transcribe in English, Spanish, French, German, Italian, Portuguese, and more
- **On-device LLM**: Summarize transcriptions using MLX-powered models (Qwen, Llama, Phi)
- **Streaming Generation**: Watch AI summaries appear token-by-token with live metrics
- **Apple Intelligence Fallback**: Uses Apple's Writing Tools API when available
- **Model Management**: Download and manage multiple LLM models
- **Performance Metrics**: Track tokens/second, generation time, and model performance

## Requirements

- iOS 26.0+ / macOS 15.0+
- Xcode 16+
- Swift 6
- Device with A12 Bionic or newer for MLX models
- Device with Apple Neural Engine for Apple Intelligence

## Tech Stack

- **Speech Recognition**: SpeechTranscriber, SpeechAnalyzer (iOS 26 SDK)
- **Audio Processing**: AVAudioEngine, AVFoundation
- **LLM Inference**: [MLX Swift](https://github.com/ml-explore/mlx-swift)
- **Model Loading**: [swift-transformers](https://github.com/huggingface/swift-transformers)
- **UI**: SwiftUI with Observable macro
- **Architecture**: MVVM with MainActor isolation

## Building

1. Clone the repository:
   ```bash
   git clone https://github.com/AndreFrelicot/llmvoice.git
   cd LLMVoice
   ```

2. Open in Xcode:
   ```bash
   open LLMVoice.xcodeproj
   ```

3. Select your target device/simulator (iOS 26+)

4. Build and run (⌘R)

## Project Structure

```
LLMVoice/
├── Managers/
│   ├── AudioManager.swift              # Audio capture
│   ├── TranscriptionManager.swift      # Speech-to-text
│   ├── SummarizationManager.swift      # AI summarization
│   └── MLXSummarizationManager.swift   # MLX model inference
├── ViewModels/
│   └── RecordingViewModel.swift        # Main app state
├── Views/
│   ├── ContentView.swift               # Main UI
│   ├── SummariesListView.swift         # Results list
│   └── ModelPickerView.swift           # Model selection
└── Models/
    ├── MLXModel.swift                  # Model definitions
    └── Summary.swift                   # Data models
```

## Supported Models

- **Qwen 2.5** (0.5B) - 150MB, 29+ languages, 32k context - Recommended
- **Gemma 3** (1B) - 300MB, 140+ languages, 32k context
- **Llama 3.2** (1B) - 500MB, 8 languages
- Custom MLX-compatible models via Hugging Face

## License

MIT License - see LICENSE file for details

## Attribution

Built with:
- [MLX Swift](https://github.com/ml-explore/mlx-swift) by Apple ML Research
- [swift-transformers](https://github.com/huggingface/swift-transformers) by Hugging Face
- Apple's SpeechTranscriber API (iOS 26 SDK)

---

**Note**: This app requires iOS 26 beta SDK. Speech transcription and on-device AI features require compatible hardware.
