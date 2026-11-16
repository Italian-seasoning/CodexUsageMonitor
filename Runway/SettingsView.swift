import ServiceManagement
import SwiftUI

/// Widgets and the Droppy droplet only show what the app last wrote, so Runway
/// opens at login by default. The first launch of an installed copy turns it on once;
/// after that the user's choice in Settings wins.
enum LoginItem {
    private static let configuredKey = "Runway.loginItemConfigured"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        UserDefaults.standard.set(true, forKey: configuredKey)
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Runway login item change failed: \(error.localizedDescription)")
        }
    }

    static func enableOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        set(true)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @ObservedObject private var updater = AppUpdater.shared
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .settings) {
                EmptyView()
            }

            ScrollView {
                VStack(spacing: AppSpacing.sm) {
                    InspectorSection(title: "Appearance") {
                        LabeledContent("App theme") {
                            Picker("App theme", selection: $settingsModel.settings.appTheme) {
                                ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 145)
                        }
                    }

                    InspectorSection(title: "Monitoring") {
                        Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: { value in
                            LoginItem.set(value)
                            openAtLogin = LoginItem.isEnabled
                        }))
                        .help("Keeps widgets and the Droppy droplet current. Runway does no work while Codex is closed.")
                        LimitPreferencesView()
                    }
                    HStack {
                        Text("Created by Italian-seasoning")
                            .foregroundStyle(AppPalette.muted)
                        Spacer()
                        Link("GitHub", destination: URL(string: "https://github.com/Italian-seasoning/CodexUsageMonitor")!)
                    }
                    .font(.system(size: AppTypeScale.caption, weight: .medium))
                    .padding(.horizontal, AppSpacing.xxs)
                    DisclosureGroup("Setup and updates") {
                        VStack(spacing: AppSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Codex data access").font(.system(size: AppTypeScale.body, weight: .semibold))
                                Text("Review folders, permissions, and background behavior.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Run Setup") {
                                NotificationCenter.default.post(name: .showCodexUsageTour, object: nil)
                            }
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Software updates").font(.system(size: AppTypeScale.body, weight: .semibold))
                                Text("Check for a newer version.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Check for Updates…") {
                                updater.checkForUpdates()
                            }
                            .disabled(!updater.canCheckForUpdates)
                        }
                        LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        LabeledContent("Built", value: buildDate)
                        }.padding(.top, AppSpacing.xs)
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.sm)
            }
        }
        .font(.system(size: AppTypeScale.label))
        .controlSize(.small)
    }

    private var buildDate: String {
        guard let executable = Bundle.main.executableURL,
              let values = try? executable.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
