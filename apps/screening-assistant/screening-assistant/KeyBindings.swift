import Foundation
import AppKit

struct KeyBindings: Codable, Equatable {
    var toggleKey = "'"
    var toggleModifiers = ["command", "option", "shift"]
    var captureKey = "."
    var captureModifiers = ["command", "option", "shift"]
    var areaCaptureKey = ","
    var areaCaptureModifiers = ["command", "option", "shift"]
    var analysisPrompt = "Describe what you see in this screenshot, paying attention to UI elements, text content, layout, and any highlighted or selected items."
    var webSocketURL = "ws://localhost:8000/ws/analysis"
    var displayName = "Assistant"
    var screenshotStoragePath = KeyBindings.defaultScreenshotPath
    var captureMode: CaptureMode = .fullScreen
    var showSelectionBorder = false
    var flashScreenOnCapture = false
    var showCrosshair = false

    private static var defaultScreenshotPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "br.eti.elio.screening-assistant"
        return appSupport.appendingPathComponent("\(bundleID)/screenshots").path
    }
}

enum CaptureMode: String, Codable, CaseIterable {
    case fullScreen = "full"
    case areaSelection = "area"

    var label: String {
        switch self {
        case .fullScreen: return "Full Screen"
        case .areaSelection: return "Area Selection"
        }
    }
}

enum Modifier: String, CaseIterable {
    case command
    case option
    case shift
    case control

    var symbol: String {
        switch self {
        case .command:  return "\u{2318}"
        case .option:   return "\u{2325}"
        case .shift:    return "\u{21E7}"
        case .control:  return "\u{2303}"
        }
    }
}

func modifierFlags(_ mods: [String]) -> NSEvent.ModifierFlags {
    mods.reduce(into: []) { flags, m in
        switch m {
        case "command":  flags.insert(.command)
        case "option":   flags.insert(.option)
        case "shift":    flags.insert(.shift)
        case "control":  flags.insert(.control)
        default: break
        }
    }
}

final class KeyBindingsController {
    static let shared = KeyBindingsController()
    private let fileURL: URL
    private(set) var current: KeyBindings

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "br.eti.elio.screening-assistant"
        let appDir = appSupport.appendingPathComponent(bundleID)
        fileURL = appDir.appendingPathComponent("keybindings.plist")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        current = (try? PropertyListDecoder().decode(KeyBindings.self, from: Data(contentsOf: fileURL))) ?? KeyBindings()
    }

    func save(_ bindings: KeyBindings) {
        current = bindings
        guard let data = try? PropertyListEncoder().encode(bindings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
