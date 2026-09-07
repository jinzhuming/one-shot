import AppKit
import SwiftUI
import Testing
@testable import Shot

@Test func annotationToolMetadataIsCompleteAndShortcutMappingRoundTrips() {
    let tools = AnnotationToolID.allCases

    #expect(tools.count == 12)
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

@Test @MainActor func calloutTextCanBeCommittedAndReplacedWithoutChangingItsObjectID() {
    let session = EditSession(image: NSImage(size: CGSize(width: 320, height: 180)))
    let rect = CGRect(x: 24, y: 18, width: 160, height: 72)

    session.selectedTool = .callout
    session.beginCallout(at: rect)
    session.commitCallout("说明", in: rect)

    guard case .callout(let text, let committedRect, _) = session.document.elements[0].element else {
        Issue.record("The callout tool must commit a callout element")
        return
    }
    #expect(text == "说明")
    #expect(committedRect == rect)

    let id = session.document.elements[0].id
    session.selectedTool = .select
    session.beginCallout(at: rect, replacing: id)
    session.commitCallout("更新", in: rect, replacing: id)

    #expect(session.document.elements[0].id == id)
    guard case .callout(let replacedText, _, _) = session.document.elements[0].element else {
        Issue.record("The callout must remain a callout after text replacement")
        return
    }
    #expect(replacedText == "更新")
}

@Test func calloutLayoutFollowsTextAndSupportsOptionalWrapping() {
    let rect = CGRect(x: 24, y: 18, width: 160, height: 72)
    let style = AnnotationStyle()
    let short = AnnotationCalloutLayout.layout(
        text: "说明",
        in: rect,
        style: style,
        wrapsText: true
    )
    let long = AnnotationCalloutLayout.layout(
        text: String(repeating: "这是一段需要换行的说明。", count: 4),
        in: rect,
        style: style,
        wrapsText: true
    )

    #expect(long.body.width == short.body.width)
    #expect(long.body.height > short.body.height)
    #expect(long.textRect.minX >= long.body.minX)
    #expect(long.textRect.maxX <= long.body.maxX)
    #expect(long.textRect.minY >= long.body.minY)
    #expect(long.textRect.maxY <= long.body.maxY)

    let singleLine = AnnotationCalloutLayout.layout(
        text: String(repeating: "更长的单行说明 ", count: 8),
        in: rect,
        style: style,
        wrapsText: false
    )
    #expect(singleLine.body.width > rect.width)
}

@Test func calloutObjectBoundsRecomputeWhenTextChanges() {
    let rect = CGRect(x: 24, y: 18, width: 160, height: 72)
    let object = AnnotationObject(element: .callout(
        "短文本",
        rect: rect,
        style: AnnotationStyle()
    ))
    let expanded = object.replacingText(String(repeating: "自动换行内容。", count: 5))
    let contracted = expanded.replacingText("短文本")

    #expect(expanded.bounds.height > object.bounds.height)
    #expect(contracted.bounds == object.bounds)
}

@Test @MainActor func secondaryAnnotationPreferencesAreAppliedToNewElements() {
    let session = EditSession(image: NSImage(size: CGSize(width: 320, height: 180)))

    session.selectedTool = .arrow
    session.arrowHeadStyle = .open
    session.arrowHeadScale = 1.6
    session.handle(.down(CGPoint(x: 20, y: 20), shift: false))
    session.handle(.up(CGPoint(x: 120, y: 80), shift: false))

    guard case .arrow(_, _, let arrowStyle) = session.document.elements[0].element else {
        Issue.record("The arrow tool must preserve its secondary settings")
        return
    }
    #expect(arrowStyle.arrowHeadStyle == .open)
    #expect(arrowStyle.arrowHeadScale == 1.6)

    session.selectedTool = .pen
    session.penSmoothing = 0.9
    session.penOpacity = 0.5
    session.handle(.down(CGPoint(x: 20, y: 100), shift: false))
    session.handle(.drag(CGPoint(x: 50, y: 110), shift: false))
    session.handle(.up(CGPoint(x: 90, y: 120), shift: false))

    guard case .pen(_, let penStyle) = session.document.elements[1].element else {
        Issue.record("The pen tool must preserve its secondary settings")
        return
    }
    #expect(penStyle.penSmoothing == 0.9)
    #expect(penStyle.penOpacity == 0.5)
}

@Test @MainActor func arrowsAndCalloutsCanBeRenderedInAnExportSnapshot() {
    let context = CGContext(
        data: nil,
        width: 320,
        height: 180,
        bitsPerComponent: 8,
        bytesPerRow: 320 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
    let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 320, height: 180))
    var document = AnnotationDocument(baseImage: image)
    var arrowStyle = AnnotationStyle()
    arrowStyle.arrowHeadStyle = .open
    arrowStyle.arrowHeadScale = 1.4
    document.commit(.arrow(
        start: CGPoint(x: 20, y: 20),
        end: CGPoint(x: 180, y: 90),
        style: arrowStyle
    ))
    document.commit(.callout(
        "说明",
        rect: CGRect(x: 80, y: 100, width: 160, height: 60),
        style: AnnotationStyle()
    ))

    #expect(document.flattenedCGImage() != nil)
}

@Test func olderAnnotationPreferencesDecodeWithNewDefaults() throws {
    let data = Data(#"{"penLineWidth":11,"highlighterOpacity":0.25}"#.utf8)
    let preferences = try JSONDecoder().decode(AnnotationPreferences.self, from: data)

    #expect(preferences.penLineWidth == 11)
    #expect(preferences.highlighterOpacity == 0.25)
    #expect(preferences.arrowHeadStyle == .filled)
    #expect(preferences.linePattern == .solid)
    #expect(preferences.calloutFillOpacity == 0.14)
    #expect(preferences.calloutWrapText)
}
