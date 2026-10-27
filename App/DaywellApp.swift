import SwiftUI
import Combine

@main
struct DaywellApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if model.hasLoaded { ContentView() }
                else { DaywellLoadingView() }
            }
                .environmentObject(model)
                .tint(Brand.ink)
                .task {
                    ProtectionEnvironment.record("app.launched", details: ProblemReportExporter.environment())
                    await model.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    ProtectionEnvironment.record("app.scene_changed", details: ["phase": String(describing: phase),
                        "authorization": String(model.authorized), "timeZone": TimeZone.current.identifier])
                    if phase == .active { Task { await model.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    ProtectionEnvironment.record("clock.significant_change", details: ["timeZone": TimeZone.current.identifier,
                        "utcOffsetSeconds": String(TimeZone.current.secondsFromGMT())])
                    Task { await model.refresh() }
                }
                .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                    // Recover missed schedule/reset callbacks while the dashboard
                    // stays open. Unchanged plans do not re-register monitors, and
                    // AppModel avoids publishing unchanged state into the UI.
                    if scenePhase == .active { Task { await model.refresh() } }
                }
        }
    }
}
