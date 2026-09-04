import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate {
    static let shared = AppCoordinator()

    private var statusItem: NSStatusItem?
    private var onboardingWindow: NSWindow?
    private var settingsPresentation: Task<Void, Never>?
    private var settingsPresentationGeneration = 0
    private var isPresentingSettings = false
    private var windowCloseObserver: NSObjectProtocol?

    func start() {
        NSApp.setActivationPolicy(.accessory)
        observeWindowCloses()
        dismissLaunchSettingsPlaceholder()
        setupStatusItem()
        HotkeyCenter.shared.register()
        PermissionService.shared.refresh()
        if PermissionService.shared.hasScreenRecording {
            WindowCatalog.prewarm()
        }
        if !AppSettings.shared.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func startCapture(_ mode: CaptureMode) {
        statusItem?.menu?.cancelTracking()
        // Let the status-item menu finish closing before changing the
        // activation policy or presenting capture windows. This matters
        // especially when the settings window just changed the app from
        // regular back to accessory.
        Task { @MainActor in
            await Task.yield()
            CaptureSession.shared.begin(mode)
        }
    }

    func toggleRecording() {
        statusItem?.menu?.cancelTracking()
        CaptureSession.shared.toggleRecording()
    }

    func hideUtilityWindows() {
        settingsPresentation?.cancel()
        settingsPresentation = nil
        isPresentingSettings = false
        PermissionService.shared.stopPolling()
        onboardingWindow?.orderOut(nil)
        Self.settingsWindows().forEach { $0.orderOut(nil) }
        restoreAccessoryPolicyIfIdle()
    }

    func showSettings() {
        // Full-screen capture chrome sits above a normal Settings window.
        if CaptureSession.shared.phase == .capturing, !CaptureSession.shared.isRecording {
            CaptureSession.shared.cancel()
        }

        settingsPresentation?.cancel()
        settingsPresentationGeneration += 1
        let generation = settingsPresentationGeneration
        isPresentingSettings = true
        becomeRegularApp()

        settingsPresentation = Task { @MainActor in
            defer {
                if settingsPresentationGeneration == generation {
                    isPresentingSettings = false
                }
            }
            // Status item menus finish tracking on the next turn; accessory
            // apps also need a Dock icon before macOS will key a window.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            becomeRegularApp()
            let settingsSelector = Selector(("showSettingsWindow:"))
            let knownWindows = Set(NSApp.windows.map { ObjectIdentifier($0) })
            _ = NSApp.sendAction(settingsSelector, to: nil, from: nil)

            // SwiftUI creates the Settings scene lazily and first tags it with
            // `com_apple_SwiftUI_Settings_window`. Retry until that window
            // exists, then pin our identifier and bring it forward.
            for attempt in 0..<24 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                if let window = Self.findSettingsWindow() ?? createdSettingsWindow(excluding: knownWindows) {
                    Self.configure(window)
                    Self.reveal(window)
                    return
                }
                if attempt < 23 {
                    _ = NSApp.sendAction(settingsSelector, to: nil, from: nil)
                }
            }
            restoreAccessoryPolicyIfIdle()
        }
    }

    func showAbout() {
        becomeRegularApp()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Shot",
            .credits: NSAttributedString(
                string: String(localized: "菜单栏截图工具"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ])
        NSApp.windows
            .filter { $0.className.contains("About") || $0.title == "Shot" }
            .forEach { $0.orderFrontRegardless() }
        NSApp.setActivationPolicy(.accessory)
    }

    func showOnboarding() {
        becomeRegularApp()
        if onboardingWindow == nil {
            let hosting = NSHostingController(rootView: OnboardingView(onFinished: { [weak self] in
                AppSettings.shared.hasCompletedOnboarding = true
                self?.destroyOnboardingWindow()
            }))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "欢迎使用 Shot")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 520, height: 460))
            window.isReleasedWhenClosed = false
            window.delegate = self
            onboardingWindow = window
        }
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.orderFrontRegardless()
        NSApp.setActivationPolicy(.accessory)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === onboardingWindow {
            AppSettings.shared.hasCompletedOnboarding = true
            PermissionService.shared.stopPolling()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if Self.isSettingsWindow(window) {
            // The Settings scene owns the window; the coordinator only
            // restores the menu-bar activation policy after AppKit has
            // actually ordered it out.
            DispatchQueue.main.async { [weak self] in
                self?.restoreAccessoryPolicyIfIdle()
            }
            return
        }
        guard window === onboardingWindow else { return }
        AppSettings.shared.hasCompletedOnboarding = true
        PermissionService.shared.stopPolling()
        onboardingWindow = nil
        window.contentViewController = nil
        restoreAccessoryPolicyIfIdle()
    }

    func restoreAccessoryPolicyIfIdle() {
        if isPresentingSettings { return }
        let hasTitledWindow = NSApp.windows.contains { window in
            window.isVisible
                && window.level <= .floating
                && window.canBecomeKey
                && window.styleMask.contains(.titled)
                && window.frame.width > 50
        }
        if !hasTitledWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func destroyOnboardingWindow() {
        PermissionService.shared.stopPolling()
        guard let window = onboardingWindow else { return }
        onboardingWindow = nil
        window.delegate = nil
        window.contentViewController = nil
        window.orderOut(nil)
        window.close()
        restoreAccessoryPolicyIfIdle()
    }

    private func observeWindowCloses() {
        guard windowCloseObserver == nil else { return }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                AppCoordinator.shared.handlePossibleSettingsClose(window)
            }
        }
    }

    private func handlePossibleSettingsClose(_ window: NSWindow) {
        guard Self.isSettingsWindow(window) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.restoreAccessoryPolicyIfIdle()
        }
    }

    private func dismissLaunchSettingsPlaceholder() {
        Self.settingsWindows().forEach { $0.orderOut(nil) }
    }

    private func becomeRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createdSettingsWindow(excluding knownWindows: Set<ObjectIdentifier>) -> NSWindow? {
        NSApp.windows.first { window in
            !knownWindows.contains(ObjectIdentifier(window))
                && window !== onboardingWindow
                && window.title != "Shot"
                && window.title != String(localized: "欢迎使用 Shot")
                && window.styleMask.contains(.titled)
                && window.canBecomeKey
                && window.frame.width > 1
        }
    }

    private static func settingsWindows() -> [NSWindow] {
        NSApp.windows.filter(isSettingsWindow)
    }

    private static func findSettingsWindow() -> NSWindow? {
        settingsWindows().first
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        SettingsWindowIdentity.matches(
            identifier: window.identifier?.rawValue,
            autosaveName: window.frameAutosaveName
        )
    }

    private static func configure(_ window: NSWindow) {
        window.title = String(localized: "设置")
        window.identifier = NSUserInterfaceItemIdentifier(SettingsWindowIdentity.identifier)
        window.minSize = NSSize(width: 520, height: 400)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
    }

    private static func reveal(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // Accessory apps sometimes still lose the ordering race; float briefly.
        window.level = .floating
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard window.isVisible else { return }
            window.level = .normal
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shot")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        item.button?.image = image
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "Shot"
        item.isVisible = true
        item.menu = StatusItemMenu.build()
        statusItem = item
    }

    func reloadStatusMenu() {
        statusItem?.menu = StatusItemMenu.build()
    }
}
