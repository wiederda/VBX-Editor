import 'package:flutter/material.dart';

/// Parst einen Text mit ANSI-SGR-Escape-Codes (Farben, fett, unterstrichen)
/// in eine Liste von [TextSpan]s, damit Konsolen-Ausgaben mit Farben
/// (z. B. von vbRed()/vbBold()/vbNormal() in VBX) korrekt dargestellt
/// werden können, statt die rohen Escape-Sequenzen anzuzeigen.
class AnsiSpanBuilder {
  // Angelehnt an die klassische Terminal-Farbpalette (Tango-artig).
  static const Map<int, Color> _fg = {
    30: Colors.black,
    31: Color(0xFFCC0000),
    32: Color(0xFF4E9A06),
    33: Color(0xFFC4A000),
    34: Color(0xFF3465A4),
    35: Color(0xFF75507B),
    36: Color(0xFF06989A),
    37: Color(0xFFD3D7CF),
    90: Color(0xFF555753),
    91: Color(0xFFEF2929),
    92: Color(0xFF8AE234),
    93: Color(0xFFFCE94F),
    94: Color(0xFF729FCF),
    95: Color(0xFFAD7FA8),
    96: Color(0xFF34E2E2),
    97: Color(0xFFEEEEEC),
  };

  static const Map<int, Color> _bg = {
    40: Colors.black,
    41: Color(0xFFCC0000),
    42: Color(0xFF4E9A06),
    43: Color(0xFFC4A000),
    44: Color(0xFF3465A4),
    45: Color(0xFF75507B),
    46: Color(0xFF06989A),
    47: Color(0xFFD3D7CF),
    100: Color(0xFF555753),
    101: Color(0xFFEF2929),
    102: Color(0xFF8AE234),
    103: Color(0xFFFCE94F),
    104: Color(0xFF729FCF),
    105: Color(0xFFAD7FA8),
    106: Color(0xFF34E2E2),
    107: Color(0xFFEEEEEC),
  };

  static final RegExp _ansiRegex = RegExp(r'\x1B\[([0-9;]*)m');

  /// Zerlegt [input] in [TextSpan]s, wobei [baseStyle] den Ausgangszustand
  /// (Standardfarbe, Schriftart) vorgibt, zu dem bei Code 0 (Reset)
  /// zurückgekehrt wird.
  static List<TextSpan> parse(String input, TextStyle baseStyle) {
    final spans = <TextSpan>[];

    var currentStyle = baseStyle;
    var lastIndex = 0;

    for (final match in _ansiRegex.allMatches(input)) {
      if (match.start > lastIndex) {
        final text = input.substring(lastIndex, match.start);

        if (text.isNotEmpty) {
          spans.add(TextSpan(text: text, style: currentStyle));
        }
      }

      final codesStr = match.group(1) ?? '';
      final codes = codesStr.isEmpty
          ? [0]
          : codesStr.split(';').map((c) => int.tryParse(c) ?? 0).toList();

      for (final code in codes) {
        if (code == 0) {
          currentStyle = baseStyle;
        } else if (code == 1) {
          currentStyle = currentStyle.copyWith(fontWeight: FontWeight.bold);
        } else if (code == 4) {
          currentStyle = currentStyle.copyWith(
            decoration: TextDecoration.underline,
          );
        } else if (code == 22) {
          currentStyle = currentStyle.copyWith(fontWeight: FontWeight.normal);
        } else if (code == 24) {
          currentStyle = currentStyle.copyWith(decoration: TextDecoration.none);
        } else if (code == 39) {
          currentStyle = currentStyle.copyWith(color: baseStyle.color);
        } else if (code == 49) {
          currentStyle = currentStyle.copyWith(backgroundColor: null);
        } else if (_fg.containsKey(code)) {
          currentStyle = currentStyle.copyWith(color: _fg[code]);
        } else if (_bg.containsKey(code)) {
          currentStyle = currentStyle.copyWith(backgroundColor: _bg[code]);
        }
        // Unbekannte Codes werden ignoriert.
      }

      lastIndex = match.end;
    }

    if (lastIndex < input.length) {
      spans.add(
        TextSpan(text: input.substring(lastIndex), style: currentStyle),
      );
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: input, style: baseStyle));
    }

    return spans;
  }
}
