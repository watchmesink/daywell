import BlockingCore
import FamilyControls
import SwiftUI

struct ApplicationEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var pickerPresented = false
    @State private var validationError: String?
    @State private var loadedSelection = false

    private var removesActiveSelection: Bool {
        guard let active = model.selection else { return true }
        return !selection.isSuperset(of: active)
    }

    private var saveTitle: String {
        !model.hasSelection ? "Activate protection" : "Save changes"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.hasSelection ? "Change what you block" : "Choose what to block")
                        .font(.title2.bold())
                    Text(model.hasSelection
                         ? "Additions are protected immediately, even during a block. Removals stay protected until tomorrow, after any active overnight block ends."
                         : "Choose apps, whole categories, or websites. Your configured rules will apply as soon as you save.")
                        .foregroundStyle(.secondary)
                    Button { pickerPresented = true } label: {
                        Label("Choose apps & websites", systemImage: "app.badge.checkmark")
                    }
                    Text("Select a whole category or expand it to choose individual apps and websites. Then save your selection here to apply it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if selection.isEmpty {
                        Text("Nothing selected").foregroundStyle(.secondary)
                    } else {
                        SelectionRows(selection: selection)
                    }
                } header: {
                    Text(selection.summary)
                } footer: {
                    Text(removesActiveSelection
                         ? "Additions apply now. Removed apps, categories, and websites stay protected until the upcoming change takes effect."
                         : "Your rules apply to everything selected. Additions do not reset used time.")
                }
                Section("Your rules") {
                    ForEach(model.snapshot.policy.windows) { window in
                        LabeledContent("Every day", value: "\(timeLabel(window.startMinute)) – \(timeLabel(window.endMinute))")
                    }
                    if let minutes = model.snapshot.policy.dailyLimitMinutes {
                        LabeledContent("Shared daily allowance", value: "\(minutes) minutes")
                    }
                    if !model.hasRules {
                        Text("No rules configured yet. Add a rule from the dashboard to protect this selection.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = validationError ?? model.error { Section { ErrorMessage(message: error) } }
                Section {
                    Button(saveTitle) {
                        Task { await saveSelection() }
                    }.disabled(model.working || selection.isEmpty)
                    if model.hasSelection {
                        Button("Remove everything tomorrow", role: .destructive) {
                            Task { if await model.save(.selection(BlockingSelection())) { dismiss() } }
                        }.disabled(model.working)
                    }
                } footer: {
                    Text("You can edit at any time. Additions apply now; removals appear under Upcoming changes.")
                }
            }
            .navigationTitle("Your selection").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveSelection() } }
                        .disabled(model.working || selection.isEmpty)
                }
            }
            .familyActivityPicker(isPresented: $pickerPresented, selection: $selection)
            .onAppear {
                // A picker presentation must not reload and overwrite unsaved choices.
                guard !loadedSelection else { return }
                loadedSelection = true
                model.error = nil
                if let saved = model.editableSelection { selection = saved }
                else { validationError = "Saved selections could not be read. Choose your apps, categories, and websites again before saving." }
            }
            .onChange(of: selection) { _, _ in validationError = nil }
        }
    }

    private func saveSelection() async {
        validationError = nil
        guard !selection.isEmpty else {
            validationError = "Select at least one app, category, or website."
            return
        }
        do {
            let encoded = try ProtectionEnvironment.encodedSelection(selection)
            if await model.save(.selection(encoded)) { dismiss() }
        } catch { validationError = error.localizedDescription }
    }
}

struct ScheduleEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [BlockWindow] = []
    @State private var loaded = false

    private var appliesImmediately: Bool {
        !model.hasSelection || BlockingPolicy(windows: windows).coversSchedule(model.snapshot.policy.windows)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("These blocks repeat every day. A shared daily allowance also applies if you've set one.")
                    Text("An end time before the start time means the block continues into the next day.")
                        .foregroundStyle(.secondary)
                    Label(appliesImmediately
                          ? "These changes apply immediately."
                          : "These changes free blocked time, so they apply tomorrow after any active overnight block ends.",
                          systemImage: appliesImmediately ? "bolt" : "clock")
                        .font(.subheadline)
                }
                ForEach($windows) { $window in
                    Section {
                        DatePicker("From", selection: dateBinding($window.startMinute), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: dateBinding($window.endMinute), displayedComponents: .hourAndMinute)
                        Button("Remove window", role: .destructive) { windows.removeAll { $0.id == window.id } }
                    }
                }
                Section {
                    Button { windows.append(BlockWindow(startMinute: 720, endMinute: 780)) } label: {
                        Label("Add window", systemImage: "plus")
                    }.disabled(windows.count >= BlockingPolicy.maximumWindows)
                    if !windows.isEmpty {
                        Button("Remove daily blocks", role: .destructive) { windows = [] }
                    }
                } footer: {
                    Text("Each window must be at least 15 minutes. Remove all windows and save to use only a daily allowance. Up to seven windows are supported.")
                }
                if let error = model.error { Section { ErrorMessage(message: error) } }
            }
            .navigationTitle("Daily blocks").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await model.save(.windows(windows)) { dismiss() } } }
                        .disabled(model.working)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                windows = model.snapshot.pendingWindows?.windows ?? model.snapshot.policy.windows
                model.error = nil
            }
        }
    }

    private func dateBinding(_ minute: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60,
                                  second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

struct LimitEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = "30"
    @State private var validationError: String?

    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Minutes per day")
                        TextField("30", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("Minutes per day")
                    }
                } footer: {
                    Text("Time in your selected apps, categories, and websites adds up. Once the total reaches this limit, everything selected is blocked until the daily reset.")
                }
                Section {
                    Label("A smaller allowance applies immediately.", systemImage: "arrow.down.circle")
                    Label("Increasing or removing the allowance applies tomorrow once protection is active.", systemImage: "clock")
                    Label("Any scheduled blocks still apply.", systemImage: "lock")
                }.font(.subheadline)
                if let pending = model.snapshot.pendingLimit, pending.minutes == nil {
                    Section {
                        Text("Removal is queued for \(pending.effectiveAfter, format: .dateTime.weekday().hour().minute()). Your current allowance remains active until then.")
                            .foregroundStyle(.secondary)
                    }
                } else if model.snapshot.policy.dailyLimitMinutes != nil {
                    Section {
                        Button(model.hasSelection ? "Remove allowance tomorrow" : "Remove allowance", role: .destructive) {
                            Task { if await model.save(.limit(nil)) { dismiss() } }
                        }.disabled(model.working)
                    } footer: {
                        Text("Use daily blocks without a usage limit.")
                    }
                }
                if let error = validationError ?? model.error { Section { ErrorMessage(message: error) } }
            }
            .navigationTitle("Shared allowance").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value = Int(minutes), (1...1440).contains(value) else {
                            validationError = RuleError.invalidLimit.localizedDescription
                            return
                        }
                        Task { if await model.save(.limit(value)) { dismiss() } }
                    }.disabled(model.working)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                minutes = String(model.snapshot.pendingLimit?.minutes ?? model.snapshot.policy.dailyLimitMinutes ?? BlockingPolicy.defaultDailyLimitMinutes)
                model.error = nil
            }
        }
    }
}
