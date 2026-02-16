import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var floatingWindow: NSWindow?
    var recordingState: RecordingState!

    func applicationDidFinishLaunching(_ notification: Notification) {
        recordingState = RecordingState()

        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "AudioCapture")
            button.action = #selector(toggleWindow(_:))
            button.target = self
        }

        // Show floating window immediately
        showFloatingWindow()
    }

    func showFloatingWindow() {
        if let existing = floatingWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MenuBarView().environmentObject(recordingState)
        let hostingView = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingView
        window.title = "AudioCapture"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.center()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        floatingWindow = window

        // Switch back to accessory after showing, so it doesn't stay in Dock
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func toggleWindow(_ sender: AnyObject?) {
        if let window = floatingWindow, window.isVisible {
            window.orderOut(nil)
        } else {
            showFloatingWindow()
        }
    }
}
