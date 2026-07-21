import XCTest
@testable import macos_ai_screening_assistant

@MainActor
final class KeyBindingsTests: XCTestCase {

    private func withController<T>(resetToDefaults: Bool = true, _ block: () throws -> T) rethrows -> T {
        let saved = KeyBindingsController.shared.current
        if resetToDefaults {
            KeyBindingsController.shared.save(KeyBindings())
        }
        defer { KeyBindingsController.shared.save(saved) }
        return try block()
    }

    // MARK: - KeyBindings Codable

    func testDefaultValues() {
        let b = KeyBindings()
        XCTAssertEqual(b.toggleKey, "'")
        XCTAssertEqual(b.captureKey, ".")
        XCTAssertEqual(b.toggleModifiers, ["command", "option", "shift"])
        XCTAssertEqual(b.captureModifiers, ["command", "option", "shift"])
    }

    func testCodableRoundTrip() throws {
        let original = KeyBindings(
            toggleKey: "x",
            captureKey: "z",
            toggleModifiers: ["command", "control"],
            captureModifiers: ["option", "shift", "function"]
        )
        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(KeyBindings.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableWithEmptyModifiers() throws {
        let original = KeyBindings(toggleKey: "a", captureKey: "b", toggleModifiers: [], captureModifiers: [])
        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(KeyBindings.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableAllModifiers() throws {
        let all: [String] = ["command", "option", "shift", "control", "function"]
        let original = KeyBindings(toggleKey: "t", captureKey: "s", toggleModifiers: all, captureModifiers: all)
        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(KeyBindings.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - KeyBindingsController

    func testControllerDefaults() {
        withController {
            let ctrl = KeyBindingsController.shared
            let b = ctrl.current
            XCTAssertEqual(b.toggleKey, "'")
            XCTAssertEqual(b.captureKey, ".")
        }
    }

    func testControllerSaveAndRead() {
        withController {
            let ctrl = KeyBindingsController.shared
            let newBindings = KeyBindings(toggleKey: "q", captureKey: "w", toggleModifiers: ["control"], captureModifiers: ["command"])
            ctrl.save(newBindings)
            XCTAssertEqual(ctrl.current, newBindings)
        }
    }

    // MARK: - Modifier enum

    func testModifierSymbols() {
        XCTAssertEqual(Modifier.command.symbol, "\u{2318}")
        XCTAssertEqual(Modifier.option.symbol, "\u{2325}")
        XCTAssertEqual(Modifier.shift.symbol, "\u{21E7}")
        XCTAssertEqual(Modifier.control.symbol, "\u{2303}")
        XCTAssertEqual(Modifier.function.symbol, "fn")
    }

    func testModifierAllCasesCount() {
        XCTAssertEqual(Modifier.allCases.count, 5)
    }

    func testModifierRawValues() {
        XCTAssertEqual(Modifier.command.rawValue, "command")
        XCTAssertEqual(Modifier.option.rawValue, "option")
        XCTAssertEqual(Modifier.shift.rawValue, "shift")
        XCTAssertEqual(Modifier.control.rawValue, "control")
        XCTAssertEqual(Modifier.function.rawValue, "function")
    }

    // MARK: - modifierFlags

    func testModifierFlagsAll() {
        let all = ["command", "option", "shift", "control", "function"]
        let flags = modifierFlags(all)
        XCTAssertTrue(flags.contains(.command))
        XCTAssertTrue(flags.contains(.option))
        XCTAssertTrue(flags.contains(.shift))
        XCTAssertTrue(flags.contains(.control))
        XCTAssertTrue(flags.contains(.function))
    }

    func testModifierFlagsSubset() {
        let flags = modifierFlags(["command", "control"])
        XCTAssertTrue(flags.contains(.command))
        XCTAssertTrue(flags.contains(.control))
        XCTAssertFalse(flags.contains(.option))
        XCTAssertFalse(flags.contains(.shift))
        XCTAssertFalse(flags.contains(.function))
    }

    func testModifierFlagsEmpty() {
        let flags = modifierFlags([])
        XCTAssertTrue(flags.isEmpty)
    }

    func testModifierFlagsInvalidStrings() {
        let flags = modifierFlags(["command", "invalid", "shift"])
        XCTAssertEqual(flags, [.command, .shift])
    }

    func testModifierFlagsOrderIndependent() {
        let a = modifierFlags(["command", "option", "shift"])
        let b = modifierFlags(["shift", "command", "option"])
        XCTAssertEqual(a, b)
    }

    // MARK: - SystemShortcutConflict

    func testConflictForD() {
        let warning = SystemShortcutConflict.warning(for: "d")
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.contains("Dock"))
    }

    func testConflictForDUppercase() {
        let warning = SystemShortcutConflict.warning(for: "D")
        XCTAssertNotNil(warning)
    }

    func testNoConflictForDefaultKeys() {
        XCTAssertNil(SystemShortcutConflict.warning(for: "'"))
        XCTAssertNil(SystemShortcutConflict.warning(for: "."))
        XCTAssertNil(SystemShortcutConflict.warning(for: "t"))
        XCTAssertNil(SystemShortcutConflict.warning(for: "a"))
    }

    func testNoConflictForUncommonKeys() {
        for key in ["x", "z", "j", "k", "1", "2", " ", "-"] {
            XCTAssertNil(SystemShortcutConflict.warning(for: key), "Key '\(key)' should not produce a conflict warning")
        }
    }

    func testConflictForDWithDifferentCase() {
        XCTAssertNotNil(SystemShortcutConflict.warning(for: "d"))
        XCTAssertNotNil(SystemShortcutConflict.warning(for: "D"))
    }

    // MARK: - Integration: modifierFlags + KeyBindings

    func testToggleModifiersRoundTrip() {
        let b = KeyBindings()
        let flags = modifierFlags(b.toggleModifiers)
        XCTAssertTrue(flags.contains(.command))
        XCTAssertTrue(flags.contains(.option))
        XCTAssertTrue(flags.contains(.shift))
    }

    func testCustomModifierRoundTrip() {
        let b = KeyBindings(toggleKey: "x", captureKey: "y", toggleModifiers: ["control", "function"], captureModifiers: ["option"])
        let toggleFlags = modifierFlags(b.toggleModifiers)
        let captureFlags = modifierFlags(b.captureModifiers)
        XCTAssertTrue(toggleFlags.contains(.control))
        XCTAssertTrue(toggleFlags.contains(.function))
        XCTAssertFalse(toggleFlags.contains(.command))
        XCTAssertTrue(captureFlags.contains(.option))
        XCTAssertFalse(captureFlags.contains(.command))
    }

    // MARK: - Menu bar icon toggle

    func testToggleHidesMenuBarIcon() {
        withController {
            let manager = MenuBarLifecycleManager(testing: true)
            XCTAssertTrue(manager.showingIcon, "Icon should start visible")

            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command, .option, .shift],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "'", charactersIgnoringModifiers: "'",
                isARepeat: false, keyCode: 39
            )!

            manager.handleKeyEvent(event)
            XCTAssertFalse(manager.showingIcon, "Icon should be hidden after toggle")
        }
    }

    func testToggleUnhidesMenuBarIcon() {
        withController {
            let manager = MenuBarLifecycleManager(testing: true)
            XCTAssertTrue(manager.showingIcon)

            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command, .option, .shift],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "'", charactersIgnoringModifiers: "'",
                isARepeat: false, keyCode: 39
            )!

            manager.handleKeyEvent(event)
            XCTAssertFalse(manager.showingIcon, "Icon should be hidden after first toggle")
            manager.handleKeyEvent(event)
            XCTAssertTrue(manager.showingIcon, "Icon should be visible after second toggle")
        }
    }

    func testToggleWithWrongKeybindingDoesNothing() {
        withController {
            let manager = MenuBarLifecycleManager(testing: true)
            XCTAssertTrue(manager.showingIcon)

            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command, .option],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "x", charactersIgnoringModifiers: "x",
                isARepeat: false, keyCode: 7
            )!

            manager.handleKeyEvent(event)
            XCTAssertTrue(manager.showingIcon, "Icon should remain visible when binding doesn't match")
        }
    }

    func testToggleWorksWithUpdatedKeybindings() {
        withController {
            let customBindings = KeyBindings(
                toggleKey: "t", captureKey: ".",
                toggleModifiers: ["control", "shift"],
                captureModifiers: ["command", "option", "shift"]
            )
            KeyBindingsController.shared.save(customBindings)

            let manager = MenuBarLifecycleManager(testing: true)
            XCTAssertTrue(manager.showingIcon)

            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.control, .shift],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "t", charactersIgnoringModifiers: "t",
                isARepeat: false, keyCode: 17
            )!

            manager.handleKeyEvent(event)
            XCTAssertFalse(manager.showingIcon, "Icon should hide with updated keybinding")
            manager.handleKeyEvent(event)
            XCTAssertTrue(manager.showingIcon, "Icon should reappear with second toggle")
        }
    }

    func testToggleWithUpdatedKeybindingAndWrongModifiersDoesNothing() {
        withController {
            let customBindings = KeyBindings(
                toggleKey: "t", captureKey: ".",
                toggleModifiers: ["control", "shift"],
                captureModifiers: ["command", "option", "shift"]
            )
            KeyBindingsController.shared.save(customBindings)

            let manager = MenuBarLifecycleManager(testing: true)
            XCTAssertTrue(manager.showingIcon)

            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command, .shift],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "t", charactersIgnoringModifiers: "t",
                isARepeat: false, keyCode: 17
            )!
            manager.handleKeyEvent(event)
            XCTAssertTrue(manager.showingIcon, "Wrong modifiers should not trigger toggle")

            let wrongKeyEvent = NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.control, .shift],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "r", charactersIgnoringModifiers: "r",
                isARepeat: false, keyCode: 15
            )!
            manager.handleKeyEvent(wrongKeyEvent)
            XCTAssertTrue(manager.showingIcon, "Wrong key should not trigger toggle")
        }
    }
}
