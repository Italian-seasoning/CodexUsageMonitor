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
                VStack(spacing: 12) {
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
                        LimitPreferencesView()
                    }
                    HStack {
                        Text("Created by Italian-seasoning")
                            .foregroundStyle(AppPalette.muted)
                        Spacer()
                        Link("GitHub", destination: URL(string: "https://github.com/Italian-seasoning/CodexUsageMonitor")!)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 4)
                    DisclosureGroup("Setup and updates") {
                        VStack(spacing: 12) {
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
                        }.padding(.top, 10)
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(14)
            }
        }
        .font(.system(size: 12))
        .controlSize(.small)
    }

    private var buildDate: String {
        guard let executable = Bundle.main.executableURL,
              let values = try? executable.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
