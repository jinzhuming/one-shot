import AppKit
import SwiftUI

enum SettingsWindowIdentity {
    static let identifier = "shot.settings"
    static let swiftUIIdentifier = "com_apple_SwiftUI_Settings_window"
    static let helperIdentifier = "shot.settings-helper"

    static func isHelper(identifier: String?) -> Bool {
        identifier == helperIdentifier
    }

    static func matches(identifier: String?, autosaveName: String = "") -> Bool {
        if isHelper(identifier: identifier) { return false }
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

@MainActor
final class SettingsPresenter: ObservableObject {
    static let shared = SettingsPresenter()
    @Published private(set) var generation = 0

    func requestOpen() {
        generation += 1
    }
}

struct SettingsOpenProbe: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var presenter = SettingsPresenter.shared

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .background(HelperWindowConfigurator())
            .onAppear {
                if presenter.generation > 0 {
                    openSettings()
                }
            }
            .onChange(of: presenter.generation) { _, generation in
                guard generation > 0 else { return }
                openSettings()
            }
    }
}

private struct HelperWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.identifier = NSUserInterfaceItemIdentifier(SettingsWindowIdentity.helperIdentifier)
        window.title = ""
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .transient, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        // Keep the window in the scene graph. `orderOut` unmounts the SwiftUI
        // view and `@Environment(\.openSettings)` becomes a no-op.
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: 1, height: 1), display: false)
    }
}
