//
//  FloatingRecordButton.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import SwiftUI

struct FloatingRecordButton: View {
    let isRecording: Bool
    var isResolving: Bool = false
    var isDisabled: Bool = false
    var isReduced: Bool = false
    let action: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0

    // Size configuration based on reduced state
    private var buttonSize: CGFloat {
        isReduced ? 45 : 70
    }

    private var ringSize: CGFloat {
        isReduced ? 55 : 80
    }

    private var iconSize: CGFloat {
        isReduced ? 20 : 30
    }

    // Button color based on state
    private var buttonColor: Color {
        if isDisabled {
            return .gray
        } else if isResolving {
            return .orange
        } else if isRecording {
            return .red
        } else {
            return .blue
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Pulsing background ring (when recording)
                if isRecording && !isReduced {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(scale)
                        .opacity(2 - scale)
                }

                // Main button
                Circle()
                    .fill(buttonColor)
                    .frame(width: buttonSize, height: buttonSize)
                    .shadow(color: .black.opacity(0.2), radius: isReduced ? 4 : 8, x: 0, y: isReduced ? 2 : 4)

                // Icon
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isRecording)
                    .opacity(isDisabled ? 0.5 : 1.0)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(isResolving ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: rotationAngle)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startPulseAnimation()
            }
        }
        .onChange(of: isResolving) { _, newValue in
            if newValue {
                startSpinAnimation()
            } else {
                stopSpinAnimation()
            }
        }
        .sensoryFeedback(.impact, trigger: isRecording)
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            scale = 1.5
        }
    }

    private func startSpinAnimation() {
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }

    private func stopSpinAnimation() {
        withAnimation(.default) {
            rotationAngle = 0
        }
    }
}

#Preview("Not Recording") {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        FloatingRecordButton(isRecording: false) {
            print("Record tapped")
        }
    }
}

#Preview("Recording") {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        FloatingRecordButton(isRecording: true) {
            print("Stop tapped")
        }
    }
}
