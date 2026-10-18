// Simulator-only stand-in for AppModel, used to capture App Store screenshots.
// The simulator cannot authorize Screen Time or create activity tokens, so this
// fixture supplies a sample routine and usage values, and draws category tiles
// in the selection editor in place of Apple's remotely rendered token labels.
import BlockingCore
import FamilyControls
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document: ProtectionDocument
    let authorized = true
    let working = false
    let hasLoaded = true
    @Published var error: String?

    init() {
        var document = ProtectionDocument()
        document.active.policy = BlockingPolicy(
            categories: [Data([1]), Data([2]), Data([3])],
            windows: [BlockWindow(startMinute: 6 * 60, endMinute: 8 * 60),
                      BlockWindow(startMinute: 21 * 60, endMinute: 0)],
            dailyLimitMinutes: 30)
        self.document = document
    }

    var snapshot: ProtectionSnapshot { document.active }
    var selection: FamilyActivitySelection? { FamilyActivitySelection() }
    var editableSelection: FamilyActivitySelection? { FamilyActivitySelection() }
    var hasSelection: Bool { true }
    var hasRules: Bool { true }
    func authorize() async {}
    func refresh(reconcileMonitors: Bool = true) async {}
    func save(_ edit: RuleEdit) async -> Bool { false }
}

enum MockSelection {
    static let summary = "3 categories"
    static let items: [(String, String, Color)] = [
        ("Social", "bubble.left.and.bubble.right.fill", .orange),
        ("Entertainment", "popcorn.fill", .pink),
        ("Games", "gamecontroller.fill", .purple),
    ]

    static func tile(_ symbol: String, _ color: Color, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white))
    }

    static var rows: some View {
        ForEach(items, id: \.0) { item in
            HStack(spacing: 14) {
                tile(item.1, item.2, size: 30)
                Text(item.0)
            }
        }
    }
}

@main
struct StorePreviewApp: App {
    @StateObject private var model = AppModel()
    private var screen: String {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.firstIndex(of: "--screen").map { arguments[$0 + 1] } ?? "dashboard"
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: .constant(screen != "dashboard")) {
                    if screen == "apps" { ApplicationEditor() } else { LimitEditor() }
                }
                .environmentObject(model)
                .tint(Brand.ink)
        }
    }
}

// Screenshot-only values. These never read or represent a person's Screen Time.
enum MockUsage {
    // Match make-store-captures.sh's status bar and keep the routine deterministic.
    static let now = Calendar.autoupdatingCurrent.date(bySettingHour: 9, minute: 41, second: 0, of: .now)!
    static let selected = summary(today: 18 * 60, average: 30 * 60)
    static let total = summary(today: 205 * 60, average: 164 * 60)

    private static func summary(today duration: TimeInterval, average: TimeInterval) -> UsageStatistics {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        var durations = Dictionary(uniqueKeysWithValues: (1...7).map {
            (calendar.date(byAdding: .day, value: -$0, to: today)!, average)
        })
        durations[today] = duration
        return UsageStatistics(dailyDurations: durations, now: now, calendar: calendar)
    }
}
