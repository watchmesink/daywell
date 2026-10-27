import BlockingCore
import FamilyControls
import Foundation
import UIKit

enum ProblemReportExporter {
    @MainActor
    static func environment() -> [String: String] {
        var system = utsname()
        uname(&system)
        let machineSize = MemoryLayout.size(ofValue: system.machine)
        let machine = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: machineSize) {
                String(cString: $0)
            }
        }
        var fields = [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "systemVersion": UIDevice.current.systemVersion,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "deviceModel": machine,
            "authorization": String(describing: AuthorizationCenter.shared.authorizationStatus),
            "timeZone": TimeZone.current.identifier,
            "utcOffsetSeconds": String(TimeZone.current.secondsFromGMT()),
            "calendar": String(describing: Calendar.current.identifier),
            "uptimeSeconds": String(ProcessInfo.processInfo.systemUptime)
        ]
        #if targetEnvironment(simulator)
        fields["simulator"] = "true"
        #else
        fields["simulator"] = "false"
        #endif
        return fields
    }

    /// Collect without reconciliation: sharing must preserve the failing state.
    static func create(problem: DiagnosticProblem, environment: [String: String]) throws -> URL {
        let now = Date()
        var report = DiagnosticReport(generatedAt: now, problem: problem, environment: environment, state: nil)
        var selection: FamilyActivitySelection?
        do {
            let document = try ProtectionEnvironment.repository().read()
            report.state = DiagnosticState(document, at: now, calendar: .autoupdatingCurrent)
            selection = ProtectionEnvironment.selection(from: document.active.policy.selection)
            report.environment["selectionDecodes"] = String(selection != nil)
            report.environment["expectedMonitorCount"] = String(MonitorSpec.plan(for: document.active).count)
        } catch {
            report.collectionErrors["protectionState"] = DiagnosticEvent.errorDetails(error)
        }

        let driver = ScreenTimeDriver()
        report.registeredMonitors = driver.diagnosticMonitors(selection: selection)
        report.installedShields = driver.diagnosticShields
        do {
            report.history = try ProtectionEnvironment.diagnosticLog().read()
        } catch {
            report.collectionErrors["diagnosticHistory"] = DiagnosticEvent.errorDetails(error)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaywellProblemReports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeOldExports(in: directory, at: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Daywell-problem-\(formatter.string(from: now))-\(UUID().uuidString.prefix(8)).json"
        let url = directory.appendingPathComponent(name)
        try report.encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Keep the attachment available after the share sheet closes; some share
        // extensions consume the file asynchronously. Later exports prune it.
        return url
    }

    private static func removeOldExports(in directory: URL, at now: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let exports = files.filter { $0.lastPathComponent.hasPrefix("Daywell-problem-") && $0.pathExtension == "json" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (index, item) in exports.enumerated() where index >= 9 || now.timeIntervalSince(item.1) > 86_400 {
            try? FileManager.default.removeItem(at: item.0)
        }
    }
}
