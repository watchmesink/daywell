import DeviceActivity
import SwiftUI

@main
struct ActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayReport { TodayUsageView(summary: $0) }
    }
}

private struct UsageSummary {
    var duration: TimeInterval
    var updatedAt: Date?
}

private struct TodayReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .daywellToday
    let content: (UsageSummary) -> TodayUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        var total: TimeInterval = 0
        var updated: Date?
        for await device in data {
            updated = max(updated ?? .distantPast, device.lastUpdatedDate)
            for await segment in device.activitySegments {
                for await category in segment.categories {
                    for await application in category.applications {
                        total += application.totalActivityDuration
                    }
                }
            }
        }
        return UsageSummary(duration: total, updatedAt: updated)
    }
}

private struct TodayUsageView: View {
    let summary: UsageSummary
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Used today").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                Text(summary.updatedAt == nil ? "—" : Duration.seconds(summary.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "hourglass").foregroundStyle(.white.opacity(0.85))
                if let updated = summary.updatedAt {
                    Text("Updated \(updated, style: .time)").font(.caption2).foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("Waiting for Screen Time").font(.caption).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.clear)
    }
}
