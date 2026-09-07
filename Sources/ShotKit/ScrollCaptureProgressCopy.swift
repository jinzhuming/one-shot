import Foundation

public enum ScrollCaptureScreenCount: Equatable, Sendable {
    case halfScreen
    case exactScreens(Int)
    case approximateScreens(Double)
}

/// Converts stitched output height into a product-facing screen count.
public enum ScrollCaptureProgressCopy {
    public static func screenCount(
        outputHeightPixels: Int,
        viewportHeightPixels: Int
    ) -> ScrollCaptureScreenCount? {
        guard outputHeightPixels > 0, viewportHeightPixels > 0 else { return nil }
        let screens = Double(outputHeightPixels) / Double(viewportHeightPixels)
        guard screens.isFinite, screens > 0 else { return nil }
        if screens < 1 {
            return .halfScreen
        }
        let nearest = screens.rounded()
        if abs(screens - nearest) < 0.05 {
            return .exactScreens(Int(nearest))
        }
        return .approximateScreens((screens * 10).rounded() / 10)
    }
}
