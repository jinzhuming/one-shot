import AppKit
import Testing
@testable import ShotKit

@Test func annotationUndoStackAndCounter() {
    #expect(AnnotationMath.nextCounter(existing: []) == 1)
    #expect(AnnotationMath.nextCounter(existing: [1, 3, 2]) == 4)
    #expect(AnnotationMath.isSignificantRect(CGRect(x: 0, y: 0, width: 4, height: 4)))
    #expect(!AnnotationMath.isSignificantRect(CGRect(x: 0, y: 0, width: 2, height: 8)))
    #expect(AnnotationMath.isSignificantDistance(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0)))

    var stack = UndoStack<Int>()
    stack.append(1)
    stack.append(2)
    #expect(stack.items == [1, 2])
    #expect(stack.canUndo)
    stack.undo()
    #expect(stack.items == [1])
    #expect(stack.canRedo)
    stack.redo()
    #expect(stack.items == [1, 2])
    stack.undo()
    stack.append(9)
    #expect(stack.items == [1, 9])
    #expect(!stack.canRedo)
}

@Test func undoStackIsBoundedAndCoalescesTransactions() {
    var stack = UndoStack<Int>(historyLimit: 3)
    for value in 0..<5 {
        stack.append(value)
    }

    stack.undo()
    stack.undo()
    stack.undo()
    #expect(stack.items == [0, 1])
    stack.undo()
    #expect(stack.items == [0, 1])

    var transaction = UndoStack<Int>(historyLimit: 100)
    transaction.append(1)
    transaction.beginTransaction()
    transaction.replace(at: 0, with: 2)
    transaction.replace(at: 0, with: 3)
    transaction.endTransaction()
    transaction.undo()
    #expect(transaction.items == [1])
    transaction.redo()
    #expect(transaction.items == [3])
}

@Test func annotationFontSizeScalesWithStroke() {
    #expect(abs(AnnotationMath.fontSize(lineWidth: 2) - 24) < 0.001)
    #expect(abs(AnnotationMath.fontSize(lineWidth: 4) - 32) < 0.001)
    #expect(abs(AnnotationMath.fontSize(lineWidth: 8) - 48) < 0.001)
    #expect(AnnotationMath.strokePresets == [2, 4, 8])
}

@Test func annotationShiftSnapsSquareAndDiagonals() {
    let square = SelectionGeometry.rect(
        from: CGPoint(x: 10, y: 10),
        to: CGPoint(x: 30, y: 20),
        square: true
    )
    #expect(abs(square.width - 20) < 0.001)
    #expect(abs(square.height - 20) < 0.001)

    let horizontal = AnnotationMath.snappedEndpoint(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 40, y: 3)
    )
    #expect(abs(horizontal.x - 40) < 0.2)
    #expect(abs(horizontal.y) < 0.2)

    let diagonal = AnnotationMath.snappedEndpoint(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 10, y: 9)
    )
    #expect(abs(diagonal.x - diagonal.y) < 0.001)
    #expect(abs(hypot(diagonal.x, diagonal.y) - hypot(10, 9)) < 0.001)
}

@Test func annotationGeometryHitTestsTopLevelShapesAndPaths() {
    #expect(AnnotationGeometry.hitTest(
        point: CGPoint(x: 10, y: 10),
        shape: .strokeRect(CGRect(x: 8, y: 8, width: 40, height: 24)),
        tolerance: 3
    ))
    #expect(!AnnotationGeometry.hitTest(
        point: CGPoint(x: 28, y: 20),
        shape: .strokeRect(CGRect(x: 8, y: 8, width: 40, height: 24)),
        tolerance: 3
    ))
    #expect(AnnotationGeometry.hitTest(
        point: CGPoint(x: 50, y: 51),
        shape: .line(CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)),
        tolerance: 2
    ))
    #expect(AnnotationGeometry.hitTest(
        point: CGPoint(x: 45, y: 44),
        shape: .polyline([CGPoint(x: 10, y: 10), CGPoint(x: 45, y: 45), CGPoint(x: 90, y: 90)]),
        tolerance: 3
    ))
}

@Test func annotationGeometryResizesInsideCanvasAndPreservesAspect() {
    let canvas = CGRect(x: 0, y: 0, width: 320, height: 180)
    let original = CGRect(x: 80, y: 40, width: 100, height: 60)
    let handle = AnnotationGeometry.resizedRect(
        original,
        handle: .bottomRight,
        to: CGPoint(x: 310, y: 175),
        preservingAspectRatio: true,
        inside: canvas
    )

    #expect(handle.maxX <= canvas.maxX)
    #expect(handle.maxY <= canvas.maxY)
    #expect(abs(handle.width / handle.height - original.width / original.height) < 0.001)
    #expect(handle.width >= 3)
}

@Test func annotationGeometrySmoothsJitterButRetainsEndpoints() {
    let points = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 10, y: 0.8),
        CGPoint(x: 11, y: -0.7),
        CGPoint(x: 20, y: 0)
    ]
    let smooth = AnnotationGeometry.smoothedPath(points, minimumDistance: 0.5)

    #expect(smooth.first == points.first)
    #expect(smooth.last == points.last)
    #expect(smooth.count <= points.count)
}
