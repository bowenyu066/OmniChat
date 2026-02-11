import SwiftUI
import AVFoundation

/// A button that records audio and transcribes it to text using OpenAI
struct AudioRecorderButton: View {
    var onTranscriptionComplete: (String) -> Void
    @Binding var isExpanded: Bool  // Exposed so parent can adjust layout

    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var errorMessage: String?
    @State private var showError = false

    // Waveform visualization
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 50)
    @State private var levelTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    @State private var durationTimer: Timer?

    private let transcriptionService = TranscriptionService.shared

    var body: some View {
        if isRecording {
            recordingView
        } else {
            micButton
        }
    }

    // MARK: - Mic Button (Idle State)

    private var micButton: some View {
        Button(action: startRecording) {
            ZStack {
                if isTranscribing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(transcriptionService.isConfigured ? Color.secondary : Color.secondary.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing || !transcriptionService.isConfigured)
        .help(isTranscribing ? "Transcribing..." : (transcriptionService.isConfigured ? "Start voice input" : "OpenAI API key required"))
        .alert("Transcription Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Recording View (Active Recording State)

    private var recordingView: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button(action: cancelRecording) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel recording")

            // Waveform visualization
            WaveformView(levels: audioLevels)
                .frame(height: 32)
                .frame(maxWidth: .infinity)

            // Duration
            Text(formatDuration(recordingDuration))
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)

            // Stop/Submit button
            Button(action: stopRecording) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary))
            }
            .buttonStyle(.plain)
            .help("Stop and transcribe")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Recording Controls

    private func startRecording() {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        beginRecording()
                    } else {
                        showErrorMessage("Microphone access denied. Please enable in System Settings.")
                    }
                }
            }

        case .denied, .restricted:
            showErrorMessage("Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone.")

        @unknown default:
            showErrorMessage("Unknown microphone permission status")
        }
    }

    private func beginRecording() {
        // Create temp file URL for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "omnichat_recording_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordingURL = fileURL

        // Configure audio session
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            isExpanded = true
            recordingDuration = 0

            // Reset waveform
            audioLevels = Array(repeating: 0.1, count: 50)

            // Start level metering timer
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                updateAudioLevel()
            }

            // Start duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingDuration += 1
            }
        } catch {
            showErrorMessage("Failed to start recording: \(error.localizedDescription)")
            cleanupRecording()
        }
    }

    private func stopRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            isRecording = false
            isExpanded = false
            return
        }

        recorder.stop()
        stopTimers()
        isRecording = false
        isExpanded = false

        // Transcribe the recorded audio
        guard let url = recordingURL else {
            showErrorMessage("No recording found")
            return
        }

        Task {
            await transcribeAudio(at: url)
        }
    }

    private func cancelRecording() {
        audioRecorder?.stop()
        stopTimers()
        isRecording = false
        isExpanded = false
        cleanupRecording()
    }

    private func stopTimers() {
        levelTimer?.invalidate()
        levelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)

        // Convert dB to normalized value (0-1)
        // Power typically ranges from -160 (silence) to 0 (max)
        let normalizedPower = max(0, min(1, (power + 50) / 50))
        let level = CGFloat(normalizedPower)

        // Shift levels and add new one
        audioLevels.removeFirst()
        audioLevels.append(max(0.1, level))  // Minimum height for visibility
    }

    private func transcribeAudio(at url: URL) async {
        isTranscribing = true
        defer {
            isTranscribing = false
            cleanupRecording()
        }

        do {
            let audioData = try Data(contentsOf: url)

            // Check file size (max 25MB for OpenAI)
            guard audioData.count < 25 * 1024 * 1024 else {
                showErrorMessage("Recording too long. Maximum file size is 25MB.")
                return
            }

            let transcribedText = try await transcriptionService.transcribe(audioData: audioData, format: "m4a")

            if !transcribedText.isEmpty {
                onTranscriptionComplete(transcribedText)
            }
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func cleanupRecording() {
        audioRecorder = nil

        // Delete temp file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Waveform Visualization

struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<levels.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 2, height: max(2, levels[index] * geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AudioRecorderButton(onTranscriptionComplete: { text in
            print("Transcribed: \(text)")
        }, isExpanded: .constant(false))

        // Preview of recording state
        HStack(spacing: 12) {
            Button(action: {}) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            WaveformView(levels: (0..<50).map { _ in CGFloat.random(in: 0.1...0.8) })
                .frame(height: 32)
                .frame(maxWidth: .infinity)

            Text("0:11")
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)

            Button(action: {}) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    .padding()
    .frame(width: 400)
}
