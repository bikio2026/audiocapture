import Foundation

@MainActor
class BrewUpdater: ObservableObject {
    static func brewPath() -> String? {
        let paths = ["/usr/local/bin/brew", "/opt/homebrew/bin/brew"]
        return paths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    func update(onStatus: @escaping (String) -> Void) async throws -> String {
        guard let brew = BrewUpdater.brewPath() else {
            throw RecordingError.writerFailed("Homebrew no encontrado")
        }
        onStatus("Iniciando brew upgrade...")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brew)
        proc.arguments = ["upgrade", "yt-dlp", "deno", "ffmpeg"]
        proc.environment = ProcessEnvironment.enrichedPATH()

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("Pouring") || trimmed.contains("Installing") {
                Task { @MainActor in onStatus("Instalando paquetes...") }
            } else if trimmed.contains("Downloading") || trimmed.contains("Fetching") {
                Task { @MainActor in onStatus("Descargando paquetes...") }
            } else if trimmed.contains("already installed") || trimmed.contains("up-to-date") {
                Task { @MainActor in onStatus("Verificando versiones...") }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { process in
                outPipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    if process.terminationStatus == 0 {
                        let version = (try? Self.readYtdlpVersion()) ?? "instalado"
                        continuation.resume(returning: version)
                    } else {
                        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        let msg = stderr.isEmpty ? "Error desconocido" : String(stderr.prefix(300))
                        continuation.resume(throwing: RecordingError.writerFailed(msg))
                    }
                }
            }
            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: RecordingError.writerFailed("No se pudo ejecutar brew: \(error.localizedDescription)"))
            }
        }
    }

    private static func readYtdlpVersion() throws -> String {
        guard let ytdlp = URLRecorder.ytdlpPath() else { return "instalado" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = ["--version"]
        proc.environment = ProcessEnvironment.enrichedPATH()
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "instalado"
    }
}
