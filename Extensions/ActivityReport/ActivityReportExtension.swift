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
    var hasActivityData: Bool
}

private struct TodayReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .daywellToday
    let content: (UsageSummary) -> TodayUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        var total: TimeInterval = 0
        var hasActivityData = false
        for await device in data {
            hasActivityData = true
            for await segment in device.activitySegments {
                // Use Screen Time's filtered aggregate, including websites and whole
                // categories, without summing overlapping category and item totals.
                total += segment.totalActivityDuration
            }
        }
        return UsageSummary(duration: total, hasActivityData: hasActivityData)
    }
}

private struct TodayUsageView: View {
    let summary: UsageSummary
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Used today").font(.subheadline).foregroundStyle(Color.primary.opacity(0.85))
                Text(summary.hasActivityData ? Duration.seconds(summary.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) : "—")
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "hourglass").foregroundStyle(Color.primary.opacity(0.85))
                if !summary.hasActivityData {
                    Text("Waiting for Screen Time").font(.caption).foregroundStyle(Color.primary.opacity(0.85))
                }
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.clear)
    }
}
