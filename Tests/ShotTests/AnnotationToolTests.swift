import AppKit
import Testing
@testable import Shot

@Test func annotationToolMetadataIsCompleteAndShortcutMappingRoundTrips() {
    let tools = AnnotationToolID.allCases

    #expect(tools.count == 10)
    #expect(Set(tools.map(\.shortcut)).count == tools.count)
    #expect(Set(tools.map(\.shortcutKeyCode)).count == tools.count)

    for tool in tools {
        #expect(!tool.title.isEmpty)
        #expect(!tool.helpText.isEmpty)
        #expect(AnnotationToolID.fromShortcutKeyCode(tool.shortcutKeyCode) == tool)
    }
}

@Test @MainActor func annotationToolbarGroupsExposeEveryTool() {
    let groupedTools = AnnotationToolID.groups.flatMap { $0 }

    #expect(Set(groupedTools) == Set(AnnotationToolID.allCases))
    #expect(groupedTools.contains(.mosaic))
}

@Test @MainActor func mosaicToolCommitsTheSelectedRegion() {
    var document = AnnotationDocument(baseImage: NSImage(size: CGSize(width: 320, height: 180)))
    let tool = ShapeTool(id: .mosaic)

    tool.handle(.down(CGPoint(x: 24, y: 18), shift: false), document: &document)
    tool.handle(.drag(CGPoint(x: 124, y: 78), shift: false), document: &document)
    tool.handle(.up(CGPoint(x: 124, y: 78), shift: false), document: &document)

    #expect(document.elements.count == 1)
    guard case .mosaic(let rect, let blockSize) = document.elements[0] else {
        Issue.record("The mosaic tool must commit a mosaic element")
        return
    }
    #expect(rect == CGRect(x: 24, y: 18, width: 100, height: 60))
    #expect(blockSize == 10)
}

@Test @MainActor func annotationPreferencesPersistPerToolAndAreUsedByNewElements() {
    let suiteName = "ShotTests.AnnotationPreferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    var preferences = settings.annotationPreferences
    preferences.penLineWidth = 11
    preferences.highlighterOpacity = 0.25
    preferences.mosaicBlockSize = 20
    settings.annotationPreferences = preferences

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.annotationPreferences.penLineWidth == 11)
    #expect(reloaded.annotationPreferences.highlighterOpacity == 0.25)
    #expect(reloaded.annotationPreferences.mosaicBlockSize == 20)

    let image = NSImage(size: CGSize(width: 320, height: 180))
    let session = EditSession(image: image, settings: reloaded)
    session.selectedTool = .mosaic
    #expect(session.mosaicBlockSize == 20)
    session.handle(.down(CGPoint(x: 20, y: 20), shift: false))
    session.handle(.up(CGPoint(x: 80, y: 60), shift: false))

    guard case .mosaic(_, let blockSize) = session.document.elements[0] else {
        Issue.record("The mosaic element must retain the configured block size")
        return
    }
    #expect(blockSize == 20)
}

@Test @MainActor func highlighterElementRetainsConfiguredOpacity() {
    let suiteName = "ShotTests.HighlighterPreferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    let session = EditSession(
        image: NSImage(size: CGSize(width: 320, height: 180)),
        settings: settings
    )
    session.selectedTool = .highlighter
    session.highlighterOpacity = 0.25
    session.handle(.down(CGPoint(x: 20, y: 20), shift: false))
    session.handle(.drag(CGPoint(x: 50, y: 40), shift: false))
    session.handle(.up(CGPoint(x: 80, y: 60), shift: false))

    guard case .highlighter(_, let style) = session.document.elements[0] else {
        Issue.record("The highlighter element must retain its configured style")
        return
    }
    #expect(style.highlighterOpacity == 0.25)
}

@Test func highlighterMetadataExplainsItsVisualTreatment() {
    let highlighter = AnnotationToolID.highlighter

    #expect(highlighter.title == "荧光笔")
    #expect(highlighter.shortcut == "6")
    #expect(highlighter.helpText.contains("半透明宽线"))
    #expect(highlighter.helpText.contains("（6）"))
}
