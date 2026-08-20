import SwiftUI

struct SessionsView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth

    @State private var range = SessionRange.sevenDays
    @State private var sortOrder = [
        KeyPathComparator(\CodexSessionSummary.updatedAt, order: .reverse)
    ]

    private var sessions: [CodexSessionSummary] {
        snapshot.recentSessions
            .filter { range.includes($0.updatedAt) }
            .sorted(using: sortOrder)
    }

    private var totalTokens: Int {
        sessions.reduce(0) { $0 + $1.usage.total }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .sessions) {
                Picker("Range", selection: $range) {
                    ForEach(SessionRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 176)
            }

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Label(
                        "\(sessions.count) \(sessions.count == 1 ? "session" : "sessions")",
                        systemImage: "rectangle.stack"
                    )
                    Spacer()
                    Text("\(totalTokens.compactTokenString) tokens")
                        .monospacedDigit()
                }
                .font(.system(size: AppTypeScale.label, weight: .semibold))
                .foregroundStyle(AppPalette.muted)

                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No sessions in this range",
                        systemImage: "rectangle.stack.badge.minus",
                        description: Text(health.detail)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appGlassPanel(cornerRadius: 16)
                } else {
                    Table(sessions, sortOrder: $sortOrder) {
                        TableColumn("Last active", value: \CodexSessionSummary.updatedAt) { session in
                            Text(session.updatedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        }
                        .width(min: 165, ideal: 190)

                        TableColumn("Model", value: \CodexSessionSummary.model) { session in
                            Text(ModelPricingCatalog.displayName(for: session.model))
                                .lineLimit(1)
                        }
                        .width(min: 130, ideal: 170)

                        TableColumn("Requests", value: \CodexSessionSummary.turns) { session in
                            Text(session.turns.formatted())
                                .monospacedDigit()
                        }
                        .width(min: 72, ideal: 82)

                        TableColumn("Tokens", value: \CodexSessionSummary.usage.total) { session in
                            Text(session.usage.total.compactTokenString)
                                .monospacedDigit()
                        }
                        .width(min: 78, ideal: 92)

                        TableColumn("Est. API cost", value: \CodexSessionSummary.sortableEstimatedCostUSD) { session in
                            Text(session.estimatedCostUSD?.compactCurrencyString ?? "Unpriced")
                                .monospacedDigit()
                        }
                        .width(min: 92, ideal: 110)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    .scrollContentBackground(.hidden)
                    .appGlassPanel(cornerRadius: 16)
                }

                Text("Local session metadata only. Costs use recorded model rates and are not subscription spend.")
                    .font(.system(size: AppTypeScale.caption, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }
}

private enum SessionRange: String, CaseIterable, Identifiable {
    case today
    case sevenDays

    var id: Self { self }
    var title: String { self == .today ? "Today" : "7 Days" }

    func includes(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        let today = calendar.startOfDay(for: now)
        let start = self == .today
            ? today
            : calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return date >= start && date <= now
    }
}
