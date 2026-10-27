"""Adapt copies of the app views for the simulator screenshot fixture."""
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])


def patch(name, replacements):
    path = src / name
    text = path.read_text()
    for old, new in replacements:
        assert old in text, f'{name}: {old!r} not found'
        text = text.replace(old, new)
    path.write_text(text)


# Drop the simulator banner; the fixture stands in for an authorized iPhone.
view = src / 'ContentView.swift'
view.write_text(re.sub(r'\n[ \t]*#if targetEnvironment\(simulator\)\n.*?#endif', '', view.read_text(), count=1, flags=re.S))

patch('ContentView.swift', [
    ('Text(selection.summary)', 'Text(MockSelection.summary)'),
    # A simulator selection has no real Screen Time tokens. Show the same report
    # views using explicit fixture values, preserving their layout and modifiers.
    ('if model.authorized, let selection = model.selection, !selection.isEmpty {',
     'if model.authorized, let selection = model.selection {'),
    ('model.snapshot.decision(at: context.date, calendar: .autoupdatingCurrent)',
     'model.snapshot.decision(at: MockUsage.now, calendar: .autoupdatingCurrent)'),
    ('at: context.date)', 'at: MockUsage.now)'),
    ("""        let calendar = Calendar.autoupdatingCurrent
        let today = usageDay
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let interval = DateInterval(
            start: calendar.date(byAdding: .day, value: -7, to: today)!,
            end: tomorrow)

        return VStack""", '        VStack'),
    ("""DeviceActivityReport(.daywellToday, filter: DeviceActivityFilter(
                segment: .daily(during: DateInterval(start: today, end: tomorrow)),
                applications: selection.applicationTokens, categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens))""",
     'TodayUsageView(summary: MockUsage.selected, scope: .selected)'),
    ("""DeviceActivityReport(.daywellTotalToday, filter: DeviceActivityFilter(
                segment: .daily(during: interval)))""",
     'TodayUsageView(summary: MockUsage.total, scope: .total)'),
])

# Reuse the production rendering code without the extension entry point or the
# live Screen Time query. The fixture only changes access levels for compilation.
root = Path(__file__).resolve().parents[2]
report = (root / 'Extensions/ActivityReport/ActivityReportExtension.swift').read_text()
scope = re.search(r'private enum UsageScope \{.*?\}', report, re.S)
assert scope, 'UsageScope declaration not found'
report_view = report[report.index('private struct TodayUsageView:'):]
(src / 'ReportPreview.swift').write_text(
    'import BlockingCore\nimport SwiftUI\n\n'
    + scope.group().replace('private enum', 'enum', 1) + '\n\n'
    + report_view.replace('private struct TodayUsageView:', 'struct TodayUsageView:', 1))
patch('Editors.swift', [
    ('''                    if selection.isEmpty {
                        Text("Nothing selected").foregroundStyle(.secondary)
                    } else {
                        SelectionRows(selection: selection)
                    }''', '                    MockSelection.rows'),
    ('Text(selection.summary)', 'Text(MockSelection.summary)'),
    ('.disabled(model.working || selection.isEmpty)', '.disabled(model.working)'),
])
