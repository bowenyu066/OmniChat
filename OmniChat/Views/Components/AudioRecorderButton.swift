import SwiftUI
import AVFoundation

/// A button that records audio and transcribes it to text using OpenAI
struct AudioRecorderButton: View {
    var onTranscriptionComplete: (String) -> Void

    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var errorMessage: String?
    @State private var showError = false

    private let transcriptionService = TranscriptionService.shared

    var body: some View {
        Button(action: toggleRecording) {
            ZStack {
                if isTranscribing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(buttonColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing || !transcriptionService.isConfigured)
        .help(helpText)
        .alert("Transcription Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var buttonColor: Color {
        if !transcriptionService.isConfigured {
            return .secondary.opacity(0.5)
        }
        return isRecording ? .red : .secondary
    }

    private var helpText: String {
        if !transcriptionService.isConfigured {
            return "OpenAI API key required for voice input"
        }
        if isTranscribing {
            return "Transcribing..."
        }
        return isRecording ? "Stop recording" : "Start voice input"
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

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
            audioRecorder?.record()
            isRecording = true
        } catch {
            showErrorMessage("Failed to start recording: \(error.localizedDescription)")
            cleanupRecording()
        }
    }

    private func stopRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            isRecording = false
            return
        }

        recorder.stop()
        isRecording = false

        // Transcribe the recorded audio
        guard let url = recordingURL else {
            showErrorMessage("No recording found")
            return
        }

        Task {
            await transcribeAudio(at: url)
        }
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
}

// MARK: - Preview

#Preview {
    AudioRecorderButton { text in
        print("Transcribed: \(text)")
    }
    .padding()
}
