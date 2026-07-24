import SwiftUI

struct WidgetStylePalette {
    var primary: Color
    var secondary: Color
    var accent: Color
    var track: Color
    var separator: Color
}

struct CodexWidgetStyledContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var style: CodexWidgetStyle
    var theme: WidgetTheme
    var monochrome: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            CodexWidgetStyleBackground(style: style, theme: theme, monochrome: monochrome)
            if style == .signalGrid {
                WidgetGridTexture(color: palette.separator)
            }
            content
                .padding(style == .signalGrid ? 12 : 15)
        }
        .foregroundStyle(palette.primary)
    }

    var palette: WidgetStylePalette {
        WidgetStylePalette.make(
            style: style,
            theme: theme,
            monochrome: monochrome,
            colorScheme: colorScheme
        )
    }
}

struct CodexWidgetStyleBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var style: CodexWidgetStyle
    var theme: WidgetTheme
    var monochrome: Bool

    var body: some View {
        let palette = WidgetStylePalette.make(
            style: style,
            theme: theme,
            monochrome: monochrome,
            colorScheme: colorScheme
        )

        switch style {
        case .precisionInstrument:
            LinearGradient(
                colors: [Color(red: 0.055, green: 0.058, blue: 0.07), Color(red: 0.025, green: 0.028, blue: 0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .nativeGlass:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [palette.accent.opacity(monochrome ? 0 : 0.14), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .signalGrid:
            Color(red: 0.045, green: 0.05, blue: 0.062)
        }
    }
}

extension WidgetStylePalette {
    static func make(
        style: CodexWidgetStyle,
        theme: WidgetTheme,
        monochrome: Bool,
        colorScheme: ColorScheme
    ) -> Self {
        let light = style == .nativeGlass && theme == .frostedWhite && colorScheme == .light
        let primary: Color = light ? .black : .white
        let accent: Color
        if monochrome || theme == .monochrome {
            accent = primary
        } else if theme == .crimson {
            accent = Color(red: 1, green: 0.388, blue: 0.388)
        } else {
            accent = Color(red: 0.34, green: 0.64, blue: 1)
        }
        return WidgetStylePalette(
            primary: primary,
            secondary: primary.opacity(light ? 0.62 : 0.67),
            accent: accent,
            track: primary.opacity(light ? 0.12 : 0.2),
            separator: primary.opacity(light ? 0.1 : 0.11)
        )
    }
}

private struct WidgetGridTexture: View {
    var color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                stride(from: 0.0, through: geometry.size.width, by: 18).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                stride(from: 0.0, through: geometry.size.height, by: 18).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(color.opacity(0.45), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
