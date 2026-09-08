import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate {
    static let shared = AppCoordinator()

    private var onboardingWindow: NSWindow?
    private var openSettingsAction: OpenSettingsAction?
    private var settingsPresentation: Task<Void, Never>?
    private var settingsPresentationGeneration = 0
    private var isPresentingSettings = false
    private var captureStartTask: Task<Void, Never>?
    private var resignDebounceTask: Task<Void, Never>?
    private var windowCloseObserver: NSObjectProtocol?
    private var applicationResignObserver: NSObjectProtocol?

    func start() {
        clearRestoredPlaceholderFrames()
        hideHelperWindow()
        NSApp.setActivationPolicy(.accessory)
        observeWindowCloses()
        observeApplicationDeactivation()
        dismissLaunchSettingsPlaceholder()
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
        // Let the status-item menu finish closing before changing the
        // activation policy or presenting capture windows. This matters
        // especially when the settings window just changed the app from
        // regular back to accessory.
        scheduleCaptureStart {
            CaptureSession.shared.begin(mode)
        }
    }

    func toggleRecording() {
        CaptureSession.shared.toggleRecording()
    }

    func startScrollingCapture() {
        scheduleCaptureStart {
            CaptureSession.shared.beginScrolling()
        }
    }

    func hideUtilityWindows() {
        captureStartTask?.cancel()
        captureStartTask = nil
        settingsPresentation?.cancel()
        settingsPresentation = nil
        isPresentingSettings = false
        PermissionService.shared.stopPolling()
        onboardingWindow?.orderOut(nil)
        Self.settingsWindows().forEach { $0.orderOut(nil) }
        hideHelperWindow()
        restoreAccessoryPolicyIfIdle()
    }

    func installOpenSettingsAction(_ action: OpenSettingsAction) {
        openSettingsAction = action
    }

    func showSettings(using action: OpenSettingsAction? = nil) {
        // Full-screen capture chrome sits above a normal Settings window.
        captureStartTask?.cancel()
        captureStartTask = nil
        if CaptureSession.shared.phase == .capturing, !CaptureSession.shared.isRecording {
            CaptureSession.shared.cancel()
        }

        if let action {
            openSettingsAction = action
        }
        guard let openSettingsAction else { return }

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
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            becomeRegularApp()
            let knownWindows = Set(NSApp.windows.map { ObjectIdentifier($0) })
            openSettingsAction()

            // SwiftUI creates the Settings scene lazily. Retry until that
            // window exists, then pin our identifier and bring it forward.
            for attempt in 0..<24 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                if let window = Self.findSettingsWindow() ?? createdSettingsWindow(excluding: knownWindows) {
                    Self.configure(window)
                    Self.reveal(window)
                    hideHelperWindow()
                    return
                }
                if attempt < 23 {
                    if attempt == 3 {
                        SettingsPresenter.shared.requestOpen()
                    }
                    openSettingsAction()
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.windows
                .filter(Self.isAboutWindow)
                .forEach { window in
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            hideHelperWindow()
        }
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
        hideHelperWindow()
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
        if Self.isSettingsWindow(window) || Self.isAboutWindow(window) {
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
                && !SettingsWindowIdentity.isHelper(identifier: window.identifier?.rawValue)
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
                AppCoordinator.shared.handleUtilityWindowClose(window)
            }
        }
    }

    private func observeApplicationDeactivation() {
        guard applicationResignObserver == nil else { return }
        applicationResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppCoordinator.shared.handleApplicationResign()
            }
        }
    }

    private func scheduleCaptureStart(_ action: @escaping @MainActor () -> Void) {
        captureStartTask?.cancel()
        captureStartTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            action()
            if !Task.isCancelled {
                captureStartTask = nil
            }
        }
    }

    private func handleApplicationResign() {
        resignDebounceTask?.cancel()
        resignDebounceTask = Task { @MainActor in
            // Menu-bar tracking and activation policy changes can produce
            // a short-lived resign/activate pair while capture starts.
            // Only treat a sustained loss of activation as an external
            // escape from the selection session.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            resignDebounceTask = nil
            guard !NSApp.isActive else { return }
            guard !CaptureSession.shared.isNonactivatingScreenshotCapture else { return }
            // A screenshot selection is an intentionally modal desktop
            // interaction. If the app loses activation, releasing its
            // full-screen capture chrome is safer than leaving an input
            // shield above another application. Nonactivating screenshot
            // panels are excluded because remaining inactive is their
            // intentional behavior; recording is excluded separately because
            // its overlay has already been dismissed and the stream is
            // allowed to continue in the background.
            guard CaptureSession.shared.phase == .capturing,
                  !CaptureSession.shared.hasRecordingActivity,
                  !CaptureSession.shared.isScrollingCapture else { return }
            CaptureSession.shared.cancel()
        }
    }

    private func handleUtilityWindowClose(_ window: NSWindow) {
        guard Self.isSettingsWindow(window) || Self.isAboutWindow(window) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.restoreAccessoryPolicyIfIdle()
        }
    }

    private func dismissLaunchSettingsPlaceholder() {
        Self.settingsWindows().forEach { $0.orderOut(nil) }
        hideHelperWindow()
    }

    private func clearRestoredPlaceholderFrames() {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(SettingsWindowIdentity.swiftUIIdentifier)")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(SettingsWindowIdentity.helperIdentifier)")
    }

    private func becomeRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideHelperWindow() {
        NSApp.windows
            .filter { SettingsWindowIdentity.isHelper(identifier: $0.identifier?.rawValue) }
            .forEach { window in
                window.alphaValue = 0
                window.ignoresMouseEvents = true
                window.setFrame(NSRect(x: -10_000, y: -10_000, width: 1, height: 1), display: false)
            }
    }

    private func createdSettingsWindow(excluding knownWindows: Set<ObjectIdentifier>) -> NSWindow? {
        NSApp.windows.first { window in
            !knownWindows.contains(ObjectIdentifier(window))
                && window !== onboardingWindow
                && !SettingsWindowIdentity.isHelper(identifier: window.identifier?.rawValue)
                && !Self.isAboutWindow(window)
                && window.styleMask.contains(.titled)
                && window.canBecomeKey
                && window.frame.width > 50
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

    private static func isAboutWindow(_ window: NSWindow) -> Bool {
        window.className.contains("About")
            || (window.title == "Shot" && window.styleMask.contains(.titled) && window.frame.width > 50)
    }

    private static func configure(_ window: NSWindow) {
        window.title = String(localized: "设置")
        window.identifier = NSUserInterfaceItemIdentifier(SettingsWindowIdentity.identifier)
        window.minSize = NSSize(width: 520, height: 400)
        window.isRestorable = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
    }

    private static func reveal(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = NSSize(
                width: max(window.frame.width, 520),
                height: max(window.frame.height, 420)
            )
            window.setFrame(
                NSRect(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
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

}
