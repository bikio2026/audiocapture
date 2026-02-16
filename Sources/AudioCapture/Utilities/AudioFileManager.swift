import Foundation

struct AudioFileManager {
    static var defaultOutputDirectory: URL {
        let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        let dir = (musicDir ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("AudioCapture", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    static func outputURL(format: AudioFormat) -> URL {
        let ext = format == .m4a ? "m4a" : "wav"
        let name = "recording_\(dateFormatter.string(from: Date())).\(ext)"
        return defaultOutputDirectory.appendingPathComponent(name)
    }

    static func videoOutputURL(format: VideoFormat) -> URL {
        let ext = format == .mov ? "mov" : "mp4"
        let name = "video_\(dateFormatter.string(from: Date())).\(ext)"
        return defaultOutputDirectory.appendingPathComponent(name)
    }
}
