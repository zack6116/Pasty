import CoreGraphics
import Foundation

public enum ScrollSelection {
    public static let preciseThreshold: CGFloat = 40
    public static let lineThreshold: CGFloat = 1

    /// Upward scroll (positive `deltaY`) matches the left arrow. Downward scroll matches the right arrow.
    public static func consume(deltaY: CGFloat, precise: Bool, accumulated: inout CGFloat) -> Int {
        guard deltaY.isFinite, deltaY != 0 else { return 0 }
        accumulated += deltaY
        let threshold = precise ? preciseThreshold : lineThreshold
        var steps = 0
        while accumulated >= threshold {
            accumulated -= threshold
            steps -= 1
        }
        while accumulated <= -threshold {
            accumulated += threshold
            steps += 1
        }
        return steps
    }
}
