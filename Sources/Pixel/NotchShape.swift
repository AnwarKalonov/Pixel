import SwiftUI

// MARK: - Authentic boring.notch NotchShape
// Follows boringNotch / DynamicNotchKit implementation exactly:
// Smooth outer top corners (connecting seamlessly to the physical display bezel)
// and smooth continuous bottom corners.
public struct NotchShape: Shape, Animatable {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public init(
        topCornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat = 14
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left curve
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // Bottom-left curve
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom-right curve
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // Top-right curve
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // Top edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

// MARK: - Boring Notch Background Styling
public struct BoringNotchBackground: View {
    public var expansionLevel: ExpansionLevel
    public var cornerRadius: CGFloat

    public init(expansionLevel: ExpansionLevel, cornerRadius: CGFloat = 14) {
        self.expansionLevel = expansionLevel
        self.cornerRadius = cornerRadius
    }

    private var topRadius: CGFloat {
        switch expansionLevel {
        case .closed: return 6
        case .hoverPeek: return 10
        case .expanded: return 14
        }
    }

    private var bottomRadius: CGFloat {
        switch expansionLevel {
        case .closed: return 14
        case .hoverPeek: return 18
        case .expanded: return 24
        }
    }

    public var body: some View {
        ZStack {
            // 1. OLED Pure Black Base
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .fill(Color.black)

            // 2. Translucent Glass Tint for expanded levels (boring.notch look)
            if expansionLevel != .closed {
                NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(0.85)

                NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(white: 0.16, opacity: 0.92), location: 0),
                                .init(color: Color(white: 0.08, opacity: 0.98), location: 0.45),
                                .init(color: Color(white: 0.04, opacity: 1.0), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // 3. Crisp Specular Rim Light (boring.notch signature)
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(expansionLevel == .closed ? 0.0 : 0.35), location: 0),
                            .init(color: Color.white.opacity(expansionLevel == .closed ? 0.0 : 0.12), location: 0.4),
                            .init(color: Color.white.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: Color.black.opacity(expansionLevel == .expanded ? 0.6 : (expansionLevel == .hoverPeek ? 0.35 : 0)),
            radius: expansionLevel == .expanded ? 28 : 12,
            x: 0,
            y: expansionLevel == .expanded ? 12 : 5
        )
    }
}
