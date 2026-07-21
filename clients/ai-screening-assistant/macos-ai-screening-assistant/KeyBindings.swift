import Foundation
import AppKit

struct KeyBindings: Codable, Equatable {
    var toggleKey = "'"
    var captureKey = "."
    var toggleModifiers = ["command", "option", "shift"]
    var captureModifiers = ["command", "option", "shift"]
}

enum Modifier: String, CaseIterable {
    case command = "command"
    case option = "option"
    case shift = "shift"
    case control = "control"
    case function = "function"

    var symbol: String {
        switch self {
        case .command:  return "\u{2318}"
        case .option:   return "\u{2325}"
        case .shift:    return "\u{21E7}"
        case .control:  return "\u{2303}"
        case .function: return "fn"
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
        case "function": flags.insert(.function)
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
        let bundleID = Bundle.main.bundleIdentifier ?? "br.eti.elio.macos-ai-screening-assistant"
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
