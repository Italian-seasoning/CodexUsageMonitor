import SwiftUI

private struct CursorGlowBorder: ViewModifier {
    let radius: CGFloat
    let accent: Color
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorLocation = CGPoint.zero
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay { glowStroke(lineWidth: 1.2, blur: 0, opacity: activeOpacity) }
            .overlay { glowStroke(lineWidth: 7, blur: 6, opacity: activeOpacity * 0.42) }
            .onContinuousHover { phase in
                guard isEnabled else {
                    isHovering = false
                    return
                }
                switch phase {
                case .active(let location):
                    cursorLocation = location
                    if !isHovering {
                        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.16)) {
                            isHovering = true
                        }
                    }
                case .ended:
                    withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.22)) {
                        isHovering = false
                    }
                }
            }
    }

    private func glowStroke(lineWidth: CGFloat, blur: CGFloat, opacity: Double) -> some View {
        GeometryReader { proxy in
            let center = UnitPoint(
                x: normalized(cursorLocation.x, within: proxy.size.width),
                y: normalized(cursorLocation.y, within: proxy.size.height)
            )
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    RadialGradient(
                        colors: [accent, Color.white.opacity(0.56), accent.opacity(0.2), .clear],
                        center: center,
                        startRadius: 0,
                        endRadius: max(max(proxy.size.width, proxy.size.height) * 0.48, 90)
                    ),
                    lineWidth: lineWidth
                )
                .blur(radius: blur)
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }

    private var activeOpacity: Double {
        isEnabled && isHovering ? 1 : 0
    }

    private func normalized(_ value: CGFloat, within length: CGFloat) -> CGFloat {
        guard length > 0 else { return 0.5 }
        return min(max(value / length, 0), 1)
    }
}

extension View {
    func cursorGlowBorder(radius: CGFloat, accent: Color, isEnabled: Bool = true) -> some View {
        modifier(CursorGlowBorder(radius: radius, accent: accent, isEnabled: isEnabled))
    }
}

