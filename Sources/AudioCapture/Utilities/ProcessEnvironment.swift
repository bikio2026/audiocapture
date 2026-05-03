import Foundation

enum ProcessEnvironment {
    // /usr/local/bin y /opt/homebrew/bin no están en el PATH heredado por launchd,
    // y herramientas como yt-dlp, ffmpeg, deno, brew viven ahí.
    static func enrichedPATH() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "/usr/local/bin:/opt/homebrew/bin"
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(extra):\(existing)"
        return env
    }
}
