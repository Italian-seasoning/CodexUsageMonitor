import AppKit
import SwiftUI

// Render actual shared widget views with a real snapshot for visual review.
@main
struct RenderWidgetGallery {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        guard (4...5).contains(arguments.count), let theme = WidgetTheme(rawValue: arguments[2]) else {
            fatalError("Usage: render-widget-gallery snapshot.json theme output.png [style]")
        }
        let style = arguments.count == 5 ? CodexWidgetStyle(rawValue: arguments[4]) ?? .nativeGlass : .nativeGlass
        let output = URL(fileURLWithPath: arguments[3])
        let individualDirectory = output.deletingPathExtension()
        try FileManager.default.createDirectory(at: individualDirectory, withIntermediateDirectories: true)
        let snapshot = try JSONDecoder().decode(CodexUsageSnapshot.self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        let families = CodexWidgetFamily.allCases
        let cellWidth: CGFloat = 370
        let rowHeights: [CGFloat] = [210, 210, 380]
        let canvas = NSImage(size: NSSize(width: cellWidth * CGFloat(families.count), height: rowHeights.reduce(50, +)))
        canvas.lockFocus()
        NSColor(calibratedWhite: 0.065, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas.size).fill()
        ("\(theme.label) · live snapshot · Small / Medium / Large" as NSString).draw(
            at: NSPoint(x: 16, y: canvas.size.height - 32),
            withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 15, weight: .medium)])
        var top = canvas.size.height - 50
        for (row, size) in CodexUsageCardSize.allCases.enumerated() {
            let frame: CGSize = switch size {
            case .small: CGSize(width: 170, height: 170)
            case .medium: CGSize(width: 340, height: 170)
            case .large: CGSize(width: 340, height: 340)
            }
            for (column, family) in families.enumerated() {
                let renderer = ImageRenderer(content: CodexWidgetFamilyView(
                    snapshot: snapshot,
                    configuration: WidgetDisplayConfiguration(family: family, style: style,
                        theme: theme, period: .sevenDays, dashboardArrangement: .activityFirst),
                    size: size, monochrome: theme == .monochrome, paintsBackground: true
                ).frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 22)).environment(\.colorScheme, theme == .frostedWhite ? .light : .dark))
                renderer.scale = 2
                guard let image = renderer.cgImage else { fatalError("Could not render \(family.rawValue)") }
                let individualPNG = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                try individualPNG.write(to: individualDirectory.appendingPathComponent("\(family.rawValue)-\(size).png"))
                let x = cellWidth * CGFloat(column) + 15
                NSImage(cgImage: image, size: frame).draw(in: NSRect(x: x, y: top - frame.height, width: frame.width, height: frame.height))
                (family.rawValue as NSString).draw(at: NSPoint(x: x, y: top - frame.height - 20),
                    withAttributes: [.foregroundColor: NSColor.lightGray, .font: NSFont.systemFont(ofSize: 11)])
            }
            top -= rowHeights[row]
        }
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            fatalError("Could not encode widget gallery")
        }
        try png.write(to: output)
        print("Rendered \(families.count * CodexUsageCardSize.allCases.count) widget layouts: \(arguments[3])")
    }
}
