import SwiftUI

struct SessionsView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth

    @State private var range = SessionRange.thirtyDays

    private var sessions: [CodexSessionSummary] {
        snapshot.recentSessions
            .filter { range.includes($0.updatedAt) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var sessionDays: [SessionDay] {
        Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.updatedAt) }
            .map { SessionDay(date: $0.key, sessions: $0.value) }
            .sorted { $0.date > $1.date }
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
                        "\(sessions.count) \(sessions.count == 1 ? "chat period" : "chat periods")",
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
                    List {
                        ForEach(sessionDays) { day in
                            Section {
                                ForEach(day.sessions) { session in
                                    SessionRow(session: session)
                                }
                            } header: {
                                Text(day.headerTitle)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .accessibilityLabel(day.headerTitle)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                    .listStyle(.inset)
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

private struct SessionDay: Identifiable {
    var date: Date
    var sessions: [CodexSessionSummary]

    var id: Date { date }
    var totalTokens: Int { sessions.reduce(0) { $0 + $1.usage.total } }
    var headerTitle: String {
        "\(date.formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(sessions.count) \(sessions.count == 1 ? "chat" : "chats") · \(totalTokens.compactTokenString) tokens"
    }
}

private struct SessionRow: View {
    var session: CodexSessionSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(timeRange)
                    .font(.system(size: AppTypeScale.label, weight: .semibold))
                    .monospacedDigit()
                Text("\(ModelPricingCatalog.displayName(for: session.model)) · \(session.turns.formatted()) \(session.turns == 1 ? "request" : "requests")")
                    .font(.system(size: AppTypeScale.caption, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(session.usage.total.compactTokenString) tokens")
                    .font(.system(size: AppTypeScale.label, weight: .semibold))
                    .monospacedDigit()
                Text(session.estimatedCostUSD?.compactCurrencyString ?? "Unpriced")
                    .font(.system(size: AppTypeScale.caption, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var timeRange: String {
        let start = session.startedAt.formatted(date: .omitted, time: .shortened)
        let end = session.updatedAt.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start)–\(end)"
    }
}

private enum SessionRange: String, CaseIterable, Identifiable {
    case today
    case sevenDays
    case thirtyDays

    var id: Self { self }
    var title: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7 Days"
        case .thirtyDays: "30 Days"
        }
    }

    func includes(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        let today = calendar.startOfDay(for: now)
        let days = switch self {
        case .today: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        }
        let start = calendar.date(byAdding: .day, value: 1 - days, to: today) ?? today
        return date >= start && date <= now
    }
}
