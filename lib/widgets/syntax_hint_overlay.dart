import 'package:flutter/material.dart';

import '../services/syntax_service.dart';

class _SyntaxHintData {
  final Offset position;
  final VbxSyntaxInfo info;
  final int paramIndex;
  final bool isDark;

  _SyntaxHintData({
    required this.position,
    required this.info,
    required this.paramIndex,
    required this.isDark,
  });
}

/// Verwaltet ein floatendes Signatur-Popup direkt unter dem Cursor
/// (analog zu AutocompleteController, aber ohne Auswahl/Interaktion).
class SyntaxHintController {
  OverlayEntry? _entry;
  final ValueNotifier<_SyntaxHintData?> _data = ValueNotifier(null);

  bool get isVisible => _entry != null;

  void show({
    required BuildContext context,
    required Offset position,
    required VbxSyntaxInfo info,
    required int paramIndex,
    required bool isDark,
  }) {
    _data.value = _SyntaxHintData(
      position: position,
      info: info,
      paramIndex: paramIndex,
      isDark: isDark,
    );

    if (_entry != null) {
      return;
    }

    _entry = OverlayEntry(
      builder: (context) {
        return ValueListenableBuilder<_SyntaxHintData?>(
          valueListenable: _data,
          builder: (context, data, _) {
            if (data == null) {
              return const SizedBox.shrink();
            }

            return Positioned(
              left: data.position.dx,
              top: data.position.dy,
              child: _SyntaxHintCard(
                info: data.info,
                paramIndex: data.paramIndex,
                isDark: data.isDark,
              ),
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_entry!);
  }

  void update({
    required Offset position,
    required VbxSyntaxInfo info,
    required int paramIndex,
    required bool isDark,
  }) {
    _data.value = _SyntaxHintData(
      position: position,
      info: info,
      paramIndex: paramIndex,
      isDark: isDark,
    );
  }

  void hide() {
    _entry?.remove();
    _entry = null;
    _data.value = null;
  }
}

class _SyntaxHintCard extends StatelessWidget {
  final VbxSyntaxInfo info;
  final int paramIndex;
  final bool isDark;

  const _SyntaxHintCard({
    required this.info,
    required this.paramIndex,
    required this.isDark,
  });

  // Zerlegt "modul.Funktion(param1, param2)" in die einzelnen Parameter,
  // Klammer-/Bracket-Tiefe wird berücksichtigt, damit z.B. "arr[0]" nicht
  // fälschlich als Parametergrenze erkannt wird.
  List<String> _splitParams(String syntax) {
    final openIdx = syntax.indexOf('(');
    final closeIdx = syntax.lastIndexOf(')');

    if (openIdx == -1 || closeIdx == -1 || closeIdx < openIdx) {
      return [];
    }

    final inner = syntax.substring(openIdx + 1, closeIdx);

    if (inner.trim().isEmpty) {
      return [];
    }

    final params = <String>[];
    var depth = 0;
    final buffer = StringBuffer();

    for (var i = 0; i < inner.length; i++) {
      final ch = inner[i];

      if (ch == '(' || ch == '[') {
        depth++;
        buffer.write(ch);
        continue;
      }

      if (ch == ')' || ch == ']') {
        depth--;
        buffer.write(ch);
        continue;
      }

      if (ch == ',' && depth == 0) {
        params.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }

      buffer.write(ch);
    }

    if (buffer.toString().trim().isNotEmpty) {
      params.add(buffer.toString().trim());
    }

    return params;
  }

  String _prefix(String syntax) {
    final openIdx = syntax.indexOf('(');
    return openIdx == -1 ? syntax : syntax.substring(0, openIdx + 1);
  }

  @override
  Widget build(BuildContext context) {
    final params = _splitParams(info.syntax);
    final prefix = _prefix(info.syntax);

    final textColor = isDark ? Colors.white70 : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final highlightColor = isDark
        ? Colors.lightBlueAccent
        : Colors.blue.shade800;

    final spans = <TextSpan>[
      TextSpan(
        text: prefix,
        style: TextStyle(color: textColor),
      ),
    ];

    for (var i = 0; i < params.length; i++) {
      final isCurrent = i == paramIndex;

      spans.add(
        TextSpan(
          text: params[i],
          style: TextStyle(
            color: isCurrent ? highlightColor : textColor,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );

      if (i < params.length - 1) {
        spans.add(
          TextSpan(
            text: ', ',
            style: TextStyle(color: textColor),
          ),
        );
      }
    }

    spans.add(
      TextSpan(
        text: ')',
        style: TextStyle(color: textColor),
      ),
    );

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(4),
      color: isDark ? const Color(0xFF2D2D30) : Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                children: spans,
              ),
            ),
            if (info.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                info.description,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: dimColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
