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
    let recording = RecordingControlBarView(onPause: {}, onStop: {}, onCancel: {})
    for state: RecordingState in [.recording, .paused, .starting, .stopping] {
        recording.update(state: state, elapsed: 65)
        try render(recording, size: recording.intrinsicContentSize, appearance: .darkAqua,
                   to: output.appendingPathComponent("recording-\(state).png"))
    }
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
