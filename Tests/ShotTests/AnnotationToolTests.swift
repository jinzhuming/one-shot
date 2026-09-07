import AppKit
import SwiftUI
import Testing
@testable import Shot

@Test func annotationToolMetadataIsCompleteAndShortcutMappingRoundTrips() {
    let tools = AnnotationToolID.allCases

    #expect(tools.count == 11)
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
    guard case .mosaic(let rect, let blockSize) = document.elements[0].element else {
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

    guard case .mosaic(_, let blockSize) = session.document.elements[0].element else {
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

    guard case .highlighter(_, let style) = session.document.elements[0].element else {
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

@Test @MainActor func selectionMovesResizesAndUndoRestoresAnAnnotation() {
    let session = EditSession(image: NSImage(size: CGSize(width: 320, height: 180)))
    session.selectedTool = .rect
    session.handle(.down(CGPoint(x: 40, y: 30), shift: false))
    session.handle(.up(CGPoint(x: 140, y: 90), shift: false))
    let original = session.document.elements[0]

    session.selectedTool = .select
    session.handle(.down(CGPoint(x: 90, y: 60), shift: false))
    session.handle(.drag(CGPoint(x: 120, y: 70), shift: false))
    session.handle(.up(CGPoint(x: 120, y: 70), shift: false))

    guard case .rect(let movedRect, _) = session.document.elements[0].element else {
        Issue.record("The selected rectangle must remain a rectangle after moving")
        return
    }
    #expect(movedRect.origin == CGPoint(x: 70, y: 40))

    let movedBounds = session.document.elements[0].bounds
    session.handle(.down(CGPoint(x: movedBounds.maxX, y: movedBounds.maxY), shift: false))
    session.handle(.up(CGPoint(x: 210, y: 140), shift: false))
    #expect(session.document.elements[0].bounds.width > original.bounds.width)

    session.undo()
    #expect(session.document.elements[0].bounds == CGRect(x: 66, y: 36, width: 108, height: 68))
}

@Test @MainActor func selectionDuplicateAndDeleteUseUndoableDocumentOperations() {
    let session = EditSession(image: NSImage(size: CGSize(width: 320, height: 180)))
    session.selectedTool = .ellipse
    session.handle(.down(CGPoint(x: 20, y: 20), shift: false))
    session.handle(.up(CGPoint(x: 80, y: 60), shift: false))
    session.selectedTool = .select
    session.handle(.down(CGPoint(x: 50, y: 40), shift: false))
    session.handle(.up(CGPoint(x: 50, y: 40), shift: false))

    let originalID = session.document.elements[0].id
    session.duplicateSelection()
    #expect(session.document.elements.count == 2)
    #expect(session.document.elements[1].id != originalID)
    #expect(session.hasSelection)

    session.deleteSelection()
    #expect(session.document.elements.count == 1)
    session.undo()
    #expect(session.document.elements.count == 2)
}

@Test @MainActor func selectionPropertiesUpdateTheSelectedObject() {
    let session = EditSession(image: NSImage(size: CGSize(width: 320, height: 180)))
    session.selectedTool = .rect
    session.handle(.down(CGPoint(x: 40, y: 30), shift: false))
    session.handle(.up(CGPoint(x: 140, y: 90), shift: false))
    session.selectedTool = .select
    session.handle(.down(CGPoint(x: 90, y: 60), shift: false))
    session.handle(.up(CGPoint(x: 90, y: 60), shift: false))

    session.lineWidth = 8
    session.color = .blue

    guard case .rect(_, let style) = session.document.elements[0].element else {
        Issue.record("The selected object must remain a rectangle while editing its style")
        return
    }
    #expect(style.lineWidth == 8)
    #expect(style.color.usingColorSpace(.deviceRGB)?.blueComponent == 1)
}

@Test @MainActor func selectedSpecialAnnotationPropertiesUpdateTheirElements() {
    let image = NSImage(size: CGSize(width: 320, height: 180))
    let session = EditSession(image: image)

    session.document.commit(.highlighter(
        points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 40)],
        style: AnnotationStyle()
    ))
    let highlighterID = session.document.elements[0].id
    session.document.select(highlighterID)
    session.selectedTool = .select
    session.highlighterOpacity = 0.25
    guard case .highlighter(_, let highlighterStyle) = session.document.elements[0].element else {
        Issue.record("The selected highlighter must remain editable")
        return
    }
    #expect(highlighterStyle.highlighterOpacity == 0.25)

    session.document.commit(.mosaic(CGRect(x: 20, y: 20, width: 80, height: 50), blockSize: 10))
    let mosaicID = session.document.elements[1].id
    session.document.select(mosaicID)
    session.mosaicBlockSize = 24
    guard case .mosaic(_, let blockSize) = session.document.elements[1].element else {
        Issue.record("The selected mosaic must remain editable")
        return
    }
    #expect(blockSize == 24)

    session.document.commit(.spotlight(CGRect(x: 30, y: 30, width: 60, height: 40), opacity: 0.5))
    let spotlightID = session.document.elements[2].id
    session.document.select(spotlightID)
    session.spotlightOpacity = 0.8
    guard case .spotlight(_, let opacity) = session.document.elements[2].element else {
        Issue.record("The selected spotlight must remain editable")
        return
    }
    #expect(opacity == 0.8)
}

@Test @MainActor func resizingTextAndCounterChangesTheirRenderedBounds() {
    let text = AnnotationObject(element: .text(
        "Shot",
        origin: CGPoint(x: 20, y: 20),
        style: AnnotationStyle(textScale: 1)
    ))
    let largeText = text.resized(to: CGRect(
        x: text.bounds.minX,
        y: text.bounds.minY,
        width: text.bounds.width * 2,
        height: text.bounds.height * 2
    ))
    #expect(largeText.bounds.width > text.bounds.width)

    let counter = AnnotationObject(element: .counter(
        1,
        center: CGPoint(x: 100, y: 100),
        style: AnnotationStyle(counterScale: 1)
    ))
    let largeCounter = counter.resized(to: CGRect(
        x: counter.bounds.minX,
        y: counter.bounds.minY,
        width: counter.bounds.width * 2,
        height: counter.bounds.height * 2
    ))
    #expect(largeCounter.bounds.width > counter.bounds.width)
}

@Test @MainActor func existingTextCanBeReplacedWithoutChangingItsObjectID() {
    var document = AnnotationDocument(baseImage: NSImage(size: CGSize(width: 320, height: 180)))
    document.commit(.text("Before", origin: CGPoint(x: 20, y: 20), style: AnnotationStyle()))
    let id = document.elements[0].id

    document.replaceText(id: id, with: "After")

    #expect(document.elements[0].id == id)
    guard case .text(let text, _, _) = document.elements[0].element else {
        Issue.record("The text object must remain editable after replacement")
        return
    }
    #expect(text == "After")
}
