import AppKit
import Testing
@testable import ShotKit

@Test func hotkeyRoundTripAndDisplayOrder() throws {
    let hotkey = Hotkey.defaultAllInOne
    let data = try JSONEncoder().encode(hotkey)
    let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
    #expect(decoded == hotkey)
    #expect(hotkey.keyCode == 0)
    #expect(hotkey.character == "a")
    #expect(hotkey.displayString == "⌃⌘A")
    #expect(hotkey.carbonModifiers != 0)
    #expect(Hotkey.defaultRecording.displayString == "⇧⌘6")
}

@Test func overlayToggleHotkeyMatchesAndReservesKeys() {
    let space = Hotkey.defaultAreaWindowToggle
    #expect(space.keyCode == 49)
    #expect(space.displayKey == "Space")
    #expect(space.matches(keyCode: 49, modifierRaw: 0))
    let caps = NSEvent.ModifierFlags.capsLock.rawValue
    #expect(space.matches(keyCode: 49, modifierRaw: caps))
    #expect(!space.matches(keyCode: 49, modifierRaw: NSEvent.ModifierFlags.shift.rawValue))
    #expect(!space.isReservedOverlayShortcut)
    #expect(Hotkey(keyCode: 53, modifierRaw: 0, character: "").isReservedOverlayShortcut)
    #expect(Hotkey(keyCode: 48, modifierRaw: 0, character: "").isReservedOverlayShortcut)
    #expect(Hotkey(keyCode: 36, modifierRaw: 0, character: "").isReservedOverlayShortcut)
    let optionW = Hotkey(
        keyCode: 13,
        modifierRaw: NSEvent.ModifierFlags.option.rawValue,
        character: "w"
    )
    #expect(optionW.matches(keyCode: 13, modifierRaw: NSEvent.ModifierFlags.option.rawValue))
    #expect(!optionW.conflicts(with: space))
}

@Test func hotkeyRejectsSystemScreenshotAndDetectsConflict() {
    let commandShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
    let three = Hotkey(keyCode: 20, modifierRaw: commandShift, character: "3")
    let four = Hotkey(keyCode: 21, modifierRaw: commandShift, character: "4")
    let five = Hotkey(keyCode: 23, modifierRaw: commandShift, character: "5")
    #expect(three.isSystemScreenshotShortcut)
    #expect(four.isSystemScreenshotShortcut)
    #expect(five.isSystemScreenshotShortcut)
    #expect(!Hotkey.defaultAllInOne.isSystemScreenshotShortcut)
    let controlCommand = NSEvent.ModifierFlags([.control, .command]).rawValue
    let same = Hotkey(keyCode: 0, modifierRaw: controlCommand, character: "a")
    #expect(Hotkey.defaultAllInOne.conflicts(with: same))
    #expect(!Hotkey.defaultAllInOne.conflicts(with: three))
}

@Test func capturePhaseMachineTransitions() {
    var machine = CapturePhaseMachine()
    #expect(machine.phase == .idle)
    #expect(!machine.isBusy)
    machine.startCapture()
    #expect(machine.phase == .capturing)
    #expect(machine.isBusy)
    machine.startEditing()
    #expect(machine.phase == .editing)
    machine.reset()
    #expect(machine.phase == .idle)
    machine.startCapture()
    machine.reset()
    #expect(machine.phase == .idle)
}

@Test func lastRegionHotkeyDoesNotConflictWithSystemScreenshot() {
    let lastRegion = Hotkey.defaultCapturePreviousRegion
    #expect(lastRegion.displayString == "⌃⌘L")
    #expect(!lastRegion.isSystemScreenshotShortcut)
    let commandShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
    #expect(!lastRegion.conflicts(with: Hotkey(keyCode: 20, modifierRaw: commandShift, character: "3")))
    #expect(!lastRegion.conflicts(with: Hotkey(keyCode: 21, modifierRaw: commandShift, character: "4")))
    #expect(!lastRegion.conflicts(with: Hotkey(keyCode: 23, modifierRaw: commandShift, character: "5")))
    #expect(!lastRegion.conflicts(with: Hotkey.defaultAllInOne))
    #expect(!lastRegion.conflicts(with: Hotkey.defaultScrolling))
}
