enum SettingsWindowIdentity {
    static let identifier = "shot.settings"
    static let swiftUIIdentifier = "com_apple_SwiftUI_Settings_window"

    static func matches(identifier: String?, autosaveName: String = "") -> Bool {
        if identifier == Self.identifier || identifier == Self.swiftUIIdentifier {
            return true
        }
        if let identifier, identifier.contains("SwiftUI_Settings") || identifier.contains("SwiftUI.Settings") {
            return true
        }
        return autosaveName.contains("SwiftUI_Settings")
            || autosaveName.contains("SwiftUI.Settings")
            || autosaveName == swiftUIIdentifier
    }
}
