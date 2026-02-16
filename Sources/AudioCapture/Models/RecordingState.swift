import SwiftUI
import Combine

enum RecordingMode: String, CaseIterable {
    case audio = "Solo Audio"
    case video = "Video + Audio"
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
    @Published var errorMessage: String?
    @Published var lastSavedURL: URL?

    private var timer: Timer?

    func startTimer() {
        recordingDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((recordingDuration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
