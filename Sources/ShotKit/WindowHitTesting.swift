import CoreGraphics

public enum WindowHitTesting {
    public static func containing(_ point: CGPoint, in frames: [CGRect]) -> [Int] {
        frames.indices.filter { frames[$0].insetBy(dx: -1, dy: -1).contains(point) }
    }

    public static func cycledIndex(current: Int, count: Int, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }
        if reverse {
            return (current - 1 + count) % count
        }
        return (current + 1) % count
    }
}
