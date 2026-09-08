import AppKit
import SwiftUI

enum SettingsWindowIdentity {
    static let identifier = "shot.settings"
    static func matches(identifier: String?) -> Bool { identifier == Self.identifier }
}

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsIdentityView { SettingsIdentityView() }
    func updateNSView(_ view: SettingsIdentityView, context: Context) { view.configure() }
}

final class SettingsIdentityView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    func configure() {
        guard let window else { return }
        window.title = String(localized: "设置")
        window.identifier = NSUserInterfaceItemIdentifier(SettingsWindowIdentity.identifier)
        window.minSize = NSSize(width: 520, height: 400)
        window.isRestorable = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
        AppCoordinator.shared.settingsWindowDidAttach(window)
    }
}
