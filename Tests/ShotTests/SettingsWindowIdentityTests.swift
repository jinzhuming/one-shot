import Testing
@testable import Shot

@Test func settingsWindowIdentityMatchesSwiftUIAndShotIdentifiers() {
    #expect(SettingsWindowIdentity.identifier == "shot.settings")
    #expect(SettingsWindowIdentity.matches(identifier: "shot.settings"))
    #expect(SettingsWindowIdentity.matches(identifier: "com_apple_SwiftUI_Settings_window"))
    #expect(SettingsWindowIdentity.matches(identifier: "com_apple_SwiftUI_Settings_window_1"))
    #expect(SettingsWindowIdentity.matches(identifier: "SwiftUI.Settings.Window"))
    #expect(SettingsWindowIdentity.matches(
        identifier: nil,
        autosaveName: "com_apple_SwiftUI_Settings_window"
    ))
    #expect(!SettingsWindowIdentity.matches(identifier: nil))
    #expect(!SettingsWindowIdentity.matches(identifier: "shot.settings-helper"))
    #expect(!SettingsWindowIdentity.matches(identifier: "NSStatusItemWindow"))
}
