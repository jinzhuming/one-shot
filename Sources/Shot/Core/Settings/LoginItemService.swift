import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class LoginItemService: ObservableObject {
    static let shared = LoginItemService()

    @Published private(set) var isEnabled: Bool

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            let status = SMAppService.mainApp.status
            if enabled {
                if status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}
