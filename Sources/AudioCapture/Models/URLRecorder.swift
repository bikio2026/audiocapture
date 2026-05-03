import Foundation
import AVFoundation

@MainActor
class URLRecorder: ObservableObject {
    private var process: Process?
    private var outputURL: URL?
    private var playerRecordingTask: Task<URL?, Error>?
    private var currentURL: URL?

    static func ytdlpPath() -> String? {
        let paths = ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"]
        return paths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    // MARK: - Download with yt-dlp

    func downloadWithYtdlp(urlString: String, format: AudioFormat, onStatus: @escaping (String) -> Void) async throws -> URL {
        guard let ytdlp = URLRecorder.ytdlpPath() else {
            throw RecordingError.writerFailed("yt-dlp no encontrado. Instalalo con: brew install yt-dlp")
        }

        guard let url = URL(string: urlString) else {
            throw RecordingError.writerFailed("URL inválida")
        }

        currentURL = url
        let outputDir = AudioFileManager.defaultOutputDirectory
        let ext = format == .m4a ? "m4a" : "wav"
        let outputTemplate = outputDir.appendingPathComponent("url_%(title)s_%(id)s.\(ext)").path

        onStatus("Conectando...")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.environment = ProcessEnvironment.enrichedPATH()

        var args = [
            "-x",
            "--no-playlist",
            "--newline",  // progress on separate lines for parsing
            "-o", outputTemplate
        ]

        if format == .m4a {
            args += ["--audio-format", "m4a"]
        } else {
            args += ["--audio-format", "wav"]
        }

        args.append(urlString)
        proc.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.process = proc

        // Read stdout in real-time for progress
        let statusCallback = onStatus
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            // Parse yt-dlp progress lines like "[download]  45.2% of 5.23MiB at 1.2MiB/s"
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("[download]") {
                // Extract percentage
                if let range = trimmed.range(of: #"\d+\.?\d*%"#, options: .regularExpression) {
                    let pct = String(trimmed[range])
                    Task { @MainActor in
                        statusCallback("Descargando: \(pct)")
                    }
                }
            } else if trimmed.contains("[ExtractAudio]") || trimmed.contains("Post-process") {
                Task { @MainActor in
                    statusCallback("Convirtiendo audio...")
                }
            } else if trimmed.contains("Destination:") || trimmed.contains("[info]") {
                Task { @MainActor in
                    statusCallback("Descargando audio...")
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { [weak self] process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self?.process = nil
                    if process.terminationStatus == 0 {
                        if let file = self?.findLatestFile(in: outputDir, ext: ext) {
                            continuation.resume(returning: file)
                        } else {
                            continuation.resume(throwing: RecordingError.writerFailed("No se encontró el archivo descargado"))
                        }
                    } else {
                        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderr = String(data: data, encoding: .utf8) ?? ""
                        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        let combined = (stderr + stdout).trimmingCharacters(in: .whitespacesAndNewlines)
                        let msg = combined.isEmpty ? "Error desconocido de yt-dlp" : String(combined.prefix(300))
                        continuation.resume(throwing: RecordingError.writerFailed(msg))
                    }
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: RecordingError.writerFailed("No se pudo ejecutar yt-dlp: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Record with AVPlayer (direct URLs)

    func recordWithAVPlayer(urlString: String, format: AudioFormat, onStatus: @escaping (String) -> Void) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw RecordingError.writerFailed("URL inválida")
        }

        currentURL = url
        onStatus("Conectando...")

        let outputURL = AudioFileManager.outputURL(format: format)
        self.outputURL = outputURL

        let asset = AVURLAsset(url: url)

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw RecordingError.writerFailed("La URL no contiene audio reproducible")
        }

        onStatus("Exportando audio...")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingError.writerFailed("No se pudo crear la sesión de exportación")
        }

        let m4aURL = format == .m4a ? outputURL : outputURL.deletingPathExtension().appendingPathExtension("m4a")
        exportSession.outputURL = m4aURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status == .completed {
            if format == .wav {
                let wavURL = outputURL
                let convertProc = Process()
                convertProc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
                convertProc.arguments = ["-f", "WAVE", "-d", "LEI16", m4aURL.path, wavURL.path]
                try convertProc.run()
                convertProc.waitUntilExit()
                try? FileManager.default.removeItem(at: m4aURL)
                return wavURL
            }
            return m4aURL
        } else {
            let errorMsg = exportSession.error?.localizedDescription ?? "Error desconocido"
            throw RecordingError.writerFailed("Exportación falló: \(errorMsg)")
        }
    }

    // MARK: - Auto-detect and record

    func record(urlString: String, format: AudioFormat, onStatus: @escaping (String) -> Void) async throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmed) != nil else {
            throw RecordingError.writerFailed("URL inválida")
        }

        // Always try yt-dlp first — it supports 1000+ sites
        if URLRecorder.ytdlpPath() != nil {
            do {
                return try await downloadWithYtdlp(urlString: trimmed, format: format, onStatus: onStatus)
            } catch let ytdlpError {
                // AVPlayer sólo abre URLs directas a archivos de audio, no páginas web.
                // Para youtube/soundcloud/etc. el fallback es ruido — el error real es el de yt-dlp.
                if Self.isWebPageURL(trimmed) {
                    throw ytdlpError
                }
                do {
                    return try await recordWithAVPlayer(urlString: trimmed, format: format, onStatus: onStatus)
                } catch {
                    throw ytdlpError
                }
            }
        }
        return try await recordWithAVPlayer(urlString: trimmed, format: format, onStatus: onStatus)
    }

    private static func isWebPageURL(_ urlString: String) -> Bool {
        let hosts = ["youtube.com", "youtu.be", "soundcloud.com", "vimeo.com",
                     "twitter.com", "x.com", "tiktok.com", "spotify.com",
                     "twitch.tv", "instagram.com", "facebook.com", "dailymotion.com"]
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }

    func cancel() {
        process?.terminate()
        process = nil
        playerRecordingTask?.cancel()
        playerRecordingTask = nil
    }

    // MARK: - Helpers

    private func findLatestFile(in directory: URL, ext: String) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return nil
        }
        return files
            .filter { $0.pathExtension == ext }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return dateA > dateB
            }
            .first
    }
}
