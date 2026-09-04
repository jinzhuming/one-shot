import CoreGraphics

public enum OverlayModeKind: Equatable, Sendable {
    case area
    case window
    case other
}

/// Area ↔ window switching while the capture overlay is up.
/// Space (or a custom key) toggles when not dragging; a click with no selection
/// enters window mode; dragging in window mode returns to area selection.
public enum OverlayModeSwitch {
    public static let dragThreshold: CGFloat = 4

    public static func toggled(from kind: OverlayModeKind) -> OverlayModeKind? {
        switch kind {
        case .area: return .window
        case .window: return .area
        case .other: return nil
        }
    }

    public static func clickWithoutDragEntersWindow(
        kind: OverlayModeKind,
        isDragging: Bool
    ) -> Bool {
        kind == .area && !isDragging
    }

    public static func dragEntersArea(kind: OverlayModeKind, distance: CGFloat) -> Bool {
        kind == .window && distance > dragThreshold
    }
}
