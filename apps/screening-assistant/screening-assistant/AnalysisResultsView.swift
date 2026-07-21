import AppKit
import SwiftUI
import ScreeningShared

@MainActor
final class AnalysisResultsWindowController: NSObject {
    static let shared = AnalysisResultsWindowController()

    private var window: NSWindow?
    private let clientManager = WebSocketClientManager(
        serverURL: URL(string: KeyBindingsController.shared.current.webSocketURL)!
    )

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = AnalysisDisplayView(clientManager: clientManager)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = .init("analysis-results")
        window.title = "AI Analysis Results"
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = self

        self.window = window
        NSApp.activate(ignoringOtherApps: true)

        clientManager.connect()
    }

    func hide() {
        window?.orderOut(nil)
        clientManager.disconnect()
    }
}

extension AnalysisResultsWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        clientManager.disconnect()
        return false
    }
}
