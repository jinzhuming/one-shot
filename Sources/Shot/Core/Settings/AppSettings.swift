import AppKit
import Foundation
import ShotKit

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let afterCaptureAction = "afterCaptureAction"
        static let copyOnComplete = "copyOnComplete"
        static let saveFormat = "saveFormat"
        static let saveDirectory = "saveDirectory"
        static let askWhereToSave = "askWhereToSave"
        static let includeWindowShadow = "includeWindowShadow"
        static let useLightweightCaptureHUD = "overlay.useLightweightCaptureHUD"
        static let screenshotBackgroundMode = "screenshot.backgroundMode"
        static let customScreenshotBackground = "screenshot.customBackground"
        static let lastSelection = "lastSelection"
        static let areaWindowToggleHotkey = "overlay.areaWindowToggleHotkey"
        static let annotationWindowPlacement = "annotation.windowPlacement"
        static let annotationZoomWithCommandScroll = "annotation.zoomWithCommandScroll"
        static let annotationPreferences = "annotation.preferences"
        static let screenshotHistory = "screenshot.history"
        static let captureSystemAudio = "recording.systemAudio"
        static let captureMicrophone = "recording.microphone"
        static let recordingCountdown = "recording.countdown"
        static let highlightClicks = "recording.highlightClicks"
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    @Published var afterCaptureAction: AfterCaptureAction {
        didSet { defaults.set(afterCaptureAction.rawValue, forKey: Key.afterCaptureAction) }
    }

    @Published var annotationWindowPlacement: AnnotationWindowPlacement {
        didSet { defaults.set(annotationWindowPlacement.rawValue, forKey: Key.annotationWindowPlacement) }
    }

    @Published var annotationZoomWithCommandScroll: Bool {
        didSet { defaults.set(annotationZoomWithCommandScroll, forKey: Key.annotationZoomWithCommandScroll) }
    }

    @Published var copyOnComplete: Bool {
        didSet { defaults.set(copyOnComplete, forKey: Key.copyOnComplete) }
    }

    @Published var saveFormat: SaveFormat {
        didSet { defaults.set(saveFormat.rawValue, forKey: Key.saveFormat) }
    }

    @Published var askWhereToSave: Bool {
        didSet { defaults.set(askWhereToSave, forKey: Key.askWhereToSave) }
    }

    @Published var includeWindowShadow: Bool {
        didSet { defaults.set(includeWindowShadow, forKey: Key.includeWindowShadow) }
    }

    @Published var useLightweightCaptureHUD: Bool {
        didSet { defaults.set(useLightweightCaptureHUD, forKey: Key.useLightweightCaptureHUD) }
    }

    @Published var screenshotBackgroundMode: ScreenshotBackgroundMode {
        didSet { defaults.set(screenshotBackgroundMode.rawValue, forKey: Key.screenshotBackgroundMode) }
    }

    @Published var customScreenshotBackgroundPath: String {
        didSet {
            if customScreenshotBackgroundPath.isEmpty {
                defaults.removeObject(forKey: Key.customScreenshotBackground)
            } else {
                defaults.set(customScreenshotBackgroundPath, forKey: Key.customScreenshotBackground)
            }
        }
    }

    @Published var saveDirectoryPath: String {
        didSet { defaults.set(saveDirectoryPath, forKey: Key.saveDirectory) }
    }

    @Published var areaWindowToggleHotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(areaWindowToggleHotkey) {
                defaults.set(data, forKey: Key.areaWindowToggleHotkey)
            }
        }
    }

    @Published var annotationPreferences: AnnotationPreferences {
        didSet {
            let validated = annotationPreferences.validated()
            if annotationPreferences != validated {
                annotationPreferences = validated
                return
            }
            if let data = try? JSONEncoder().encode(validated) {
                defaults.set(data, forKey: Key.annotationPreferences)
            }
        }
    }

    @Published var screenshotHistory: [ScreenshotHistoryItem] {
        didSet {
            if let data = try? JSONEncoder().encode(screenshotHistory) {
                defaults.set(data, forKey: Key.screenshotHistory)
            }
        }
    }

    @Published var captureSystemAudio: Bool {
        didSet { defaults.set(captureSystemAudio, forKey: Key.captureSystemAudio) }
    }

    @Published var captureMicrophone: Bool {
        didSet { defaults.set(captureMicrophone, forKey: Key.captureMicrophone) }
    }

    @Published var recordingCountdown: RecordingCountdown {
        didSet { defaults.set(recordingCountdown.rawValue, forKey: Key.recordingCountdown) }
    }

    @Published var highlightClicks: Bool {
        didSet { defaults.set(highlightClicks, forKey: Key.highlightClicks) }
    }

    var saveDirectoryURL: URL {
        get { URL(fileURLWithPath: saveDirectoryPath, isDirectory: true) }
        set { saveDirectoryPath = newValue.path }
    }

    var customScreenshotBackgroundURL: URL? {
        get {
            guard !customScreenshotBackgroundPath.isEmpty else { return nil }
            return URL(fileURLWithPath: customScreenshotBackgroundPath)
        }
        set { customScreenshotBackgroundPath = newValue?.path ?? "" }
    }

    func screenshotBackgroundURL(for screen: NSScreen) -> URL? {
        switch screenshotBackgroundMode {
        case .desktop:
            return NSWorkspace.shared.desktopImageURL(for: screen)
        case .custom:
            return customScreenshotBackgroundURL
        case .none:
            return nil
        }
    }

    var lastSelection: RegionSelection? {
        get {
            guard let dict = defaults.dictionary(forKey: Key.lastSelection) else { return nil }
            func value(_ key: String) -> CGFloat? {
                (dict[key] as? NSNumber).map { CGFloat(truncating: $0) }
            }
            guard let x = value("x"), let y = value("y"), let w = value("w"), let h = value("h") else { return nil }
            let displayID = (dict["displayID"] as? NSNumber).map { $0.uint32Value } ?? 0
            let rect = CGRect(x: x, y: y, width: w, height: h)
            guard displayID != 0,
                  x.isFinite, y.isFinite, w.isFinite, h.isFinite,
                  w > 0, h > 0,
                  rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
            return RegionSelection(rect: rect, displayID: displayID)
        }
        set {
            if let selection = newValue {
                defaults.set(
                    [
                        "x": selection.rect.origin.x,
                        "y": selection.rect.origin.y,
                        "w": selection.rect.width,
                        "h": selection.rect.height,
                        "displayID": selection.displayID
                    ],
                    forKey: Key.lastSelection
                )
            } else {
                defaults.removeObject(forKey: Key.lastSelection)
            }
        }
    }

    static var defaultSaveDirectory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("Shot", isDirectory: true)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        afterCaptureAction = AfterCaptureAction(rawValue: defaults.string(forKey: Key.afterCaptureAction) ?? "") ?? .annotate
        annotationWindowPlacement = AnnotationWindowPlacement(
            rawValue: defaults.string(forKey: Key.annotationWindowPlacement) ?? ""
        ) ?? .inPlace
        annotationZoomWithCommandScroll = defaults.object(forKey: Key.annotationZoomWithCommandScroll) as? Bool ?? false
        copyOnComplete = defaults.object(forKey: Key.copyOnComplete) as? Bool ?? true
        saveFormat = SaveFormat(rawValue: defaults.string(forKey: Key.saveFormat) ?? "") ?? .png
        askWhereToSave = defaults.bool(forKey: Key.askWhereToSave)
        includeWindowShadow = defaults.object(forKey: Key.includeWindowShadow) as? Bool ?? false
        useLightweightCaptureHUD = defaults.object(forKey: Key.useLightweightCaptureHUD) as? Bool ?? true
        screenshotBackgroundMode = ScreenshotBackgroundMode(
            rawValue: defaults.string(forKey: Key.screenshotBackgroundMode) ?? ""
        ) ?? .desktop
        customScreenshotBackgroundPath = defaults.string(forKey: Key.customScreenshotBackground) ?? ""
        let storedSaveDirectory = defaults.string(forKey: Key.saveDirectory)
        // Keep an explicitly stored path untouched. This prevents changing a
        // user's existing Downloads or custom location when the fresh-install
        // default evolves.
        let resolvedSaveDirectory = storedSaveDirectory ?? Self.defaultSaveDirectory.path
        saveDirectoryPath = resolvedSaveDirectory
        if storedSaveDirectory != resolvedSaveDirectory {
            defaults.set(resolvedSaveDirectory, forKey: Key.saveDirectory)
        }
        areaWindowToggleHotkey = Self.loadAreaWindowToggleHotkey(from: defaults)
        if let data = defaults.data(forKey: Key.annotationPreferences),
           let preferences = try? JSONDecoder().decode(AnnotationPreferences.self, from: data) {
            annotationPreferences = preferences.validated()
        } else {
            annotationPreferences = .default
        }
        if let data = defaults.data(forKey: Key.screenshotHistory),
           let items = try? JSONDecoder().decode([ScreenshotHistoryItem].self, from: data) {
            screenshotHistory = items
        } else {
            screenshotHistory = []
        }
        captureSystemAudio = defaults.bool(forKey: Key.captureSystemAudio)
        captureMicrophone = defaults.bool(forKey: Key.captureMicrophone)
        recordingCountdown = RecordingCountdown(
            rawValue: defaults.object(forKey: Key.recordingCountdown) as? Int ?? 0
        ) ?? .off
        highlightClicks = defaults.bool(forKey: Key.highlightClicks)
    }

    private static func loadAreaWindowToggleHotkey(from defaults: UserDefaults) -> Hotkey {
        guard let data = defaults.data(forKey: Key.areaWindowToggleHotkey),
              let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data),
              !hotkey.isReservedOverlayShortcut
        else {
            return .defaultAreaWindowToggle
        }
        return hotkey
    }
}
