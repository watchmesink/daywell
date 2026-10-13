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
    ('''                                ForEach(Array(selection.applicationTokens), id: \\.self) { token in Label(token) }
                                ForEach(Array(selection.categoryTokens), id: \\.self) { token in Label(token) }
                                ForEach(Array(selection.webDomainTokens), id: \\.self) { token in Label(token) }
''', '                                MockSelection.icons\n'),
])
patch('Editors.swift', [
    ('''                    if selection.isEmpty {
                        Text("Nothing selected").foregroundStyle(.secondary)
                    } else {
                        SelectionRows(selection: selection)
                    }''', '                    MockSelection.rows'),
    ('Text(selection.summary)', 'Text(MockSelection.summary)'),
    ('.disabled(model.working || selection.isEmpty)', '.disabled(model.working)'),
])
