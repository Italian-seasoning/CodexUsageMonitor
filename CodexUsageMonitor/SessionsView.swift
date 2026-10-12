import SwiftUI

struct SessionsView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth
    var compact = false
    var onSelectActivity: ((String) -> Void)? = nil
    @State private var range = SessionRange.thirtyDays
    @State private var search = ""
    @State private var sort = SessionSort.recent
    @State private var selectedSession: CodexSessionSummary?

    private var sessions: [CodexSessionSummary] {
        SessionBrowser.filtered(snapshot.recentSessions, range: range, search: search, sort: sort)
    }
    private var days: [SessionDay] {
        Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.updatedAt) }
            .map { SessionDay(date: $0.key, sessions: sort.sorted($0.value)) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            if compact {
                Picker("Range", selection: $range) {
                    ForEach(SessionRange.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                    .padding(.horizontal, 18).padding(.top, 8)
            } else {
                AppSectionHeader(section: .sessions) {
                    Picker("Range", selection: $range) {
                        ForEach(SessionRange.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 176)
                }
            }
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a chat or model", text: $search)
                        .textFieldStyle(.plain).accessibilityLabel("Search chats")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                    Menu {
                        Picker("Order within each day", selection: $sort) {
                            ForEach(SessionSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Order within each day: \(sort.rawValue)").accessibilityLabel("Sort chats")
                }
                .font(.system(size: 12)).padding(10).appGlassPanel(cornerRadius: 10)
                HStack {
                    Text("\(Set(sessions.map(\.sessionID)).count) chats")
                    Spacer()
                    Text("\(sessions.reduce(0) { $0 + $1.usage.total }.compactTokenString) tokens").monospacedDigit()
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.vertical, 12)

            if sessions.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No recorded chats" : "No matching chats",
                    systemImage: search.isEmpty ? "rectangle.stack" : "magnifyingglass",
                    description: Text(search.isEmpty ? "Try a wider range. Chats appear after local usage is recorded."
                        : "Try another chat name or model, or choose a wider range.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(day.title)
                                    Spacer()
                                    Text(day.sessions.reduce(0) { $0 + $1.usage.total }.compactTokenString).monospacedDigit()
                                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                ForEach(day.sessions) { session in
                                    Button { selectedSession = session } label: { SessionRow(session: session) }
                                        .buttonStyle(.plain).help("Inspect \(session.displayTitle)")
                                }
                            }
                        }
                        Text("Each row shows a chat’s usage for that day. API estimates are not subscription spending.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.horizontal, 18).padding(.bottom, 18)
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session,
                activity: snapshot.sessionActivity.first { $0.id == session.sessionID },
                onSelectActivity: onSelectActivity)
        }
    }
}

private struct SessionDay: Identifiable {
    var date: Date
    var sessions: [CodexSessionSummary]
    var id: Date { date }
    var title: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

private struct SessionRow: View {
    var session: CodexSessionSummary
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text(ModelPricingCatalog.displayName(for: session.model))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.turns.formatted()) \(session.turns == 1 ? "request" : "requests")")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(session.usage.total.compactTokenString).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("tokens").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(session.estimatedCostUSD?.compactCurrencyString ?? "Unpriced")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.monospacedDigit()
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary).padding(.top, 4)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .appGlassPanel(cornerRadius: 12).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}

private struct SessionDetailView: View {
    var session: CodexSessionSummary
    var activity: CodexSessionActivity?
    var onSelectActivity: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.displayTitle).font(.system(size: 20, weight: .semibold)).lineLimit(3)
                    Text(session.updatedAt.formatted(.dateTime.month(.wide).day().year()))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InspectorSection(title: "Recorded usage", subtitle: "For this day") {
                        row("Model", ModelPricingCatalog.displayName(for: session.model))
                        row("Tokens", session.usage.total.formatted())
                        row("Requests", session.turns.formatted())
                        row("API estimate", session.estimatedCostUSD?.compactCurrencyString ?? "Unpriced")
                        row("First activity", session.startedAt.formatted(date: .omitted, time: .shortened))
                        row("Last activity", session.updatedAt.formatted(date: .omitted, time: .shortened))
                    }
                    InspectorSection(title: "Token breakdown") {
                        row("Input", session.usage.input.formatted())
                        row("Cached input", session.usage.cachedInput.formatted())
                        row("Output", session.usage.output.formatted())
                        row("Reasoning output", session.usage.reasoningOutput.formatted())
                        Text("Cached input is part of input. Reasoning is part of output.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if let activity {
                        InspectorSection(title: "Latest chat activity") {
                            row("Status", activity.status())
                            if let project = activity.project { row("Project", project) }
                            if let count = activity.toolCalls { row("Tool calls", count.formatted()) }
                            if let count = activity.toolFailures { row("Tool failures", count.formatted()) }
                        }
                        if let onSelectActivity {
                            Button("View chat activity", systemImage: "waveform.path") {
                                dismiss(); onSelectActivity(session.sessionID)
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                    Text("Session ID: \(session.sessionID)")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("API estimates use recorded model rates and do not represent subscription spending.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }.padding(20).frame(minWidth: 360, idealWidth: 420, maxWidth: 520, minHeight: 440, idealHeight: 540)
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 12)).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label), \(value)")
    }
}

enum SessionSort: String, CaseIterable, Identifiable {
    case recent = "Most recent", tokens = "Most tokens", cost = "Highest API estimate"
    var id: Self { self }
    func sorted(_ sessions: [CodexSessionSummary]) -> [CodexSessionSummary] {
        sessions.sorted {
            let a = self == .tokens ? Double($0.usage.total) : $0.sortableEstimatedCostUSD
            let b = self == .tokens ? Double($1.usage.total) : $1.sortableEstimatedCostUSD
            if self != .recent, a != b { return a > b }
            return $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
    }
}

enum SessionBrowser {
    static func filtered(_ sessions: [CodexSessionSummary], range: SessionRange, search: String,
                         sort: SessionSort, now: Date = .now) -> [CodexSessionSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return sort.sorted(sessions.filter { session in
            range.includes(session.updatedAt, now: now) && (query.isEmpty
                || [session.displayTitle, ModelPricingCatalog.displayName(for: session.model), session.model, session.sessionID]
                    .contains { $0.localizedStandardContains(query) })
        })
    }
}

enum SessionRange: String, CaseIterable, Identifiable {
    case today, sevenDays, thirtyDays
    var id: Self { self }
    var title: String {
        switch self { case .today: "Today"; case .sevenDays: "7 Days"; case .thirtyDays: "30 Days" }
    }
    func includes(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        let today = calendar.startOfDay(for: now)
        let days = switch self { case .today: 1; case .sevenDays: 7; case .thirtyDays: 30 }
        let start = calendar.date(byAdding: .day, value: 1 - days, to: today) ?? today
        return date >= start && date <= now
    }
}
