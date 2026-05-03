import SwiftUI
import Combine

enum RecordingMode: String, CaseIterable {
    case audio = "Audio"
    case video = "Video"
    case url = "URL"
}

enum AudioFormat: String, CaseIterable {
    case m4a = "M4A"
    case wav = "WAV"
}

enum VideoFormat: String, CaseIterable {
    case mov = "MOV"
    case mp4 = "MP4"
}

enum RecordingError: Error, LocalizedError {
    case noDisplayFound
    case noAppSelected
    case noWindowSelected
    case permissionDenied
    case writerFailed(String)
    case streamStoppedExternally

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No se encontró display"
        case .noAppSelected: return "No hay app seleccionada"
        case .noWindowSelected: return "No hay ventana seleccionada"
        case .permissionDenied: return "Permiso de grabación denegado"
        case .writerFailed(let msg): return "Error de grabación: \(msg)"
        case .streamStoppedExternally: return "La grabación fue detenida desde el indicador de macOS"
        }
    }
}

@MainActor
class RecordingState: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingMode: RecordingMode = .audio
    @Published var selectedAudioFormat: AudioFormat = .m4a
    @Published var selectedVideoFormat: VideoFormat = .mov
    @Published var urlInput: String = ""
    @Published var urlStatus: String?
    @Published var timerEnabled = false
    @Published var timerHours: Int = 0
    @Published var timerMinutes: Int = 5
    @Published var timerSeconds: Int = 0
    @Published var errorMessage: String?
    @Published var lastSavedURL: URL?

    @Published var brewUpdateStatus: String?
    @Published var brewUpdateError: String?
    @Published var brewUpdateSuccessVersion: String?

    var onTimerExpired: (() -> Void)?

    var timerLimit: TimeInterval? {
        guard timerEnabled else { return nil }
        let total = TimeInterval(timerHours * 3600 + timerMinutes * 60 + timerSeconds)
        return total > 0 ? total : nil
    }

    private var timer: Timer?

    func startTimer() {
        recordingDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.recordingDuration += 0.1
                if let limit = self.timerLimit, self.recordingDuration >= limit {
                    self.onTimerExpired?()
                }
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    var remainingTime: String? {
        guard let limit = timerLimit else { return nil }
        let remaining = max(0, limit - recordingDuration)
        let totalSeconds = Int(remaining)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "-%d:%02d:%02d", h, m, s)
        }
        return String(format: "-%02d:%02d", m, s)
    }

    var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((recordingDuration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
