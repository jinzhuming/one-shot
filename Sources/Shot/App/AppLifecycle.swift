import AppKit

/// One owner for system observers and the memory pressure source. No polling
/// runs while the menu bar app is idle.
@MainActor
final class AppLifecycle {
    static let shared = AppLifecycle()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pressure: DispatchSourceMemoryPressure?
    private var suspensionTask: Task<Void, Never>?
    private(set) var isSuspended = false

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(name, center: workspace) { $0.suspend() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(name, center: workspace) { $0.resume() }
        }
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { _ in
            CaptureSession.shared.relayoutForCurrentScreens()
            PinController.shared.relayoutForCurrentScreens()
            WindowCatalog.shared.releaseCachedContent()
        }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler {
            Task { @MainActor in
                if CaptureSession.shared.phase == .idle { WindowCatalog.shared.releaseCachedContent() }
                ScreenshotHistoryStore.repository.releasePendingImages()
                Diagnostics.lifecycle.notice("Released reconstructible caches after memory pressure")
            }
        }
        pressure.resume()
        self.pressure = pressure
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, action: @escaping (AppLifecycle) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; action(self) }
        }
        observers.append((center, observer))
    }

    private func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        PermissionService.shared.stopPolling()
        SaveLocationPresenter.dismiss()
        Diagnostics.lifecycle.info("Session suspended")
        suspensionTask = Task { @MainActor in
            await CaptureSession.shared.suspendForSystemEvent()
            WindowCatalog.shared.releaseCachedContent()
            suspensionTask = nil
        }
    }

    private func resume() {
        isSuspended = false
        PermissionService.shared.refresh()
        WindowCatalog.shared.releaseCachedContent()
        CaptureSession.shared.relayoutForCurrentScreens()
        PinController.shared.relayoutForCurrentScreens()
        Diagnostics.lifecycle.info("Session resumed")
    }

    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        pressure?.cancel()
        pressure = nil
        suspensionTask?.cancel()
        suspensionTask = nil
    }
}
