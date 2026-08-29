import 'package:flutter/material.dart';

import '../services/highlight_service.dart';
import '../services/usage_check_service.dart';

class VbxTextEditingController extends TextEditingController {
  VbxHighlightConfig? config;

  List<int> searchMatches = [];
  int searchMatchLength = 0;
  int? currentMatchStart;

  /// Stellen unbekannter Namespaces im aktuellen Script.
  List<ModuleUsageIssue> usageIssues = [];

  VbxTextEditingController({super.text, this.config});

  // ------------------------------------------------------------
  // Usage-Warnungen
  // ------------------------------------------------------------

  void setUsageIssues(List<ModuleUsageIssue> issues) {
    final unchanged =
        issues.length == usageIssues.length &&
        _usageIssuesEqual(issues, usageIssues);

    if (unchanged) {
      return;
    }

    usageIssues = List<ModuleUsageIssue>.from(issues);

    notifyListeners();
  }

  void clearUsageIssues() {
    if (usageIssues.isEmpty) {
      return;
    }

    usageIssues = [];

    notifyListeners();
  }

  bool _usageIssuesEqual(List<ModuleUsageIssue> a, List<ModuleUsageIssue> b) {
    if (a.length != b.length) {
      return false;
    }

    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start ||
          a[i].end != b[i].end ||
          a[i].module != b[i].module) {
        return false;
      }
    }

    return true;
  }

  // ------------------------------------------------------------
  // Suche
  // ------------------------------------------------------------

  void setSearchHighlights({
    required List<int> matches,
    required int matchLength,
    int? currentMatchStart,
  }) {
    final unchanged =
        matchLength == searchMatchLength &&
        currentMatchStart == this.currentMatchStart &&
        matches.length == searchMatches.length &&
        _listEquals(matches, searchMatches);

    if (unchanged) {
      return;
    }

    searchMatches = List<int>.from(matches);
    searchMatchLength = matchLength;
    this.currentMatchStart = currentMatchStart;

    notifyListeners();
  }

  void clearSearchHighlights() {
    if (searchMatches.isEmpty && currentMatchStart == null) {
      return;
    }

    searchMatches = [];
    searchMatchLength = 0;
    currentMatchStart = null;

    notifyListeners();
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }

    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }

    return true;
  }

  // ------------------------------------------------------------
  // TextSpan
  // ------------------------------------------------------------

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;

    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final cfg = config;

    List<TextSpan> spans;

    if (cfg == null) {
      spans = [TextSpan(text: text, style: style)];
    } else {
      final brightness = Theme.of(context).brightness;
      final colors = cfg.colorsFor(brightness);

      spans = _tokenize(text, style ?? const TextStyle(), cfg, colors);
    }

    // ------------------------------------------------------------
    // Unbekannte Namespaces gelb markieren
    // ------------------------------------------------------------

    if (usageIssues.isNotEmpty) {
      spans = _applyUsageHighlights(spans, text);
    }

    // ------------------------------------------------------------
    // Suche darüberlegen
    // ------------------------------------------------------------

    if (searchMatches.isNotEmpty && searchMatchLength > 0) {
      spans = _applySearchHighlights(spans, text);
    }

    return TextSpan(style: style, children: spans);
  }

  // ------------------------------------------------------------
  // Usage-Highlights
  // ------------------------------------------------------------

  List<TextSpan> _applyUsageHighlights(List<TextSpan> spans, String fullText) {
    final ranges =
        usageIssues
            .map((issue) => (start: issue.start, end: issue.end))
            .where(
              (range) =>
                  range.start >= 0 &&
                  range.end > range.start &&
                  range.start < fullText.length,
            )
            .map(
              (range) => (
                start: range.start,
                end: range.end > fullText.length ? fullText.length : range.end,
              ),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    if (ranges.isEmpty) {
      return spans;
    }

    final result = <TextSpan>[];

    var globalPosition = 0;
    var rangeIndex = 0;

    for (final span in spans) {
      final spanText = span.text ?? '';

      if (spanText.isEmpty) {
        continue;
      }

      final spanStart = globalPosition;
      final spanEnd = globalPosition + spanText.length;

      var localPosition = spanStart;

      while (localPosition < spanEnd) {
        while (rangeIndex < ranges.length &&
            ranges[rangeIndex].end <= localPosition) {
          rangeIndex++;
        }

        if (rangeIndex >= ranges.length ||
            ranges[rangeIndex].start >= spanEnd) {
          result.add(
            TextSpan(
              text: spanText.substring(
                localPosition - spanStart,
                spanEnd - spanStart,
              ),
              style: span.style,
            ),
          );

          localPosition = spanEnd;
          break;
        }

        final range = ranges[rangeIndex];

        // --------------------------------------------------------
        // Bereich vor der Markierung
        // --------------------------------------------------------

        if (range.start > localPosition) {
          final beforeEnd = range.start < spanEnd ? range.start : spanEnd;

          result.add(
            TextSpan(
              text: spanText.substring(
                localPosition - spanStart,
                beforeEnd - spanStart,
              ),
              style: span.style,
            ),
          );

          localPosition = beforeEnd;

          if (localPosition >= spanEnd) {
            break;
          }
        }

        // --------------------------------------------------------
        // Gelb markierter Bereich
        // --------------------------------------------------------

        final highlightEnd = range.end < spanEnd ? range.end : spanEnd;

        result.add(
          TextSpan(
            text: spanText.substring(
              localPosition - spanStart,
              highlightEnd - spanStart,
            ),
            style: (span.style ?? const TextStyle()).copyWith(
              backgroundColor: Colors.yellow.withOpacity(0.35),
            ),
          ),
        );

        localPosition = highlightEnd;

        if (localPosition >= range.end) {
          rangeIndex++;
        }
      }

      globalPosition = spanEnd;
    }

    return result;
  }

  // ------------------------------------------------------------
  // Such-Highlights
  // ------------------------------------------------------------

  List<TextSpan> _applySearchHighlights(List<TextSpan> spans, String fullText) {
    final ranges =
        searchMatches
            .map(
              (start) => (
                start: start,
                end: start + searchMatchLength,
                isCurrent: start == currentMatchStart,
              ),
            )
            .where(
              (range) =>
                  range.start >= 0 &&
                  range.start < fullText.length &&
                  range.end > range.start,
            )
            .map(
              (range) => (
                start: range.start,
                end: range.end > fullText.length ? fullText.length : range.end,
                isCurrent: range.isCurrent,
              ),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    if (ranges.isEmpty) {
      return spans;
    }

    final result = <TextSpan>[];

    var pos = 0;
    var rangeIndex = 0;

    for (final span in spans) {
      final spanText = span.text ?? '';

      if (spanText.isEmpty) {
        continue;
      }

      final spanStart = pos;
      final spanEnd = pos + spanText.length;

      var localPos = spanStart;

      while (localPos < spanEnd) {
        while (rangeIndex < ranges.length &&
            ranges[rangeIndex].end <= localPos) {
          rangeIndex++;
        }

        if (rangeIndex >= ranges.length ||
            ranges[rangeIndex].start >= spanEnd) {
          result.add(
            TextSpan(
              text: spanText.substring(
                localPos - spanStart,
                spanEnd - spanStart,
              ),
              style: span.style,
            ),
          );

          localPos = spanEnd;
          break;
        }

        final range = ranges[rangeIndex];

        // --------------------------------------------------------
        // Bereich vor dem Treffer
        // --------------------------------------------------------

        if (range.start > localPos) {
          final beforeEnd = range.start < spanEnd ? range.start : spanEnd;

          result.add(
            TextSpan(
              text: spanText.substring(
                localPos - spanStart,
                beforeEnd - spanStart,
              ),
              style: span.style,
            ),
          );

          localPos = beforeEnd;

          if (localPos >= spanEnd) {
            break;
          }
        }

        // --------------------------------------------------------
        // Treffer
        // --------------------------------------------------------

        final highlightEnd = range.end < spanEnd ? range.end : spanEnd;

        final backgroundColor = range.isCurrent
            ? Colors.orangeAccent.withOpacity(0.7)
            : Colors.yellow.withOpacity(0.35);

        result.add(
          TextSpan(
            text: spanText.substring(
              localPos - spanStart,
              highlightEnd - spanStart,
            ),
            style: (span.style ?? const TextStyle()).copyWith(
              backgroundColor: backgroundColor,
            ),
          ),
        );

        localPos = highlightEnd;

        if (highlightEnd >= range.end) {
          rangeIndex++;
        }
      }

      pos = spanEnd;
    }

    return result;
  }

  // ------------------------------------------------------------
  // Tokenizer
  // ------------------------------------------------------------

  List<TextSpan> _tokenize(
    String text,
    TextStyle baseStyle,
    VbxHighlightConfig config,
    Map<String, Color> colors,
  ) {
    final spans = <TextSpan>[];

    var index = 0;

    while (index < text.length) {
      // ----------------------------------------------------------
      // Block-Kommentar
      // ----------------------------------------------------------

      if (text.startsWith(config.blockCommentStart, index)) {
        final end = text.indexOf(
          config.blockCommentEnd,
          index + config.blockCommentStart.length,
        );

        final endIndex = end == -1
            ? text.length
            : end + config.blockCommentEnd.length;

        spans.add(
          TextSpan(
            text: text.substring(index, endIndex),
            style: baseStyle.copyWith(color: colors['comment']),
          ),
        );

        index = endIndex;
        continue;
      }

      // ----------------------------------------------------------
      // Zeilen-Kommentar
      // ----------------------------------------------------------

      if (text.startsWith(config.lineComment, index)) {
        final end = text.indexOf('\n', index);

        final endIndex = end == -1 ? text.length : end;

        spans.add(
          TextSpan(
            text: text.substring(index, endIndex),
            style: baseStyle.copyWith(color: colors['comment']),
          ),
        );

        index = endIndex;
        continue;
      }

      // ----------------------------------------------------------
      // String
      // ----------------------------------------------------------

      if (text[index] == '"') {
        var end = index + 1;

        while (end < text.length) {
          if (text[end] == '"') {
            end++;
            break;
          }

          end++;
        }

        spans.add(
          TextSpan(
            text: text.substring(index, end),
            style: baseStyle.copyWith(color: colors['string']),
          ),
        );

        index = end;
        continue;
      }

      // ----------------------------------------------------------
      // Zahl
      // ----------------------------------------------------------

      if (_isDigit(text[index])) {
        var end = index + 1;

        while (end < text.length && (_isDigit(text[end]) || text[end] == '.')) {
          end++;
        }

        spans.add(
          TextSpan(
            text: text.substring(index, end),
            style: baseStyle.copyWith(color: colors['number']),
          ),
        );

        index = end;
        continue;
      }

      // ----------------------------------------------------------
      // Direktive
      // ----------------------------------------------------------

      String? directive;

      for (final candidate in config.directives) {
        if (text.startsWith(candidate, index)) {
          if (directive == null || candidate.length > directive.length) {
            directive = candidate;
          }
        }
      }

      if (directive != null) {
        spans.add(
          TextSpan(
            text: directive,
            style: baseStyle.copyWith(color: colors['directive']),
          ),
        );

        index += directive.length;
        continue;
      }

      // ----------------------------------------------------------
      // Wort
      // ----------------------------------------------------------

      if (_isWordStart(text[index])) {
        var end = index + 1;

        while (end < text.length && _isWordPart(text[end])) {
          end++;
        }

        final word = text.substring(index, end);

        final lower = word.toLowerCase();

        Color? color;

        if (config.booleans.contains(lower)) {
          color = colors['boolean'];
        } else if (config.logicals.contains(lower)) {
          color = colors['logical'];
        } else if (config.keywords.contains(lower)) {
          color = colors['keyword'];
        }

        spans.add(
          TextSpan(
            text: word,
            style: color == null ? baseStyle : baseStyle.copyWith(color: color),
          ),
        );

        index = end;
        continue;
      }

      // ----------------------------------------------------------
      // Operator
      // ----------------------------------------------------------

      String? operator;

      for (final candidate in config.operators) {
        if (text.startsWith(candidate, index)) {
          if (operator == null || candidate.length > operator.length) {
            operator = candidate;
          }
        }
      }

      if (operator != null) {
        spans.add(
          TextSpan(
            text: operator,
            style: baseStyle.copyWith(color: colors['operator']),
          ),
        );

        index += operator.length;
        continue;
      }

      // ----------------------------------------------------------
      // Normales Zeichen
      // ----------------------------------------------------------

      spans.add(TextSpan(text: text[index], style: baseStyle));

      index++;
    }

    return spans;
  }

  // ------------------------------------------------------------
  // Zeichenprüfung
  // ------------------------------------------------------------

  bool _isDigit(String char) {
    final code = char.codeUnitAt(0);

    return code >= 48 && code <= 57;
  }

  bool _isWordStart(String char) {
    final code = char.codeUnitAt(0);

    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        char == '_';
  }

  bool _isWordPart(String char) {
    final code = char.codeUnitAt(0);

    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        (code >= 48 && code <= 57) ||
        char == '_';
  }
}
