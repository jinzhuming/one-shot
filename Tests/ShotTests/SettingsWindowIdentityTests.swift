import AppKit
import Testing
@testable import Shot

@Test @MainActor func settingsSceneConfiguresItsOwnWindowWithoutAHelper() {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    window.contentView = SettingsIdentityView()
    #expect(SettingsWindowIdentity.matches(identifier: window.identifier?.rawValue))
    #expect(window.title == String(localized: "设置"))
    #expect(!window.isRestorable)
    #expect(!SettingsWindowIdentity.matches(identifier: "shot.settings-helper"))
    #expect(!SettingsWindowIdentity.matches(identifier: "NSStatusItemWindow"))
}
