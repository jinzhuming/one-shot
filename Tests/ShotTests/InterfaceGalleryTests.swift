import AppKit
import SwiftUI
import Testing
@testable import Shot

/// Opt-in component renders, not desktop captures. Native materials here have
/// no live desktop backdrop; real display/VoiceOver acceptance stays manual.
@Test @MainActor func renderInterfaceGallery() throws {
    guard let directory = ProcessInfo.processInfo.environment["SHOT_UI_GALLERY_DIR"] else { return }
    let output = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for dark in [false, true] {
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        let suffix = dark ? "dark" : "light"
        for page in SettingsView.Page.allCases {
            for size in [CGSize(width: 720, height: 560), CGSize(width: 640, height: 480)] {
                let compact = size.width == 640 ? "-compact" : ""
                try render(NSHostingView(rootView: SettingsView(initialPage: page).background(Color(nsColor: .windowBackgroundColor))),
                           size: size, appearance: appearance,
                           to: output.appendingPathComponent("settings-\(page.rawValue)-\(suffix)\(compact).png"))
            }
        }
        for step in 0...2 {
            try render(NSHostingView(rootView: OnboardingView(initialStep: step, onFinished: {}).background(Color(nsColor: .windowBackgroundColor))),
                       size: CGSize(width: 520, height: 460), appearance: appearance,
                       to: output.appendingPathComponent("onboarding-\(step)-\(suffix).png"))
        }
        let suiteName = "Shot.Gallery.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let session = EditSession(image: NSImage(size: CGSize(width: 640, height: 400)),
                                  settings: AppSettings(defaults: preferences))
        for width: CGFloat in [584, 820] {
            for tool in AnnotationToolID.allCases {
                session.selectedTool = tool
                let toolbar = AnnotationToolbar(session: session, onCopy: {}, onSave: {}, onPin: {},
                                                onOCR: {}, onClose: {}, presentation: dark ? .floatingHUD : .windowAdaptive,
                                                availableWidth: width)
                try render(NSHostingView(rootView: toolbar), size: CGSize(width: width, height: 89), appearance: appearance,
                           to: output.appendingPathComponent("toolbar-\(tool.rawValue)-\(Int(width))-\(suffix).png"))
            }
        }
    }
    try renderRecordingComponents(to: output)
}

@Test @MainActor func renderRecordingGallery() throws {
    guard let directory = ProcessInfo.processInfo.environment["SHOT_RECORDING_GALLERY_DIR"] else { return }
    let output = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try renderRecordingComponents(to: output)
}

@MainActor private func renderRecordingComponents(to output: URL) throws {
    for dark in [false, true] {
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        let suffix = dark ? "dark" : "light"
        for accessible in [false, true] {
            let variant = accessible ? "-accessible" : ""
            let recording = RecordingControlBarView(onPause: {}, onStop: {}, onCancel: {})
            for state: RecordingState in [.recording, .paused, .starting, .pausing, .resuming, .stopping] {
                recording.update(state: state, elapsed: 3665)
                applyGalleryAccessibility(to: recording, enabled: accessible)
                try render(recording, size: recording.intrinsicContentSize, appearance: appearance,
                           to: output.appendingPathComponent("recording-\(state)-\(suffix)\(variant).png"))
                let status = RecordingStatusHUDView(frame: .zero)
                status.update(state: state, elapsed: 3665)
                applyGalleryAccessibility(to: status, enabled: accessible)
                try render(status, size: status.intrinsicContentSize, appearance: appearance,
                           to: output.appendingPathComponent("recording-status-\(state)-\(suffix)\(variant).png"))
            }
            let countdown = RecordingCountdownView(frame: .zero)
            countdown.update(3)
            applyGalleryAccessibility(to: countdown, enabled: accessible)
            try render(countdown, size: CGSize(width: 88, height: 88), appearance: appearance,
                       to: output.appendingPathComponent("recording-countdown-\(suffix)\(variant).png"))
            let preview = RecordingPreviewView(url: output.appendingPathComponent("preview.mov"),
                                               onCopy: {}, onSave: {}, onReveal: {}, onClose: {})
            for exporting in [false, true] {
                preview.setExporting(exporting)
                applyGalleryAccessibility(to: preview, enabled: accessible)
                try render(preview, size: CGSize(width: 380, height: 284), appearance: appearance,
                           to: output.appendingPathComponent("recording-preview-\(exporting ? "saving" : "ready")-\(suffix)\(variant).png"))
            }
        }
    }
}

@MainActor private func applyGalleryAccessibility(to view: NSView, enabled: Bool) {
    (view as? HUDMaterialView)?.applyAccessibility(reduceTransparency: enabled, increaseContrast: enabled)
    for subview in view.subviews { applyGalleryAccessibility(to: subview, enabled: enabled) }
}

@MainActor private func render(_ view: NSView, size: CGSize, appearance: NSAppearance.Name, to url: URL) throws {
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearance)
    defer { window.contentView = nil; window.close() }
    window.contentView = view
    view.frame = CGRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
}
