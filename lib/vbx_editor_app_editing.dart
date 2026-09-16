part of 'vbx_editor_app.dart';

extension _VbxEditorAppEditing on _VbxEditorAppState {
  bool get _hasSelection {
    final tab = _currentTab;

    if (tab == null) {
      return false;
    }

    final selection = tab.controller.selection;

    return selection.start != selection.end;
  }

  ({int lineStart, int lineEnd, List<String> lines}) _selectedLineRange(
    EditorTab tab,
  ) {
    final text = tab.controller.text;
    final selection = tab.controller.selection;

    var start = selection.start;
    var end = selection.end;

    if (start < 0) start = 0;
    if (end < 0) end = start;
    if (start > text.length) start = text.length;
    if (end > text.length) end = text.length;

    if (start > end) {
      final tmp = start;
      start = end;
      end = tmp;
    }

    // Auf ganze Zeilen erweitern.
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;

    var searchFrom = end;
    if (end > start && end > 0 && text[end - 1] == '\n') {
      // Endet die Auswahl genau auf einem Zeilenumbruch, die leere
      // Folgezeile nicht mehr mit einbeziehen.
      searchFrom = end - 1;
    }

    var lineEnd = text.indexOf('\n', searchFrom);
    if (lineEnd == -1) lineEnd = text.length;

    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');

    return (lineStart: lineStart, lineEnd: lineEnd, lines: lines);
  }

  void _applyLineEdit(
    EditorTab tab,
    int lineStart,
    int lineEnd,
    List<String> newLines,
  ) {
    final text = tab.controller.text;
    final block = text.substring(lineStart, lineEnd);
    final newBlock = newLines.join('\n');

    final newText =
        text.substring(0, lineStart) + newBlock + text.substring(lineEnd);

    final lengthDiff = newBlock.length - block.length;

    setState(() {
      tab.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: lineStart,
          extentOffset: lineEnd + lengthDiff,
        ),
      );
    });

    // Fokus zurück ins Editorfeld holen: der Toolbar-Button hat den
    // Fokus übernommen, wodurch ein unfokussiertes TextField die
    // (hier bewusst auf den ganzen bearbeiteten Block erweiterte)
    // Selektion nicht mehr optisch anzeigt -- obwohl sie intern
    // weiterhin besteht und _hasSelection/die Buttons dadurch aktiv
    // bleiben. Ohne requestFocus sieht es so aus, als sei nichts mehr
    // markiert, obwohl ein erneuter Klick weiterhin denselben
    // (unsichtbaren) Bereich trifft.
    tab.focusNode.requestFocus();
  }

  void _commentSelectedLines() {
    final tab = _currentTab;

    if (tab == null || !_hasSelection) {
      return;
    }

    final range = _selectedLineRange(tab);

    final newLines = range.lines.map((l) {
      if (l.trim().isEmpty) {
        return l;
      }

      final indentMatch = RegExp(r'^(\s*)').firstMatch(l)!;
      final indent = indentMatch.group(1)!;

      return "$indent' ${l.substring(indent.length)}";
    }).toList();

    _applyLineEdit(tab, range.lineStart, range.lineEnd, newLines);
  }

  void _uncommentSelectedLines() {
    final tab = _currentTab;

    if (tab == null || !_hasSelection) {
      return;
    }

    final range = _selectedLineRange(tab);
    final commentPrefixRegex = RegExp(r"^(\s*)'\s?");

    final newLines = range.lines.map((l) {
      final match = commentPrefixRegex.firstMatch(l);

      if (match == null) {
        return l;
      }

      final ws = match.group(1)!;
      return ws + l.substring(match.end);
    }).toList();

    _applyLineEdit(tab, range.lineStart, range.lineEnd, newLines);
  }
}
