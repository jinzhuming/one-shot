import AppKit
import Carbon

public struct Hotkey: Equatable, Codable, Sendable {
    public var keyCode: UInt16
    public var modifierRaw: UInt
    public var character: String

    public init(keyCode: UInt16, modifierRaw: UInt, character: String) {
        self.keyCode = keyCode
        self.modifierRaw = modifierRaw
        self.character = character
    }

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRaw)
    }

    public var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    public var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += displayKey
        return parts
    }

    public var displayKey: String {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "?" : trimmed.uppercased()
        }
    }

    public static let defaultAllInOne = Hotkey(
        keyCode: 0,
        modifierRaw: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        character: "a"
    )

    public static let defaultRecording = Hotkey(
        keyCode: 22,
        modifierRaw: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        character: "6"
    )

    public static let defaultAreaWindowToggle = Hotkey(
        keyCode: 49,
        modifierRaw: 0,
        character: " "
    )

    /// Command-Shift-3/4/5 are reserved by macOS screenshot.
    public var isSystemScreenshotShortcut: Bool {
        let mods = Self.significantModifiers(modifiers)
        guard mods == [.command, .shift] else { return false }
        return keyCode == 20 || keyCode == 21 || keyCode == 23
    }

    /// Esc / Tab / Return stay reserved for cancel, window cycling, and fullscreen confirm.
    public var isReservedOverlayShortcut: Bool {
        keyCode == 36 || keyCode == 48 || keyCode == 53
    }

    public func conflicts(with other: Hotkey) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    public func matches(keyCode: UInt16, modifierRaw: UInt) -> Bool {
        let eventMods = Self.significantModifiers(NSEvent.ModifierFlags(rawValue: modifierRaw))
        let selfMods = Self.significantModifiers(modifiers)
        return self.keyCode == keyCode && eventMods == selfMods
    }

    public func matches(_ event: NSEvent) -> Bool {
        matches(keyCode: event.keyCode, modifierRaw: event.modifierFlags.rawValue)
    }

    private static func significantModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }
}
