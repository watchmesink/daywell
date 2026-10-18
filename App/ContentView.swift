import BlockingCore
import DeviceActivity
import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: EditorSheet?
    @State private var usageDay = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    @ScaledMetric(relativeTo: .body) private var selectedUsageHeight = 76
    @ScaledMetric(relativeTo: .caption) private var totalUsageHeight = 48

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    #if targetEnvironment(simulator)
                    inset {
                        Label("Simulator preview · Blocking requires an iPhone.", systemImage: "iphone")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    #endif
                    if let error = model.error { inset { ErrorMessage(message: error) } }
                    if let failure = model.document.lastError, failure != model.error { inset { ErrorMessage(message: failure) } }
                    if model.hasSelection {
                        dashboard
                    } else {
                        onboarding
                    }
                    if model.snapshot.hasPendingChanges { inset { pendingCard } }
                    inset { footer }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(.container, edges: .horizontal)
            .background(Brand.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshUsageDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                refreshUsageDay()
            }
            .sheet(item: $sheet) { editor in
                switch editor {
                case .application: ApplicationEditor()
                case .schedule: ScheduleEditor()
                case .limit: LimitEditor()
                }
            }
        }
    }

    private func inset<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 0) {
                OceanSunsetBackdrop()
                inset {
                    Text("A little more room\nin your day.")
                        .font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-1.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, -24)
            }
            inset {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Set your boundaries once. Daywell keeps them in place, with no skip button when a block is active.")
                        .foregroundStyle(.secondary).font(.body).lineSpacing(4)
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            if model.authorized { sheet = .application }
                            else { Task { await model.authorize() } }
                        } label: {
                            HStack {
                                if model.working { ProgressView().tint(.white) }
                                Text(model.authorized ? "Choose what to block" : "Continue")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(PrimaryButton()).disabled(model.working)
                        Text("Choose apps, categories, and websites to block. Your rules apply to everything selected, and your choices and usage stay on your device.")
                            .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    rulesCard()
                }
            }
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.authorized {
                inset {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Protection needs access", systemImage: "exclamationmark.shield")
                                .font(.headline)
                            Text("Screen Time access is off. Your saved rules remain, but iOS cannot enforce them until you enable access again.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Continue") { Task { await model.authorize() } }
                                .buttonStyle(PrimaryButton()).disabled(model.working)
                        }
                    }
                }
            }
            statusCard
            inset { appCard() }
            inset { rulesCard() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            OceanSunsetBackdrop()
            inset {
                VStack(alignment: .leading, spacing: 18) {
                    // Time updates affect the status copy, not remote reports or cards.
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        statusSummary(model.snapshot.decision(at: context.date, calendar: .autoupdatingCurrent))
                    }
                    if model.authorized, let selection = model.selection, !selection.isEmpty {
                        Divider().overlay(Color.primary.opacity(0.25))
                        usageReports(selection: selection)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, -24)
        }
        .accessibilityIdentifier("protection-status")
    }

    private func statusSummary(_ decision: ShieldDecision) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.authorized ? (decision.isBlocked ? "BLOCK ACTIVE" : model.hasRules ? "TIME AVAILABLE" : "NO RULES SET") : "ACCESS NEEDED",
                  systemImage: model.authorized ? (decision.isBlocked ? "lock.fill" : "checkmark.circle.fill") : "exclamationmark.circle")
                .font(.system(.caption, design: .rounded, weight: .bold)).tracking(1)
            Text(!model.authorized ? "Reconnect\nto your routine." : decision.isBlocked ? "A moment\naway from the screen." : model.hasRules ? "Enjoy your time.\nKeep your limits." : "Make room\nfor your day.")
                .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1)
            if decision.budgetExhausted {
                Text(ProtectionCopy.allowanceUsed).font(.subheadline)
            } else if let next = decision.nextScheduleTransition {
                Text(decision.scheduled ? "Scheduled block ends at \(next, style: .time)." : "Next scheduled block at \(next, style: .time).")
                    .font(.subheadline)
            } else {
                Text(decision.scheduled ? "Your overlapping schedules cover the whole day." : model.hasRules ? "Your daily allowance keeps you on track." : "Add a rule below to start protecting your time.")
                    .font(.subheadline)
            }
        }
    }

    private func appCard() -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeading(title: "Blocked activity")
                    Spacer()
                    Button("Change") { sheet = .application }.font(.subheadline)
                        .disabled(!model.authorized || model.working)
                }
                if let selection = model.selection {
                    Text(selection.summary).font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Selected activity unavailable", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    private func usageReports(selection: FamilyActivitySelection) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let today = usageDay
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let interval = DateInterval(
            start: calendar.date(byAdding: .day, value: -7, to: today)!,
            end: tomorrow)

        return VStack(alignment: .leading, spacing: 4) {
            DeviceActivityReport(.daywellToday, filter: DeviceActivityFilter(
                segment: .daily(during: DateInterval(start: today, end: tomorrow)),
                applications: selection.applicationTokens, categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens))
                .frame(height: selectedUsageHeight)
            DeviceActivityReport(.daywellTotalToday, filter: DeviceActivityFilter(
                segment: .daily(during: interval)))
                .frame(height: totalUsageHeight)
        }
        // Read-only extension hosts must not capture swipes from the dashboard.
        .allowsHitTesting(false)
        .id(model.snapshot.generation)
    }

    private func refreshUsageDay() {
        let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        if usageDay != today { usageDay = today }
    }

    private func rulesCard() -> some View {
        let windows = model.snapshot.policy.windows
        let allowance = model.snapshot.policy.dailyLimitMinutes
        return Card {
            VStack(alignment: .leading, spacing: 18) {
                if !windows.isEmpty {
                    HStack {
                        SectionHeading(title: "Daily blocks")
                        Spacer()
                        Button("Edit") { sheet = .schedule }.font(.subheadline)
                    }
                    ForEach(windows) { window in
                        routineRow(window.startMinute < 720 ? "sun.max" : "moon", "Every day",
                                   "\(timeLabel(window.startMinute)) – \(timeLabel(window.endMinute))")
                    }
                }
                if !windows.isEmpty && allowance != nil { Divider() }
                if let minutes = allowance {
                    HStack {
                        SectionHeading(title: "Shared daily allowance")
                        Spacer()
                        Button("Edit") { sheet = .limit }.font(.subheadline)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(String(minutes))
                            .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("min / day").foregroundStyle(.secondary)
                    }
                    Text(model.hasSelection
                         ? "Time in selected apps, categories, and websites adds up. Increases or removal take effect tomorrow."
                         : "Time in selected apps, categories, and websites adds up. You can change or remove this rule before activation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if windows.isEmpty && allowance == nil {
                    SectionHeading(title: "Your rules")
                    Text("Choose daily blocks, a shared allowance, or both.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if windows.isEmpty || allowance == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        if windows.isEmpty {
                            Button { sheet = .schedule } label: {
                                Label("Add daily blocks", systemImage: "plus.circle")
                            }
                        }
                        if allowance == nil {
                            Button { sheet = .limit } label: {
                                Label("Add daily allowance", systemImage: "plus.circle")
                            }
                        }
                    }.font(.subheadline)
                }
            }
            .disabled((model.hasSelection && !model.authorized) || model.working)
        }
    }

    private var pendingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Upcoming changes")
                if let pending = model.snapshot.pendingLimit {
                    Text("Now: " + (model.snapshot.policy.dailyLimitMinutes.map { "\($0) minutes per day" } ?? "No daily allowance"))
                        .font(.caption).foregroundStyle(.secondary)
                    Label(pending.minutes.map { "New allowance: \($0) minutes per day" } ?? "Daily allowance will be removed",
                          systemImage: "clock.arrow.circlepath")
                    Text("From \(pending.effectiveAfter, format: .dateTime.weekday().hour().minute())")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let pending = model.snapshot.pendingWindows {
                    Label("Daily blocks will change", systemImage: "calendar.badge.clock")
                    if pending.windows.isEmpty {
                        Text("Scheduled blocks will be removed.")
                    } else {
                        ForEach(pending.windows) { window in
                            Text("\(timeLabel(window.startMinute)) – \(timeLabel(window.endMinute))")
                                .monospacedDigit()
                        }
                    }
                    Text("From \(pending.effectiveAfter, format: .dateTime.weekday().hour().minute())")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let pending = model.snapshot.pendingSelection {
                    Label("Upcoming selection", systemImage: "app.badge")
                    if pending.selection.isEmpty {
                        Text("Everything will be removed from protection.")
                    } else if let selection = ProtectionEnvironment.selection(from: pending.selection) {
                        Text(selection.summary).font(.caption).foregroundStyle(.secondary)
                        SelectionRows(selection: selection)
                    } else {
                        Text("Upcoming selection could not be read.")
                    }
                    Text("From \(pending.effectiveAfter, format: .dateTime.weekday().hour().minute()). Additions are already protected; removals remain protected until then.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel pending changes") { Task { _ = await model.save(.cancelPending) } }
                    .font(.subheadline).disabled(model.working || !model.authorized)
            }
        }
    }

    private func routineRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No account required.", systemImage: "heart")
                .font(.caption).foregroundStyle(.secondary)
            Text("iOS lets you bypass protection by uninstalling Daywell or revoking its Screen Time access in Settings.")
                .font(.caption2).foregroundStyle(.secondary).lineSpacing(3)
        }.padding(.top, 4)
    }
}

private enum EditorSheet: String, Identifiable {
    case application, schedule, limit
    var id: String { rawValue }
}
