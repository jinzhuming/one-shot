import CoreGraphics
import Foundation

public enum WindowInclusion {
    public static let minimumSize: CGFloat = 40
    public static let maxLayer = 24

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
}
