import Foundation
import CoreGraphics

public enum NotchMetrics {
    // MARK: - Level 1: Physical MacBook notch (matches MBP 14" / 16")
    public static let closedWidth: CGFloat  = 160
    public static let closedHeight: CGFloat = 38

    // MARK: - Level 2: Hover Peek compact pill
    public static let peekWidth: CGFloat  = 420
    public static let peekHeight: CGFloat = 52

    // MARK: - Level 3: Full AI Work Deck
    public static let expandedWidth: CGFloat  = 620
    public static let expandedHeight: CGFloat = 500

    // Legacy aliases
    public static var collapsedWidth: CGFloat  { closedWidth }
    public static var collapsedHeight: CGFloat { closedHeight }

    public static func size(for level: ExpansionLevel) -> CGSize {
        switch level {
        case .closed:    return CGSize(width: closedWidth,    height: closedHeight)
        case .hoverPeek: return CGSize(width: peekWidth,      height: peekHeight)
        case .expanded:  return CGSize(width: expandedWidth,  height: expandedHeight)
        }
    }

    // Matching macOS design language — outer top corners tight, inner bottom smooth
    public static func cornerRadius(for level: ExpansionLevel) -> CGFloat {
        switch level {
        case .closed:    return 12
        case .hoverPeek: return 18
        case .expanded:  return 24
        }
    }
}
