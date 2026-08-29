const String kIndentUnit = '    '; // 4 Leerzeichen

final RegExp _ifOpenRegex = RegExp(r'^If\b.*\bThen$', caseSensitive: false);
final RegExp _elseIfRegex = RegExp(r'^ElseIf\b.*\bThen$', caseSensitive: false);
final RegExp _elseRegex = RegExp(r'^Else$', caseSensitive: false);
final RegExp _caseRegex = RegExp(r'^Case\b.*$', caseSensitive: false);
final RegExp _forOpenRegex = RegExp(r'^For\b.*$', caseSensitive: false);
final RegExp _whileOpenRegex = RegExp(r'^While\b.*$', caseSensitive: false);
final RegExp _doOpenRegex = RegExp(
  r'^Do(\s+(While|Until)\b.*)?$',
  caseSensitive: false,
);
final RegExp _subOpenRegex = RegExp(r'^Sub\b.*$', caseSensitive: false);
final RegExp _functionOpenRegex = RegExp(
  r'^Function\b.*$',
  caseSensitive: false,
);
final RegExp _selectCaseOpenRegex = RegExp(
  r'^Select\s+Case\b.*$',
  caseSensitive: false,
);
final RegExp _closerRegex = RegExp(
  r'^(End\s+If|End\s+While|End\s+Sub|End\s+Function|End\s+Select|Next(\s+\w+)?|Loop(\s+(While|Until)\b.*)?)$',
  caseSensitive: false,
);

bool _isOpener(String t) =>
    _ifOpenRegex.hasMatch(t) ||
    _forOpenRegex.hasMatch(t) ||
    _whileOpenRegex.hasMatch(t) ||
    _doOpenRegex.hasMatch(t) ||
    _subOpenRegex.hasMatch(t) ||
    _functionOpenRegex.hasMatch(t) ||
    _selectCaseOpenRegex.hasMatch(t);

bool _isMidMarker(String t) =>
    _elseIfRegex.hasMatch(t) ||
    _elseRegex.hasMatch(t) ||
    _caseRegex.hasMatch(t);

bool _isCloser(String t) => _closerRegex.hasMatch(t);

String? _closingKeywordFor(String t) {
  if (_ifOpenRegex.hasMatch(t)) return 'End If';
  if (_forOpenRegex.hasMatch(t)) return 'Next';
  if (_whileOpenRegex.hasMatch(t)) return 'End While';
  if (_doOpenRegex.hasMatch(t)) return 'Loop';
  if (_subOpenRegex.hasMatch(t)) return 'End Sub';
  if (_functionOpenRegex.hasMatch(t)) return 'End Function';
  if (_selectCaseOpenRegex.hasMatch(t)) return 'End Select';
  return null;
}

class AutoIndentResult {
  final String text;
  final int cursor;

  AutoIndentResult(this.text, this.cursor);
}

/// Prüft, ob die nächste NICHT-leere Zeile nach [textAfter] bereits genau
/// dem erwarteten Abschluss ([expectedKeyword]) auf der erwarteten
/// Einrückungsebene ([expectedIndent]) entspricht. Wird genutzt, um beim
/// automatischen Einfügen eines Block-Abschlusses keine Duplikate zu
/// erzeugen, wenn direkt darunter zufällig schon der passende Abschluss
/// (z. B. der einer äußeren Ebene) steht.
bool _nextNonEmptyLineMatches(
  String textAfter,
  String expectedIndent,
  String expectedKeyword,
) {
  final lines = textAfter.split('\n');

  for (final line in lines) {
    if (line.trim().isEmpty) {
      continue;
    }

    final indent = RegExp(r'^[ \t]*').firstMatch(line)?.group(0) ?? '';
    final trimmed = line.trim();

    return indent == expectedIndent &&
        trimmed.toLowerCase() == expectedKeyword.toLowerCase();
  }

  return false;
}

/// Wird direkt nach einem Enter-Tastendruck aufgerufen (cursorOffset zeigt
/// auf die Position direkt NACH dem bereits eingefügten '\n').
/// Gibt null zurück, wenn nichts anzupassen ist.
AutoIndentResult? applyAutoIndent(String text, int cursorOffset) {
  if (cursorOffset <= 0 || cursorOffset > text.length) {
    return null;
  }

  if (text[cursorOffset - 1] != '\n') {
    return null;
  }

  final beforeNewline = text.substring(0, cursorOffset - 1);
  final prevLineStart = beforeNewline.lastIndexOf('\n') + 1;
  final prevLineRaw = beforeNewline.substring(prevLineStart);

  final prevIndent = RegExp(r'^[ \t]*').firstMatch(prevLineRaw)?.group(0) ?? '';
  final prevTrimmed = prevLineRaw.trim();

  final isMid = _isMidMarker(prevTrimmed);
  final isClose = _isCloser(prevTrimmed);
  final isOpen = _isOpener(prevTrimmed);

  var effectiveIndent = prevIndent;
  var correctedPrevLineRaw = prevLineRaw;

  // Mid-Marker (Else/ElseIf/Case) und reine Schließer (End If, Next, ...)
  // werden selbst eine Ebene zurückgesetzt.
  if (isMid || isClose) {
    effectiveIndent = prevIndent.length >= kIndentUnit.length
        ? prevIndent.substring(kIndentUnit.length)
        : '';
    correctedPrevLineRaw = effectiveIndent + prevTrimmed;
  }

  String newLineIndent;

  if (isOpen || isMid) {
    newLineIndent = effectiveIndent + kIndentUnit;
  } else if (isClose) {
    newLineIndent = effectiveIndent;
  } else {
    newLineIndent = prevIndent;
  }

  final restAfterCursor = text.substring(cursorOffset);
  final prefix = text.substring(0, prevLineStart) + correctedPrevLineRaw + '\n';

  final closing = isOpen ? _closingKeywordFor(prevTrimmed) : null;

  if (closing != null) {
    // Prüfen, ob direkt darunter (nächste nicht-leere Zeile) bereits
    // GENAU dieser Abschluss auf der Zielebene steht -- dann nicht
    // nochmal einfügen, um Duplikate zu vermeiden. In allen anderen
    // Fällen (auch wenn danach z. B. ein "End If" einer äußeren Ebene
    // folgt) wird der Abschluss eingefügt.
    final alreadyClosedBelow = _nextNonEmptyLineMatches(
      restAfterCursor,
      effectiveIndent,
      closing,
    );

    if (!alreadyClosedBelow) {
      final newText =
          prefix +
          newLineIndent +
          '\n' +
          effectiveIndent +
          closing +
          restAfterCursor;
      final newCursor = prefix.length + newLineIndent.length;

      return AutoIndentResult(newText, newCursor);
    }
  }

  if (newLineIndent.isEmpty && correctedPrevLineRaw == prevLineRaw) {
    return null; // nichts zu tun
  }

  final newText = prefix + newLineIndent + restAfterCursor;
  final newCursor = prefix.length + newLineIndent.length;

  return AutoIndentResult(newText, newCursor);
}

/// Formatiert das GESAMTE Dokument neu, basierend auf der
/// Verschachtelungstiefe (If/For/While/Do/Sub/Function/Select Case).
/// Wird beim Speichern aufgerufen, nicht beim Tippen.
String reindentDocument(String text) {
  final lines = text.split('\n');
  final result = <String>[];

  var level = 0;

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();

    if (trimmed.isEmpty) {
      result.add('');
      continue;
    }

    int lineLevel;

    if (_isCloser(trimmed)) {
      level = level > 0 ? level - 1 : 0;
      lineLevel = level;
    } else if (_isMidMarker(trimmed)) {
      // Else/ElseIf/Case: eine Ebene weniger als der Block-Inhalt,
      // aber die Blockebene selbst bleibt für die Folgezeilen erhalten.
      lineLevel = level > 0 ? level - 1 : 0;
    } else if (_isOpener(trimmed)) {
      lineLevel = level;
      level += 1;
    } else {
      lineLevel = level;
    }

    result.add(kIndentUnit * lineLevel + trimmed);
  }

  return result.join('\n');
}
