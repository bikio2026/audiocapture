import ScreenCaptureKit
import AppKit

struct CaptureApp: Identifiable, Hashable {
    let id: String
    let name: String
    let app: SCRunningApplication

    init(_ app: SCRunningApplication) {
        self.id = app.bundleIdentifier
        self.name = app.applicationName
        self.app = app
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CaptureApp, rhs: CaptureApp) -> Bool {
        lhs.id == rhs.id
    }
}

struct CaptureWindow: Identifiable, Hashable {
    let id: UInt32
    let title: String
    let appName: String
    let window: SCWindow

    init(_ window: SCWindow) {
        self.id = window.windowID
        self.title = window.title ?? "Sin título"
        self.appName = window.owningApplication?.applicationName ?? "Desconocida"
        self.window = window
    }

    var displayName: String {
        if title.isEmpty || title == "Sin título" {
            return appName
        }
        return "\(appName) — \(title)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CaptureWindow, rhs: CaptureWindow) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class AppEnumerator: ObservableObject {
    @Published var availableApps: [CaptureApp] = []
    @Published var availableWindows: [CaptureWindow] = []
    @Published var selectedApp: CaptureApp?
    @Published var selectedWindow: CaptureWindow?
    @Published var errorMessage: String?

    func refreshApps() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let ownBundleID = Bundle.main.bundleIdentifier ?? ""
            availableApps = content.applications
                .filter { $0.bundleIdentifier != ownBundleID && !$0.applicationName.isEmpty }
                .map { CaptureApp($0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Windows: only on-screen, with reasonable size, exclude our own
            availableWindows = content.windows
                .filter { window in
                    guard let app = window.owningApplication else { return false }
                    return app.bundleIdentifier != ownBundleID
                        && window.isOnScreen
                        && window.frame.width > 100
                        && window.frame.height > 100
                }
                .map { CaptureWindow($0) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            errorMessage = nil
        } catch {
            errorMessage = "Sin permiso de grabación. Ve a Ajustes > Privacidad > Grabación de pantalla y activa AudioCapture."
            availableApps = []
            availableWindows = []
        }
    }
}
