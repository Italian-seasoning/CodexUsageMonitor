import AppKit
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
    var paintsBackground = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            if paintsBackground {
                CodexWidgetStyleBackground(style: style, theme: theme, monochrome: monochrome)
            }
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
            let colors = switch theme {
            case .crimson:
                [Color(red: 0.025, green: 0.25, blue: 0.28), Color(red: 0.015, green: 0.08, blue: 0.13)]
            case .classicRed:
                [Color(red: 0.065, green: 0.058, blue: 0.062), Color(red: 0.018, green: 0.018, blue: 0.022)]
            default:
                [Color(red: 0.055, green: 0.058, blue: 0.07), Color(red: 0.025, green: 0.028, blue: 0.035)]
            }
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .nativeGlass:
            let base = switch theme {
            case .frostedWhite where colorScheme == .light: Color(red: 0.95, green: 0.96, blue: 0.98)
            case .crimson: Color(red: 0.035, green: 0.19, blue: 0.22)
            case .classicRed: Color(red: 0.095, green: 0.09, blue: 0.10)
            default: Color(red: 0.13, green: 0.14, blue: 0.17)
            }
            ZStack {
                base
                LinearGradient(
                    colors: [
                        palette.accent.opacity(monochrome ? 0 : 0.18),
                        Color.white.opacity(colorScheme == .dark ? 0.035 : 0.16),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .signalGrid:
            switch theme {
            case .crimson: Color(red: 0.018, green: 0.12, blue: 0.16)
            case .classicRed: Color(red: 0.028, green: 0.027, blue: 0.032)
            default: Color(red: 0.045, green: 0.05, blue: 0.062)
            }
        }
    }
}

struct CodexWidgetCustomImageBackground: View {
    var image: NSImage

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(Color.black.opacity(0.38))
                .clipped()
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
        let light = !monochrome && style == .nativeGlass && theme == .frostedWhite && colorScheme == .light
        let primary: Color = light ? .black : .white
        let accent: Color
        if monochrome || theme == .monochrome {
            accent = primary
        } else {
            accent = switch theme {
            case .crimson: Color(red: 0.12, green: 0.82, blue: 0.79)
            case .classicRed: Color(red: 1, green: 0.18, blue: 0.23)
            default: Color(red: 0.34, green: 0.64, blue: 1)
            }
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
