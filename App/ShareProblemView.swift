import BlockingCore
import SwiftUI
import UIKit

struct ShareProblemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var occurredAt = Date()
    @State private var selectedUsageShown = ""
    @State private var preparing = false
    @State private var error: String?
    @State private var attachment: ProblemAttachment?
    @State private var uptimeSeconds = ProcessInfo.processInfo.systemUptime

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Describe the problem and share a report to help us understand what happened.")
                        .foregroundStyle(.secondary)
                    TextField("For example: Instagram was blocked before I used it.", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("What happened")
                        .accessibilityIdentifier("problem-description")
                    DatePicker("When it happened", selection: $occurredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("problem-time")
                } header: {
                    Text("What happened?")
                }

                Section {
                    TextField("For example: 0 min", text: $selectedUsageShown)
                        .accessibilityLabel("Selected activity shown")
                        .accessibilityIdentifier("problem-selected-usage")
                } header: {
                    Text("Selected activity shown (optional)")
                } footer: {
                    Text("Enter the value shown on Daywell's dashboard. Apple keeps exact usage measurements private, so they aren't attached automatically.")
                }

                Section("Device timing included") {
                    LabeledContent("Time since device restart") {
                        Text(Duration.seconds(uptimeSeconds).formatted(.units(
                            allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                    }
                    .accessibilityIdentifier("problem-device-uptime")
                    Text("Device uptime and the timing of recent blocking events are attached to help investigate this problem.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Text("The report includes recent blocking events, your rules, and app and iOS versions. The automatic logs exclude app and website names and browsing history. Anything you write above is included.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Only recent events recorded by Daywell are included. You choose where to send the report in the next step.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task { await prepareReport() }
                    } label: {
                        HStack {
                            if preparing { ProgressView() }
                            Label(preparing ? "Preparing report…" : "Share report", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(preparing)
                    .accessibilityIdentifier("share-problem-report")
                }
                if let error { Section { ErrorMessage(message: error) } }
            }
            .navigationTitle("Share problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $attachment) { item in
                ProblemShareSheet(url: item.url) { sharingError in
                    attachment = nil
                    if sharingError != nil { error = "The report could not be shared. Please try again." }
                }
            }
        }
    }

    @MainActor
    private func prepareReport() async {
        guard !preparing else { return }
        preparing = true
        error = nil
        defer { preparing = false }
        let problem = DiagnosticProblem(description: description, occurredAt: occurredAt, selectedUsageShown: selectedUsageShown)
        let environment = ProblemReportExporter.environment()
        if let value = environment["uptimeSeconds"].flatMap(Double.init) { uptimeSeconds = value }
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try ProblemReportExporter.create(problem: problem, environment: environment)
            }.value
            attachment = ProblemAttachment(url: url)
        } catch {
            ProtectionEnvironment.record("report.export_failed", details: DiagnosticEvent.errorDetails(error))
            self.error = "The report could not be created. Please try again."
        }
    }
}

private struct ProblemAttachment: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProblemShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            Task { @MainActor in completion(error) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
