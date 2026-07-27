import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .settings) {
                EmptyView()
            }

            ScrollView {
                VStack(spacing: 14) {
                    InspectorSection(title: "Appearance", subtitle: "App and widget defaults stay independent") {
                        LabeledContent("App accent") {
                            Picker("App accent", selection: $settingsModel.settings.appTheme) {
                                ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 165)
                        }
                        LabeledContent("Default widget theme") {
                            Picker("Default widget theme", selection: $settingsModel.settings.defaultWidgetTheme) {
                                ForEach(WidgetTheme.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 165)
                        }
                    }

                    InspectorSection(title: "Application behavior", subtitle: "Menu bar, Dock, background refresh, and notifications") {
                        LimitPreferencesView()
                    }

                    InspectorSection(title: "Setup and updates") {
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
                                Text("Check the configured Sparkle update channel.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Check for Updates…") {
                                updater.checkForUpdates()
                            }
                            .disabled(!updater.canCheckForUpdates)
                        }
                    }
                }
                .frame(maxWidth: 720)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
