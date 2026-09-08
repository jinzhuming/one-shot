import AppKit
import ShotKit

/// Owns polling, mouse throttling and stale snapshot rejection independently
/// of overlay input and drawing. stop() invalidates every outstanding result.
@MainActor
final class WindowSnapshotRefresher {
    private let catalog: WindowCatalog
    private let mayRefresh: () -> Bool
    private let onChange: () -> Void
    private var periodic: Task<Void, Never>?
    private var mouse: Task<Void, Never>?
    private var lifetime = OperationLifetime()
    var isRunning: Bool { periodic != nil }

    init(catalog: WindowCatalog, mayRefresh: @escaping () -> Bool, onChange: @escaping () -> Void) {
        self.catalog = catalog
        self.mayRefresh = mayRefresh
        self.onChange = onChange
    }

    deinit { periodic?.cancel(); mouse?.cancel() }

    func start() {
        stop()
        periodic = Task { @MainActor [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                if let self, self.mayRefresh() {
                    if ticks % 4 == 0 {
                        try? await self.catalog.refresh()
                        if !Task.isCancelled, self.mayRefresh() { self.onChange() }
                    }
                    await self.refresh()
                }
                ticks &+= 1
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    func mouseMoved() {
        guard periodic != nil else { return }
        mouse?.cancel()
        mouse = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard !Task.isCancelled, mayRefresh() else { return }
        let token = lifetime.begin()
        let height = CoordinateSpace.primaryDisplayHeight
        let pid = ProcessInfo.processInfo.processIdentifier
        let allowed = catalog.shareableWindowIDs
        guard let snapshot = try? await BackgroundWork.run({
            WindowSnapshotBuilder.build(primaryDisplayHeight: height, ourPID: pid, allowedWindowIDs: allowed)
        }), !Task.isCancelled, lifetime.contains(token), mayRefresh() else { return }
        lifetime.finish(token)
        let previous = catalog.windows
        catalog.applyWindowsSnapshot(snapshot)
        if previous != snapshot { onChange() }
    }

    func stop() {
        lifetime.invalidate()
        periodic?.cancel()
        periodic = nil
        mouse?.cancel()
        mouse = nil
    }
}
