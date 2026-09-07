import AppKit
import Testing
@testable import ShotKit

@Test func singleWindowShadowPreferenceMapsToScreenCaptureKitFlag() {
    #expect(WindowCapturePolicy.route(includeShadow: true) == .singleWindow)
    #expect(WindowCapturePolicy.route(includeShadow: false) == .singleWindow)
    #expect(!WindowCapturePolicy.ignoresShadowsSingleWindow(includeShadow: true))
    #expect(WindowCapturePolicy.ignoresShadowsSingleWindow(includeShadow: false))
}

@Test func windowInclusionFiltersLayerSizeAndPID() {
    let our: pid_t = 100
    #expect(WindowInclusion.shouldInclude(layer: 0, size: CGSize(width: 80, height: 80), processID: 200, ourPID: our))
    // System-owned full-screen surfaces such as Dock and the menu bar must
    // never outrank an application window during hover hit-testing.
    #expect(!WindowInclusion.shouldInclude(layer: 1, size: CGSize(width: 80, height: 80), processID: 200, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: 20, size: CGSize(width: 1920, height: 1080), processID: 200, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: 0, size: CGSize(width: 80, height: 80), processID: our, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: 0, size: CGSize(width: 20, height: 80), processID: 200, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: -1, size: CGSize(width: 80, height: 80), processID: 200, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: 25, size: CGSize(width: 80, height: 80), processID: 200, ourPID: our))
}

@Test func windowInclusionRejectsWindowMissingFromShareableContent() {
    let shareable: Set<CGWindowID> = [42, 84]
    #expect(WindowInclusion.isShareable(windowID: 42, in: shareable))
    #expect(!WindowInclusion.isShareable(windowID: 99, in: shareable))
}

@Test func windowHitTestingFrontmostAndCycle() {
    let front = CGRect(x: 100, y: 100, width: 200, height: 120)
    let back = CGRect(x: 80, y: 80, width: 400, height: 300)
    let miss = CGRect(x: 0, y: 0, width: 40, height: 40)
    let hits = WindowHitTesting.containing(CGPoint(x: 150, y: 150), in: [front, back, miss])
    #expect(hits == [0, 1])
    #expect(WindowHitTesting.cycledIndex(current: 0, count: 2, reverse: false) == 1)
    #expect(WindowHitTesting.cycledIndex(current: 1, count: 2, reverse: false) == 0)
    #expect(WindowHitTesting.cycledIndex(current: 0, count: 2, reverse: true) == 1)
}
