import SwiftUI
import AppKit
import Combine
import ScreeningShared

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

enum SystemShortcutConflict {
    private static let reserved: Set<String> = ["d"]

    static func warning(for key: String) -> String? {
        guard reserved.contains(key.lowercased()) else { return nil }
        switch key.lowercased() {
        case "d": return "⚠ ⌘⌥⇧D is reserved by macOS for Show/Hide Dock"
        default:  return "⚠ This key may conflict with a macOS system shortcut"
        }
    }
}

private final class LogStore: ObservableObject {
    static let shared = LogStore()
    @Published private(set) var entries: [String] = []

    func log(_ message: String, attributes: [String: String] = [:]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        entries.append("[\(timestamp)] \(message)")
        OtelTracer.shared.log(message, attributes: attributes)
    }

    func clear() {
        entries.removeAll()
    }
}

@main
struct ScreeningAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuLifecycle = MenuBarLifecycleManager()
    @State private var bindings = KeyBindingsController.shared.current
    @StateObject private var webSocketManager = WebSocketClientManager()
    @State private var showLocalAnalysis = UserDefaults.standard.bool(forKey: "showLocalAnalysis")

    init() {
        setupOpenTelemetryPipeline()
        if UserDefaults.standard.object(forKey: "Screenshots.saveToDisk") != nil {
            ScreenshotStore.shared.saveToDisk = UserDefaults.standard.bool(forKey: "Screenshots.saveToDisk")
        }
    }

    var body: some Scene {
        Settings {
            VStack(spacing: 14) {
                Text("Screening Assistant Settings")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    keybindingSection(
                        label: "Toggle Menu Bar Icon",
                        key: $bindings.toggleKey,
                        modifiers: $bindings.toggleModifiers
                    )

                    keybindingSection(
                        label: "Screen Frame Capture",
                        key: $bindings.captureKey,
                        modifiers: $bindings.captureModifiers
                    )

                    keybindingSection(
                        label: "Area Selection Capture",
                        key: $bindings.areaCaptureKey,
                        modifiers: $bindings.areaCaptureModifiers
                    )
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("App Display Name:")
                        .font(.subheadline).bold()
                    TextField("Assistant", text: $bindings.displayName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: bindings.displayName) { _, _ in
                            KeyBindingsController.shared.save(bindings)
                        }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Analysis Prompt:")
                        .font(.subheadline).bold()
                    TextEditor(text: $bindings.analysisPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 80)
                        .border(Color(nsColor: .separatorColor), width: 0.5)
                        .cornerRadius(4)
                        .onChange(of: bindings.analysisPrompt) { _, _ in
                            KeyBindingsController.shared.save(bindings)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("WebSocket Server URL:")
                        .font(.subheadline).bold()
                    TextField("ws://localhost:8000/ws/analysis", text: $bindings.webSocketURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: bindings.webSocketURL) { _, newURL in
                            KeyBindingsController.shared.save(bindings)
                            if let url = URL(string: newURL) {
                                webSocketManager.reconnect(to: url)
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Screenshot Storage Path:")
                        .font(.subheadline).bold()
                    HStack(spacing: 6) {
                        TextField("~/Library/Application Support/...", text: $bindings.screenshotStoragePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button("Browse…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            panel.message = "Choose screenshot storage folder"
                            panel.directoryURL = URL(fileURLWithPath: bindings.screenshotStoragePath)
                            if panel.runModal() == .OK, let url = panel.url {
                                bindings.screenshotStoragePath = url.path
                                KeyBindingsController.shared.save(bindings)
                                ScreenshotStore.shared.changeStorageDirectory(to: url)
                            }
                        }
                        .fixedSize()
                    }
                    .onChange(of: bindings.screenshotStoragePath) { _, newPath in
                        KeyBindingsController.shared.save(bindings)
                        let url = URL(fileURLWithPath: newPath)
                        ScreenshotStore.shared.changeStorageDirectory(to: url)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Capture Mode:")
                        .font(.subheadline).bold()
                    Picker("", selection: $bindings.captureMode) {
                        ForEach(CaptureMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: bindings.captureMode) { _, _ in
                        KeyBindingsController.shared.save(bindings)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Visual Effects (Area Selection):")
                        .font(.subheadline).bold()
                    Toggle("Show Selection Border", isOn: $bindings.showSelectionBorder)
                        .onChange(of: bindings.showSelectionBorder) { _, _ in
                            KeyBindingsController.shared.save(bindings)
                        }
                    Toggle("Flash Screen on Capture", isOn: $bindings.flashScreenOnCapture)
                        .onChange(of: bindings.flashScreenOnCapture) { _, _ in
                            KeyBindingsController.shared.save(bindings)
                        }
                    Toggle("Show Crosshair Cursor", isOn: $bindings.showCrosshair)
                        .onChange(of: bindings.showCrosshair) { _, _ in
                            KeyBindingsController.shared.save(bindings)
                        }
                }

                Divider()

                Toggle("Show AI analysis results locally", isOn: $showLocalAnalysis)
                    .onChange(of: showLocalAnalysis) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "showLocalAnalysis")
                        if newValue {
                            AnalysisResultsWindowController.shared.show()
                        } else {
                            AnalysisResultsWindowController.shared.hide()
                        }
                    }

                Button("Kill Agent") { NSApp.terminate(nil) }
            }
            .padding()
            .frame(width: 400, height: 880)
        }
    }

    @ViewBuilder
    private func keybindingSection(label: String, key: Binding<String>, modifiers: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("• \(label):")
            HStack(spacing: 4) {
                ForEach(Modifier.allCases, id: \.rawValue) { mod in
                    let isOn = modifiers.wrappedValue.contains(mod.rawValue)
                    Button(mod.symbol) {
                        if isOn {
                            modifiers.wrappedValue.removeAll { $0 == mod.rawValue }
                        } else {
                            modifiers.wrappedValue.append(mod.rawValue)
                        }
                        KeyBindingsController.shared.save(bindings)
                    }
                    .buttonStyle(.bordered)
                    .tint(isOn ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    .controlSize(.small)
                }
                TextField("", text: key)
                    .frame(width: 36)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .onChange(of: key.wrappedValue) { _, newValue in
                        if let lastChar = newValue.last {
                            key.wrappedValue = String(lastChar).lowercased()
                        }
                        KeyBindingsController.shared.save(bindings)
                    }
            }
            SystemShortcutConflict.warning(for: key.wrappedValue).map { warning in
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func setupOpenTelemetryPipeline() {
        let tracer = OtelTracer.shared
        LogStore.shared.log("[OTel] Initializing OpenTelemetry tracer SDK provider...", attributes: ["otel.init": "true"])
        let span = tracer.startSpan("app.startup", attributes: ["component": "application"])
        tracer.log("OpenTelemetry pipeline initialized", severity: "INFO", severityNumber: 9, attributes: ["otel.init": "complete"])
        tracer.endSpan(span, status: .ok)
    }
}

class MenuBarLifecycleManager: NSObject, ObservableObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private(set) var showingIcon: Bool = true
    private var windowObserver: AnyCancellable?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var logsWindow: NSWindow?
    lazy var captureManager = ScreenCaptureManager()

    init(testing: Bool = false) {
        super.init()
        guard !testing else { return }
        mountMenuBarIcon()
        attachKeyboardHooks()
        setupSettingsWindowFocusTrap()
    }

    deinit {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        windowObserver?.cancel()
    }

    private func mountMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let actionBtn = statusItem?.button {
            actionBtn.image = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: "Screening Service Monitor")

            let contextMenu = NSMenu()

            let statusIndicator = NSMenuItem(title: "Screening Node: Online (OTel Active)", action: nil, keyEquivalent: "")
            statusIndicator.isEnabled = false
            contextMenu.addItem(statusIndicator)
            contextMenu.addItem(NSMenuItem.separator())

            let analysisItem = NSMenuItem(title: "Show Analysis Results", action: #selector(openAnalysisResults), keyEquivalent: "a")
            analysisItem.target = self
            contextMenu.addItem(analysisItem)

            contextMenu.addItem(NSMenuItem.separator())

            let configItem = NSMenuItem()

            let bindings = KeyBindingsController.shared.current
            let modString = bindings.toggleModifiers.compactMap { Modifier(rawValue: $0) }.map(\.symbol).joined()

            let settingsButtonView = NSHostingView(rootView:
                SettingsLink {
                    HStack {
                        Text("Configure Keybindings...")
                        Spacer()
                        Text("\(modString)\(bindings.toggleKey.uppercased())").foregroundColor(.secondary).font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            )

            settingsButtonView.frame = NSRect(x: 0, y: 0, width: 240, height: 26)
            configItem.view = settingsButtonView
            configItem.action = #selector(menuItemTriggered)
            configItem.target = self

            contextMenu.addItem(configItem)

            let logsItem = NSMenuItem(title: "Show Application Logs", action: #selector(openLogsWindow), keyEquivalent: "l")
            logsItem.target = self
            contextMenu.addItem(logsItem)

            contextMenu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(title: "Quit Assistant", action: #selector(terminateApplication), keyEquivalent: "q")
            quitItem.target = self
            contextMenu.addItem(quitItem)

            statusItem?.menu = contextMenu
        }
    }

    private func setupSettingsWindowFocusTrap() {
        windowObserver = NotificationCenter.default
            .publisher(for: NSApplication.willUpdateNotification, object: NSApp)
            .sink { _ in
                let settingsWindows = NSApp.windows.filter { $0.title == "Settings" }
                for window in settingsWindows where !window.isKeyWindow {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
            }
    }

    @objc private func menuItemTriggered() {
        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow = NSApp.windows.first(where: { $0.title == "Settings" }) {
            settingsWindow.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor
    @objc private func openAnalysisResults() {
        NSApp.activate(ignoringOtherApps: true)
        AnalysisResultsWindowController.shared.show()
    }

    @objc private func openLogsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let logsWindow = logsWindow {
            logsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = .init("app-logs")
        window.title = "Application Logs"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: LogView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        logsWindow = window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @objc private func terminateApplication() {
        NSApp.terminate(nil)
    }

    private func attachKeyboardHooks() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleKeyEvent(event) else { return event }
            return nil
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let currentModifiers = event.modifierFlags.intersection(relevant)
        guard let keysPressed = event.charactersIgnoringModifiers?.lowercased() else { return false }

        let bindings = KeyBindingsController.shared.current
        let toggleMods = modifierFlags(bindings.toggleModifiers)
        let captureMods = modifierFlags(bindings.captureModifiers)
        let areaCaptureMods = modifierFlags(bindings.areaCaptureModifiers)

        if currentModifiers == toggleMods, keysPressed == bindings.toggleKey {
            toggleMenuVisibility()
            return true
        }
        if currentModifiers == captureMods, keysPressed == bindings.captureKey {
            dispatchScreenCapture()
            return true
        }
        if currentModifiers == areaCaptureMods, keysPressed == bindings.areaCaptureKey {
            dispatchAreaCapture()
            return true
        }
        return false
    }

    private func toggleMenuVisibility() {
        let span = OtelTracer.shared.startSpan("toggle.menu.visibility", attributes: [
            "component": "keyboard",
            "showing": "\(showingIcon)"
        ])
        showingIcon.toggle()
        if showingIcon {
            mountMenuBarIcon()
        } else {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
        }
        LogStore.shared.log("[Action] Menu icon visibility toggled to: \(showingIcon ? "visible" : "hidden")",
                            attributes: ["event": "menu_toggle", "visibility": "\(showingIcon)"])
        OtelTracer.shared.endSpan(span, status: .ok)
    }

    private func dispatchScreenCapture() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let span = OtelTracer.shared.startSpan("screen.capture.trigger", attributes: [
            "component": "keyboard",
            "action": "capture"
        ])
        Task { [weak self] in
            try? await self?.captureManager.captureAndStore()
        }
        LogStore.shared.log("[Trigger] Hotkey Activated: Initializing ScreenCaptureKit buffer payload pipeline...",
                            attributes: ["event": "screen_capture"])
        OtelTracer.shared.endSpan(span, status: .ok)
    }

    private func dispatchAreaCapture() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let span = OtelTracer.shared.startSpan("area.capture.trigger", attributes: [
            "component": "keyboard",
            "action": "area_capture"
        ])
        Task { [weak self] in
            try? await self?.captureManager.captureAndStore()
        }
        LogStore.shared.log("[Trigger] Hotkey Activated: Initializing area selection capture...",
                            attributes: ["event": "area_capture"])
        OtelTracer.shared.endSpan(span, status: .ok)
    }
}

private struct LogView: View {
    @ObservedObject private var store = LogStore.shared
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Clear") { store.clear() }
                    .font(.caption)
                SettingsLink {
                    Label("Preferences", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.entries.enumerated()), id: \.offset) { i, entry in
                            Text(entry)
                                .id(i)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .background(Color(.textBackgroundColor))
                .onChange(of: store.entries.count) { _, _ in
                    guard autoScroll else { return }
                    proxy.scrollTo(store.entries.count - 1, anchor: .bottom)
                }
            }
        }
    }
}
