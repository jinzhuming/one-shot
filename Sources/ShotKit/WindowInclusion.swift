import CoreGraphics
import Foundation

public enum WindowInclusion {
    public static let minimumSize: CGFloat = 40
    /// Window capture targets ordinary application windows. System-owned
    /// layers such as Dock (layer 20) and the menu bar (layer 24) can cover
    /// the entire display and would otherwise win hover hit-testing.
    public static let maxLayer = 0

    public static func shouldInclude(
        layer: Int,
        size: CGSize,
        processID: pid_t,
        ourPID: pid_t
    ) -> Bool {
        if processID == ourPID { return false }
        if size.width < minimumSize || size.height < minimumSize { return false }
        if layer < 0 || layer > maxLayer { return false }
        return true
    }

    public static func isShareable(
        windowID: CGWindowID,
        in shareableWindowIDs: Set<CGWindowID>
    ) -> Bool {
        shareableWindowIDs.contains(windowID)
    }
}
