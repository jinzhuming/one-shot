import AppKit
import Testing
@testable import Shot

@MainActor private func buttons(in view: NSView) -> [NSButton] {
    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
}

@Test @MainActor func recordingControlsRecoverAfterEveryTransition() throws {
    let view = RecordingControlBarView(onPause: {}, onStop: {}, onCancel: {})
    let stop = try #require(buttons(in: view).first { $0.title == String(localized: "停止并保存") })
    let pause = try #require(buttons(in: view).first { $0.title == String(localized: "暂停") })
    let cancel = try #require(buttons(in: view).first { $0.title == String(localized: "放弃") })
    for transient: RecordingState in [.starting, .pausing, .resuming] {
        view.update(state: transient, elapsed: 10)
        #expect(!stop.isEnabled && !pause.isEnabled && cancel.isEnabled)
        for stable: RecordingState in [.recording, .paused] {
            view.update(state: stable, elapsed: 10)
            #expect(stop.isEnabled && pause.isEnabled && cancel.isEnabled)
        }
    }
    view.update(state: .stopping, elapsed: 10)
    #expect(!stop.isEnabled && !pause.isEnabled && !cancel.isEnabled)
}

@Test @MainActor func recordingCountdownVisibilityTracksPanelLifetime() {
    let hud = RecordingCountdownHUD()
    #expect(!hud.isVisible)
    guard let screen = NSScreen.main else { return }
    hud.show(seconds: 3, on: screen)
    #expect(hud.isVisible)
    hud.hide()
    #expect(!hud.isVisible)
}

@Test @MainActor func statusItemIconStateTracksRecordingLifecycle() {
    let icon = StatusItemIconState()
    let menu = StatusItemMenuState()
    let revision = menu.revision

    #expect(!icon.recordingActive)
    icon.update(recordingActive: true)
    #expect(icon.recordingActive)
    icon.update(recordingActive: true)
    #expect(icon.recordingActive)
    icon.update(recordingActive: false)
    #expect(!icon.recordingActive)

    menu.reload()
    #expect(menu.revision == revision &+ 1)
    #expect(!icon.recordingActive)
}

@Test @MainActor func thinAndTallPinsReserveRoomForTheirControls() {
    let display = CGRect(x: -640, y: 40, width: 640, height: 480)
    for image in [CGSize(width: 5000, height: 1), CGSize(width: 1, height: 5000)] {
        for size in [PinLayout.windowSize(for: image, visibleFrame: display),
                     PinLayout.zoomedWindowSize(for: image, visibleFrame: display)] {
            #expect(size.width >= 192)
            #expect(size.height >= 54)
            #expect(size.width <= display.width && size.height <= display.height)
        }
    }
}

@Test func savedFeedbackIdentifiesTheActualMedia() {
    #expect(ExportMediaKind.video.savedTitle == String(localized: "视频已保存"))
    #expect(ExportMediaKind.screenshot.savedTitle == String(localized: "截图已保存"))
}

@Test @MainActor func nativeMaterialsCanChangeAccessibilityWithoutBeingRecreated() throws {
    let view = HUDMaterialView(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
    let fallback = try #require(view.subviews.first)
    for surface: HUDMaterialView.Surface in [.darkHUD, .adaptive, .windowHeader] {
        view.surface = surface
        view.applyAccessibility(reduceTransparency: true, increaseContrast: true)
        #expect(!view.isHidden && !fallback.isHidden)
        #expect(view.layer?.borderWidth == 2)
        view.applyAccessibility(reduceTransparency: false, increaseContrast: false)
        #expect(!view.isHidden && fallback.isHidden)
        #expect(view.layer?.borderWidth == 0)
    }
}
