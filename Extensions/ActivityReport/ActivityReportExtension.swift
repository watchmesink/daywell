import BlockingCore
import DeviceActivity
import ManagedSettings
import SwiftUI

@main
struct ActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayReport(context: .daywellToday, scope: .selected) {
            TodayUsageView(summary: $0, scope: .selected)
        }
        TodayReport(context: .daywellTotalToday, scope: .total) {
            TodayUsageView(summary: $0, scope: .total)
        }
    }
}

private enum UsageScope {
    case selected, total
}

private struct TodayReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let scope: UsageScope
    let content: (UsageStatistics) -> TodayUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageStatistics {
        let calendar = Calendar.autoupdatingCurrent
        var dailyDurations: [Date: TimeInterval] = [:]
        for await device in data {
            for await segment in device.activitySegments {
                let duration: TimeInterval
                switch scope {
                case .selected:
                    duration = await selectedDuration(in: segment)
                case .total:
                    // The segment aggregate is the device's screen-on time, even
                    // when an application/category/domain filter is supplied.
                    duration = segment.totalActivityDuration
                }
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                dailyDurations[day, default: 0] += duration
            }
        }
        return UsageStatistics(dailyDurations: dailyDurations, now: .now, calendar: calendar)
    }

    private func selectedDuration(in segment: DeviceActivityData.ActivitySegment) async -> TimeInterval {
        var applications: [ApplicationToken: TimeInterval] = [:]
        var webDomains: [WebDomainToken: TimeInterval] = [:]
        var untokenizedDuration: TimeInterval = 0
        for await category in segment.categories {
            // A selected category expands to its filtered applications and sites.
            // Count these leaves once; category totals also include the leaves.
            for await activity in category.applications {
                if let token = activity.application.token {
                    applications[token] = max(applications[token, default: 0], activity.totalActivityDuration)
                } else {
                    untokenizedDuration += activity.totalActivityDuration
                }
            }
            for await activity in category.webDomains {
                if let token = activity.webDomain.token {
                    webDomains[token] = max(webDomains[token, default: 0], activity.totalActivityDuration)
                } else {
                    untokenizedDuration += activity.totalActivityDuration
                }
            }
        }
        return applications.values.reduce(0, +) + webDomains.values.reduce(0, +) + untokenizedDuration
    }
}

private struct TodayUsageView: View {
    let summary: UsageStatistics
    let scope: UsageScope

    var body: some View {
        VStack(alignment: .leading, spacing: scope == .selected ? 5 : 3) {
            if scope == .selected {
                Text("Selected activity today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formattedDuration)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if summary.todayDuration == nil {
                    Text("Waiting for Screen Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 5) {
                    Text("Total screen time")
                    Text(formattedDuration).fontWeight(.semibold).monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                comparison
                    .font(.caption)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.clear)
    }

    private var formattedDuration: String {
        guard let duration = summary.todayDuration else { return "—" }
        return Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    @ViewBuilder
    private var comparison: some View {
        if let change = summary.percentageChange {
            let roundedChange = change.rounded()
            HStack(spacing: 4) {
                Text(percentage(roundedChange))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(roundedChange < 0 ? Color.green : roundedChange > 0 ? Color.red : Color.secondary)
                Text("vs 7-day avg").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(summary.todayDuration == nil ? "Waiting for Screen Time" :
                    summary.previousSevenDaysAverage == 0 ? "No usage in the previous 7 days" : "7-day comparison unavailable")
                .foregroundStyle(.secondary)
        }
    }

    private func percentage(_ change: Double) -> String {
        let value = abs(change).formatted(.number.precision(.fractionLength(0)))
        return change < 0 ? "−\(value)%" : change > 0 ? "+\(value)%" : "0%"
    }
}
