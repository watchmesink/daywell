import BlockingCore
import DeviceActivity
import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sheet: EditorSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    #if targetEnvironment(simulator)
                    Label("Simulator preview · Blocking requires an iPhone.", systemImage: "iphone")
                        .font(.caption).foregroundStyle(.secondary)
                    #endif
                    if let error = model.error { ErrorMessage(message: error) }
                    if let failure = model.document.lastError, failure != model.error { ErrorMessage(message: failure) }
                    if model.hasApplications {
                        dashboard
                    } else {
                        onboarding
                    }
                    if model.snapshot.hasPendingChanges { pendingCard }
                    footer
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 22).padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.background)
            .navigationTitle("Daywell")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
            .sheet(item: $sheet) { editor in
                switch editor {
                case .application: ApplicationEditor()
                case .schedule: ScheduleEditor()
                case .limit: LimitEditor()
                }
            }
        }
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 26) {
            Image("DaywellIcon").resizable().scaledToFit()
                .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 18))
            Text("A little more room\nin your day.")
                .font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-1.4)
                .fixedSize(horizontal: false, vertical: true)
            Text("Set your boundaries once. Daywell keeps them in place, with no skip button when a block is active.")
                .foregroundStyle(.secondary).font(.body).lineSpacing(4)
            rulesCard()
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    if model.authorized { sheet = .application }
                    else { Task { await model.authorize() } }
                } label: {
                    HStack {
                        if model.working { ProgressView().tint(.black) }
                        Text(model.authorized ? "Choose apps & start" : "Enable Screen Time access")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButton()).disabled(model.working)
                Text("Choose the apps you want to block. Your rules apply to all selected apps, and your choices and usage stay on your device.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.authorized {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Protection needs access", systemImage: "exclamationmark.shield")
                            .font(.headline)
                        Text("Screen Time access is off. Your saved rules remain, but iOS cannot enforce them until you enable access again.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Enable access") { Task { await model.authorize() } }
                            .buttonStyle(PrimaryButton()).disabled(model.working)
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let decision = model.snapshot.decision(at: context.date, calendar: .autoupdatingCurrent)
                VStack(alignment: .leading, spacing: 22) {
                    statusCard(decision)
                    appCard()
                    rulesCard()
                }
            }
        }
    }

    private func statusCard(_ decision: ShieldDecision) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(model.authorized ? (decision.isBlocked ? "BLOCK ACTIVE" : model.hasRules ? "TIME AVAILABLE" : "NO RULES SET") : "ACCESS NEEDED",
                      systemImage: model.authorized ? (decision.isBlocked ? "lock.fill" : "checkmark.circle.fill") : "exclamationmark.circle")
                    .font(.system(.caption, design: .rounded, weight: .bold)).tracking(1)
                Spacer()
                Image(systemName: "sun.horizon").font(.title2)
            }
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
            if model.authorized, model.snapshot.policy.dailyLimitMinutes != nil, !decision.budgetExhausted,
               let tokens = model.tokens, !tokens.isEmpty {
                Divider().overlay(.white.opacity(0.25))
                DeviceActivityReport(.daywellToday, filter: DeviceActivityFilter(
                    segment: .daily(during: Calendar.current.dateInterval(of: .day, for: .now)!),
                    applications: Set(tokens)))
                    .frame(height: 88)
                    .id(model.snapshot.generation)
            }
        }
        .foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background { OceanSunsetBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityIdentifier("protection-status")
    }

    private func appCard() -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeading(title: "Blocked apps")
                    Spacer()
                    Button("Change") { sheet = .application }.font(.subheadline)
                        .disabled(!model.authorized || model.working)
                }
                if let tokens = model.tokens {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(tokens, id: \.self) { token in
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .frame(width: 36, height: 36)
                            }
                        }
                    }
                    .frame(height: 36)
                } else {
                    Label("Selected apps unavailable", systemImage: "exclamationmark.triangle")
                }
            }
        }
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
                    Text(model.hasApplications
                         ? "Time in all selected apps adds up. Increases or removal take effect tomorrow."
                         : "Time in all selected apps adds up. You can change or remove this rule before activation.")
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
            .disabled((model.hasApplications && !model.authorized) || model.working)
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
                if let pending = model.snapshot.pendingApplications {
                    Label("Upcoming selection · \(pending.applications.count) apps", systemImage: "app.badge")
                    if pending.applications.isEmpty {
                        Text("All apps will be removed from protection.")
                    } else if let tokens = ProtectionEnvironment.applications(from: pending.applications) {
                        ForEach(tokens, id: \.self) { token in SelectedApplicationRow(token: token) }
                    } else {
                        Text("Upcoming apps could not be read.")
                    }
                    Text("From \(pending.effectiveAfter, format: .dateTime.weekday().hour().minute()). New apps are already protected; removed apps remain protected until then.")
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
