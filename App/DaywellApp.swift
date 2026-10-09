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
                .task { await model.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await model.refresh() }
                }
                .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                    // Threshold callbacks update shared storage in another process.
                    // Pick them up while the dashboard stays open, too.
                    if scenePhase == .active { Task { await model.refresh(reconcileMonitors: false) } }
                }
        }
    }
}
