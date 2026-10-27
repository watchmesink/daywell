import Foundation

public enum ProtectionCopy {
    public static func allowanceUsed(resetsAt reset: Date?, now: Date = Date(),
                                     calendar: Calendar = .autoupdatingCurrent,
                                     locale: Locale = .autoupdatingCurrent) -> String {
        let explanation = "The daily allowance is used."
        guard let reset, reset > now else { return explanation }
        let today = calendar.startOfDay(for: now)
        if reset == calendar.date(byAdding: .day, value: 1, to: today) {
            return explanation + " It will reset at midnight."
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return explanation + " It will reset on \(formatter.string(from: reset))."
    }
}
