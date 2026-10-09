import BlockingCore
import Combine
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document = ProtectionDocument()
    @Published private(set) var authorized = false
    @Published private(set) var working = false
    @Published private(set) var hasLoaded = false
    @Published var error: String?
    private var authorizationObservation: AnyCancellable?
    private var refreshing = false
    private var refreshTask: Task<(ProtectionDocument, String?), Error>?
    private var editRevision = 0

    init() {
        authorizationObservation = AuthorizationCenter.shared.$authorizationStatus.sink { [weak self] status in
            Task { @MainActor in
                self?.authorized = status == .approved
                await self?.refresh()
            }
        }
    }

    var snapshot: ProtectionSnapshot { document.active }
    var tokens: [ApplicationToken]? { ProtectionEnvironment.applications(from: snapshot.policy.applications) }
    var editableTokens: [ApplicationToken]? {
        ProtectionEnvironment.applications(from: snapshot.pendingApplications?.applications ?? snapshot.policy.applications)
    }
    var hasApplications: Bool { !snapshot.policy.applications.isEmpty }
    var hasRules: Bool { !snapshot.policy.windows.isEmpty || snapshot.policy.dailyLimitMinutes != nil }

    func authorize() async {
        guard !working else { return }
        working = true
        error = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        } catch {
            self.error = "Screen Time access could not be enabled. \(error.localizedDescription)"
        }
        working = false
        await refresh()
    }

    func refresh(reconcileMonitors: Bool = true) async {
        guard !working, !refreshing else { return }
        refreshing = true
        let revision = editRevision
        defer { refreshing = false; refreshTask = nil; hasLoaded = true }
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        let mayReconcile = authorized && reconcileMonitors
        do {
            let task = Task.detached(priority: .userInitiated) { () throws -> (ProtectionDocument, String?) in
                let repository = try ProtectionEnvironment.repository()
                // Loading saved selections must not depend on iOS accepting a monitor
                // refresh. Otherwise a refresh failure makes configured apps disappear.
                let saved = try repository.read()
                var refreshError: String?
                if mayReconcile {
                    do { try ProtectionEnvironment.coordinator().reconcile() }
                    catch RuleError.busy { /* Another process is committing a rule update. */ }
                    catch { refreshError = error.localizedDescription }
                }
                let latest: ProtectionDocument
                do { latest = try repository.read() }
                catch { return (saved, error.localizedDescription) }
                return (latest, refreshError ?? latest.lastError)
            }
            refreshTask = task
            let result = try await task.value
            // A background read must not overwrite a newer edit or disable its UI.
            guard revision == editRevision, !working else { return }
            document = result.0
            if reconcileMonitors || result.1 != nil { error = result.1 }
        } catch {
            if revision == editRevision, !working { self.error = error.localizedDescription }
        }
    }

    func save(_ edit: RuleEdit) async -> Bool {
        guard !working else { error = RuleError.busy.localizedDescription; return false }
        let editingDraft: Bool
        switch edit {
        case .windows, .limit: editingDraft = !hasApplications
        default: editingDraft = false
        }
        guard authorized || editingDraft else { error = "Enable Screen Time access before changing protection."; return false }
        working = true
        editRevision += 1
        error = nil
        // Let an in-flight foreground reconciliation release the operation lock.
        // Its result is discarded by the revision check above.
        _ = await refreshTask?.result
        do {
            document = try await Task.detached(priority: .userInitiated) {
                try ProtectionEnvironment.coordinator().execute(edit)
                return try ProtectionEnvironment.repository().read()
            }.value
            working = false
            return true
        } catch {
            self.error = error.localizedDescription
            working = false
            return false
        }
    }
}
