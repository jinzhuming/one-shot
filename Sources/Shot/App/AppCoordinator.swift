import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate {
    static let shared = AppCoordinator()

    private var onboardingWindow: NSWindow?
    private var openSettingsAction: OpenSettingsAction?
    private var settingsPresentation: Task<Void, Never>?
    private weak var settingsWindow: NSWindow?
    private var isPresentingSettings = false
    private var captureStartTask: Task<Void, Never>?
    private var resignDebounceTask: Task<Void, Never>?
    private var windowCloseObserver: NSObjectProtocol?
    private var applicationResignObserver: NSObjectProtocol?

    func start() {
        NSApp.setActivationPolicy(.accessory)
        observeWindowCloses()
        observeApplicationDeactivation()
        HotkeyCenter.shared.register()
        PermissionService.shared.refresh()
        AppLifecycle.shared.start()
        Task { await ScreenshotHistoryStore.repository.reconcile() }
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
        settingsWindow?.orderOut(nil)
        restoreAccessoryPolicyIfIdle()
    }

    func installOpenSettingsAction(_ action: OpenSettingsAction) {
        openSettingsAction = action
        if isPresentingSettings { showSettings() }
    }

    func settingsWindowDidAttach(_ window: NSWindow) {
        settingsWindow = window
        if isPresentingSettings {
            isPresentingSettings = false
            revealSettings(window)
        }
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
        isPresentingSettings = true
        guard let openSettingsAction else { return }
        settingsPresentation?.cancel()
        settingsPresentation = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.becomeRegularApp()
            openSettingsAction()
            if let window = self.settingsWindow {
                self.revealSettings(window)
            }
            self.isPresentingSettings = false
            self.settingsPresentation = nil
        }
    }

    private func revealSettings(_ window: NSWindow) {
        if let screen = CoordinateSpace.screen(containing: NSEvent.mouseLocation) {
            let frame = screen.visibleFrame
            window.setFrameOrigin(CGPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2
            ))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private func becomeRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == SettingsWindowIdentity.identifier
    }

    private static func isAboutWindow(_ window: NSWindow) -> Bool {
        window.className.contains("About")
            || (window.title == "Shot" && window.styleMask.contains(.titled) && window.frame.width > 50)
    }

}
