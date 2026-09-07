import AppKit
import ScreenCaptureKit
import ShotKit

struct CapturableWindow: Identifiable, Equatable, @unchecked Sendable {
    var id: CGWindowID { windowID }
    let windowID: CGWindowID
    let frame: CGRect
    let title: String
    let bundleIdentifier: String?
    let processID: pid_t
}

enum WindowSnapshotBuilder {
    static func build(
        primaryDisplayHeight: CGFloat,
        ourPID: pid_t,
        allowedWindowIDs: Set<CGWindowID>? = nil
    ) -> [CapturableWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return build(
            dictionaries: dictionaries,
            primaryDisplayHeight: primaryDisplayHeight,
            ourPID: ourPID,
            allowedWindowIDs: allowedWindowIDs
        )
    }

    static func build(
        dictionaries: [[String: Any]],
        primaryDisplayHeight: CGFloat,
        ourPID: pid_t,
        allowedWindowIDs: Set<CGWindowID>? = nil
    ) -> [CapturableWindow] {
        var ordered: [CapturableWindow] = []
        var seen = Set<CGWindowID>()

        for dict in dictionaries {
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  seen.insert(windowID).inserted else { continue }
            if let allowedWindowIDs,
               !WindowInclusion.isShareable(windowID: windowID, in: allowedWindowIDs) {
                continue
            }
            let processID = (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard let rawBounds = dict[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds),
                  WindowInclusion.shouldInclude(
                      layer: layer,
                      size: bounds.size,
                      processID: processID,
                      ourPID: ourPID
                  ) else { continue }
            ordered.append(
                CapturableWindow(
                    windowID: windowID,
                    frame: RectMath.cocoaRect(
                        fromCGWindowBounds: bounds,
                        primaryHeight: primaryDisplayHeight
                    ),
                    title: dict[kCGWindowName as String] as? String ?? "",
                    bundleIdentifier: nil,
                    processID: processID
                )
            )
        }
        return ordered
    }
}

@MainActor
final class WindowCatalog {
    static let shared = WindowCatalog()

    static let shareableContentMaxAge: TimeInterval = 2
    static let idleReleaseDelay: TimeInterval = 20

    private(set) var windows: [CapturableWindow] = []
    private(set) var displays: [SCDisplay] = []
    private(set) var content: SCShareableContent?
    private var lastShareableRefresh: Date?
    private var inFlightRefresh: Task<Void, Error>?
    private var idleReleaseTask: Task<Void, Never>?
    private var isSessionActive = false
    private var refreshEpoch = 0
    private(set) var shareableWindowIDs: Set<CGWindowID>?

    private init() {}

    /// Hover uses CoreGraphics; ScreenCaptureKit is only required for the actual capture.
    static func prewarm() {
        Task {
            try? await shared.ensureShareableContent()
            shared.scheduleIdleRelease()
        }
    }

    func markSessionActive() {
        isSessionActive = true
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
    }

    func markSessionIdle() {
        isSessionActive = false
        scheduleIdleRelease()
    }

    func scheduleIdleRelease() {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        guard !isSessionActive else { return }
        idleReleaseTask = Task { [weak self] in
            let nanos = UInt64(Self.idleReleaseDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled, !self.isSessionActive else { return }
            self.releaseCachedContent()
        }
    }

    func releaseCachedContent() {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        refreshEpoch += 1
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        content = nil
        displays = []
        windows = []
        shareableWindowIDs = nil
        lastShareableRefresh = nil
    }

    func refreshWindowsFromCG() {
        windows = WindowSnapshotBuilder.build(
            primaryDisplayHeight: CoordinateSpace.primaryDisplayHeight,
            ourPID: ProcessInfo.processInfo.processIdentifier,
            allowedWindowIDs: shareableWindowIDs
        )
    }

    func applyWindowsSnapshot(_ snapshot: [CapturableWindow]) {
        windows = snapshot
    }

    var hasFreshShareableContent: Bool {
        guard content != nil, let lastShareableRefresh else { return false }
        return Date().timeIntervalSince(lastShareableRefresh) < Self.shareableContentMaxAge
    }

    func ensureShareableContent() async throws {
        if hasFreshShareableContent { return }
        try await refresh()
    }

    func refresh() async throws {
        if let inFlightRefresh {
            try await inFlightRefresh.value
            return
        }
        try await startRefresh()
    }

    /// Waits for any prewarm refresh and then obtains a new content snapshot.
    /// Interactive screenshot capture uses this so a prewarm started before the
    /// hotkey cannot leave transient windows out of the initial snapshot.
    func refreshLatest() async throws {
        if let inFlightRefresh {
            try await inFlightRefresh.value
        }
        try Task.checkCancellation()
        try await startRefresh()
    }

    private func startRefresh() async throws {
        refreshEpoch += 1
        let epoch = refreshEpoch
        let task = Task { @MainActor in
            try await self.performRefresh()
        }
        inFlightRefresh = task
        defer {
            if epoch == refreshEpoch {
                inFlightRefresh = nil
            }
        }
        try await task.value
    }

    func windows(at point: CGPoint) -> [CapturableWindow] {
        windows.filter { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    func hitTest(_ point: CGPoint) -> CapturableWindow? {
        windows(at: point).first
    }

    func scWindow(id: CGWindowID) -> SCWindow? {
        content?.windows.first { $0.windowID == id }
    }

    func scDisplay(id: CGDirectDisplayID) -> SCDisplay? {
        displays.first { $0.displayID == id }
    }

    private func performRefresh() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        self.content = content
        self.displays = content.displays
        shareableWindowIDs = Set(content.windows.map(\.windowID))
        lastShareableRefresh = Date()
        refreshWindowsFromCG()
    }

}
