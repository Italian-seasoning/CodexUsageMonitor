import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

struct WidgetsView: View {
    var snapshot: CodexUsageSnapshot

    @State private var selectedSize = CodexUsageWidgetSize.medium
    @State private var configurations = DesktopWidgetConfigurationsStore.load()
    @State private var configuredSizes: Set<CodexUsageWidgetSize> = []
    @State private var wallpaper: NSImage?
    @State private var customBackgroundImage: NSImage?
    @State private var backgroundImportError: String?
    @State private var preset = WidgetPresetMode.custom
    @State private var savedPresets = SavedWidgetPresetStore.load()
    @State private var savedPresetID: UUID?
    @State private var presetName = ""

    var body: some View {
        pageContent
            .task {
                loadWallpaper()
                loadCustomBackgroundImage()
                refreshConfiguredSizes()
            }
            .alert(
                "Couldn’t Use Image",
                isPresented: Binding(
                    get: { backgroundImportError != nil },
                    set: { if !$0 { backgroundImportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backgroundImportError ?? "Choose another image and try again.")
            }
    }

    private var pageContent: some View {
        VStack(spacing: 0) {
            pageHeader
            workspace
        }
    }

    private var pageHeader: some View {
        AppSectionHeader(section: .widgets) {
            Text("Configured in Codex Usage")
                .font(.system(size: AppTypeScale.label, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
        }
    }

    private var workspace: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                controls
                    .frame(width: 310)

                preview
                    .frame(maxWidth: .infinity, minHeight: 448)
            }
            .padding(16)
        }
    }

    private var preview: some View {
        DesktopWidgetPreview(
            snapshot: snapshot,
            configuration: currentConfiguration,
            size: selectedSize,
            wallpaper: wallpaper,
            customBackground: customBackgroundImage,
            isConfigured: configuredSizes.contains(selectedSize)
        )
    }

    private var controls: some View {
        VStack(spacing: 12) {
            sizeControls
            contentControls
            appearanceControls
        }
    }

    private var sizeControls: some View {
        InspectorSection(
            title: "Desktop size",
            subtitle: "Each size keeps its own content and appearance."
        ) {
                Picker("Desktop size", selection: sizeBinding) {
                    ForEach(CodexUsageWidgetSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                HStack(spacing: 6) {
                    Circle()
                        .fill(configuredSizes.contains(selectedSize) ? AppPalette.positive : AppPalette.muted)
                        .frame(width: 6, height: 6)
                    Text(configuredSizes.contains(selectedSize) ? "Detected on this Mac" : "Preview only")
                        .font(.system(size: AppTypeScale.caption, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }
        }
    }

    private var contentControls: some View {
        InspectorSection(title: "Content") {
                LabeledContent("Widget") {
                    Picker("Widget", selection: configurationBinding(\WidgetDisplayConfiguration.family)) {
                        ForEach(CodexWidgetFamily.allCases) { family in
                            Label(family.title, systemImage: family.symbol).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                if currentConfiguration.family.supportsPeriod {
                    LabeledContent("Period") {
                        Picker("Period", selection: configurationBinding(\WidgetDisplayConfiguration.period)) {
                            ForEach(UsagePeriod.allCases) { period in
                                Text(period.title).tag(period)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 165)
                    }
                }

                if currentConfiguration.family == .dashboard {
                    LabeledContent("Arrangement") {
                        Picker("Arrangement", selection: configurationBinding(\WidgetDisplayConfiguration.dashboardArrangement)) {
                            ForEach(DashboardArrangement.allCases) { arrangement in
                                Text(arrangement.title).tag(arrangement)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 165)
                    }
                }

                Text(currentConfiguration.family.detail)
                    .font(.system(size: AppTypeScale.caption))
                    .foregroundStyle(AppPalette.muted)
        }
    }

    private var appearanceControls: some View {
        InspectorSection(title: "Appearance") {
                LabeledContent("Preset") {
                    Picker("Preset", selection: presetBinding) {
                        ForEach(WidgetPresetMode.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                if preset == .saved {
                    LabeledContent("Saved mix") {
                        Picker("Saved mix", selection: savedPresetBinding) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(savedPresets) { item in
                                Text(item.name).tag(Optional(item.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 165)
                    }
                }

                LabeledContent("Style") {
                    Picker("Style", selection: configurationBinding(\WidgetDisplayConfiguration.style)) {
                        ForEach(CodexWidgetStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                LabeledContent("Theme") {
                    Picker("Theme", selection: configurationBinding(\WidgetDisplayConfiguration.theme)) {
                        ForEach(WidgetTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                LabeledContent("Background") {
                    HStack(spacing: 8) {
                        Button(currentConfiguration.backgroundMode == .customImage ? "Replace…" : "Choose Image…") {
                            chooseBackgroundImage()
                        }
                        if currentConfiguration.backgroundMode == .customImage {
                            Button {
                                removeBackgroundImage()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove custom background")
                        }
                    }
                    .frame(width: 165, alignment: .leading)
                }

                Divider().overlay(AppPalette.divider)

                LabeledContent("Save mix") {
                    HStack(spacing: 6) {
                        TextField("Name", text: $presetName)
                        Button("Save") { savePreset() }
                            .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .frame(width: 165)
                }

                if preset == .saved, savedPresetID != nil {
                    Button("Delete selected preset", role: .destructive) {
                        deleteSelectedPreset()
                    }
                    .buttonStyle(.borderless)
                }
        }
    }

    private var currentConfiguration: WidgetDisplayConfiguration {
        configurations.configuration(for: selectedSize)
    }

    private var sizeBinding: Binding<CodexUsageWidgetSize> {
        Binding(
            get: { selectedSize },
            set: { size in
                selectedSize = size
                loadCustomBackgroundImage(for: size)
                preset = .custom
                savedPresetID = nil
            }
        )
    }

    private var presetBinding: Binding<WidgetPresetMode> {
        Binding(
            get: { preset },
            set: { value in
                preset = value
                applyPreset(value)
            }
        )
    }

    private var savedPresetBinding: Binding<UUID?> {
        Binding(
            get: { savedPresetID },
            set: { value in
                savedPresetID = value
                if preset == .saved {
                    applyPreset(.saved)
                }
            }
        )
    }

    private func configurationBinding<Value>(
        _ keyPath: WritableKeyPath<WidgetDisplayConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { currentConfiguration[keyPath: keyPath] },
            set: { value in
                var configuration = currentConfiguration
                configuration[keyPath: keyPath] = value
                save(configuration)
                preset = .custom
            }
        )
    }

    private func save(_ configuration: WidgetDisplayConfiguration) {
        configurations.set(configuration, for: selectedSize)
        guard DesktopWidgetConfigurationsStore.save(configurations) else { return }
        CodexWidgetReloader.reloadAll()
    }

    private func applyPreset(_ requestedPreset: WidgetPresetMode? = nil) {
        let selectedPreset = requestedPreset ?? preset
        guard selectedPreset != .custom else { return }
        let saved = savedPresets.first { $0.id == savedPresetID }
        let appearance = selectedPreset.presentation(
            savedPreset: saved,
            customStyle: currentConfiguration.style,
            customTheme: currentConfiguration.theme
        )
        var configuration = currentConfiguration
        configuration.style = appearance.style
        configuration.theme = appearance.theme
        save(configuration)
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = savedPresets.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }?.id ?? UUID()
        savedPresets.removeAll { $0.id == id }
        savedPresets.append(
            SavedWidgetPreset(
                id: id,
                name: name,
                style: currentConfiguration.style,
                theme: currentConfiguration.theme
            )
        )
        savedPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        SavedWidgetPresetStore.save(savedPresets)
        savedPresetID = id
        presetName = ""
        preset = .saved
    }

    private func deleteSelectedPreset() {
        guard let savedPresetID else { return }
        savedPresets.removeAll { $0.id == savedPresetID }
        SavedWidgetPresetStore.save(savedPresets)
        self.savedPresetID = nil
        preset = .custom
    }

    private func loadWallpaper() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return }
        wallpaper = NSImage(contentsOf: url)
    }

    private func loadCustomBackgroundImage(for size: CodexUsageWidgetSize? = nil) {
        customBackgroundImage = NSImage(
            contentsOf: WidgetBackgroundImageStore.url(for: size ?? selectedSize)
        )
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            customBackgroundImage = try WidgetBackgroundImageImporter.importImage(
                from: sourceURL,
                for: selectedSize
            )
            var configuration = currentConfiguration
            configuration.backgroundMode = .customImage
            save(configuration)
        } catch {
            backgroundImportError = error.localizedDescription
        }
    }

    private func removeBackgroundImage() {
        let url = WidgetBackgroundImageStore.url(for: selectedSize)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            customBackgroundImage = nil
            var configuration = currentConfiguration
            configuration.backgroundMode = .styled
            save(configuration)
        } catch {
            backgroundImportError = error.localizedDescription
        }
    }

    private func refreshConfiguredSizes() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case let .success(infos) = result else { return }
            let sizes = Set(
                infos.compactMap { info -> CodexUsageWidgetSize? in
                    guard CodexWidgetKind.all.contains(info.kind) else { return nil }
                    return info.family.desktopWidgetSize
                }
            )
            DispatchQueue.main.async {
                configuredSizes = sizes
            }
        }
    }
}

private struct DesktopWidgetPreview: View {
    var snapshot: CodexUsageSnapshot
    var configuration: WidgetDisplayConfiguration
    var size: CodexUsageWidgetSize
    var wallpaper: NSImage?
    var customBackground: NSImage?
    var isConfigured: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            desktopBackground

            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 25)

            HStack(spacing: 6) {
                Circle().fill(.white.opacity(0.82)).frame(width: 4, height: 4)
                Text("Desktop · top-left preview")
                    .font(.system(size: AppTypeScale.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Label(isConfigured ? "On desktop" : "Preview", systemImage: isConfigured ? "checkmark.circle.fill" : "eye")
                    .font(.system(size: AppTypeScale.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 12)
            .frame(height: 25)

            widget
                .padding(.leading, 28)
                .padding(.top, 48)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.panelBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Top-left desktop preview for the (size.title) Codex Usage widget")
    }

    @ViewBuilder
    private var desktopBackground: some View {
        if let wallpaper {
            GeometryReader { geometry in
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.28, anchor: .topLeading)
                    .overlay(Color.black.opacity(0.13))
                    .clipped()
            }
        } else {
            LinearGradient(
                colors: [AppPalette.gradientLeading.opacity(0.78), AppPalette.windowTint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var widget: some View {
        ZStack {
            widgetBackground
            CodexWidgetFamilyView(
                snapshot: snapshot,
                configuration: configuration,
                size: size.cardSize,
                monochrome: configuration.theme == .monochrome
            )
        }
        .frame(width: size.previewFrame.width, height: size.previewFrame.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if usesCustomBackground, let customBackground {
            CodexWidgetCustomImageBackground(image: customBackground)
        } else {
            CodexWidgetStyleBackground(
                style: configuration.style,
                theme: configuration.theme,
                monochrome: configuration.theme == .monochrome
            )
        }
    }

    private var usesCustomBackground: Bool {
        configuration.backgroundMode == .customImage && customBackground != nil
    }
}

private enum WidgetBackgroundImageImporter {
    enum ImportError: LocalizedError {
        case unreadableImage
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "That file isn’t a readable image."
            case .encodingFailed: "The image couldn’t be prepared for WidgetKit."
            }
        }
    }

    static func importImage(from sourceURL: URL, for size: CodexUsageWidgetSize) throws -> NSImage {
        guard let source = NSImage(contentsOf: sourceURL),
              source.size.width > 0,
              source.size.height > 0
        else {
            throw ImportError.unreadableImage
        }

        let maximumDimension: CGFloat = 1_200
        let scale = min(1, maximumDimension / max(source.size.width, source.size.height))
        let targetSize = NSSize(
            width: max(1, source.size.width * scale),
            height: max(1, source.size.height * scale)
        )
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.84]
              )
        else {
            throw ImportError.encodingFailed
        }

        let destination = WidgetBackgroundImageStore.url(for: size)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return NSImage(data: data) ?? resized
    }
}

private extension WidgetFamily {
    var desktopWidgetSize: CodexUsageWidgetSize {
        switch self {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }
}

private extension CodexUsageWidgetSize {
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var previewFrame: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 340, height: 170)
        case .large: CGSize(width: 340, height: 340)
        }
    }

    var cardSize: CodexUsageCardSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }
}

private extension CodexWidgetFamily {
    var title: String {
        switch self {
        case .limits: "Limits"
        case .usagePulse: "Usage Pulse"
        case .costLens: "Cost Lens"
        case .modelMix: "Model Mix"
        case .headroomImpact: "Headroom Impact"
        case .sessionLive: "Session Live"
        case .dashboard: "Dashboard"
        }
    }

    var symbol: String {
        switch self {
        case .limits: "gauge.with.dots.needle.67percent"
        case .usagePulse: "waveform.path.ecg"
        case .costLens: "dollarsign.circle"
        case .modelMix: "square.stack.3d.up"
        case .headroomImpact: "arrow.down.right.and.arrow.up.left"
        case .sessionLive: "bolt.horizontal.circle"
        case .dashboard: "rectangle.3.group"
        }
    }

    var detail: String {
        switch self {
        case .limits: "Remaining 5-hour and weekly allowance."
        case .usagePulse: "Selected-period token activity."
        case .costLens: "Recorded API-equivalent estimate."
        case .modelMix: "Top model and attributed share."
        case .headroomImpact: "Local compression savings."
        case .sessionLive: "Current-session activity and freshness."
        case .dashboard: "A curated multi-metric workspace."
        }
    }

    var supportsPeriod: Bool {
        ![.limits, .sessionLive].contains(self)
    }
}

private extension CodexWidgetStyle {
    var title: String {
        switch self {
        case .precisionInstrument: "Precision Instrument"
        case .nativeGlass: "Native Glass"
        case .signalGrid: "Signal Grid"
        }
    }
}

private extension WidgetPresetMode {
    var title: String {
        switch self {
        case .summer: "Summer"
        case .classicRed: "Classic Red"
        case .darkGlass: "Dark Glass"
        case .frosted: "Frosted Coast"
        case .signal: "Signal"
        case .saved: "Saved Preset"
        case .custom: "Custom"
        }
    }
}

private extension DashboardArrangement {
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .limitsFirst: "Limits First"
        case .activityFirst: "Activity First"
        }
    }
}
