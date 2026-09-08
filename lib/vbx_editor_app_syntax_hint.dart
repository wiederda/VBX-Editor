part of 'vbx_editor_app.dart';

extension _VbxEditorAppSyntaxHint on _VbxEditorAppState {
  void _attachEditorListener(EditorTab tab) {
    String lastText = tab.controller.text;

    bool isProcessingAutoFormat = false;

    tab.controller.addListener(() {
      if (!mounted || isProcessingAutoFormat) {
        return;
      }

      final currentText = tab.controller.text;
      final textChanged = currentText != lastText;

      final isVbFile =
          tab.filePath == null || FileService.isExecutable(tab.filePath);

      // ------------------------------------------------------------
      // Auto-Einrückung
      // ------------------------------------------------------------

      if (textChanged &&
          isVbFile &&
          currentText.length == lastText.length + 1 &&
          tab.controller.selection.baseOffset > 0 &&
          tab.controller.selection.baseOffset <= currentText.length &&
          currentText[tab.controller.selection.baseOffset - 1] == '\n') {
        final adjusted = applyAutoIndent(
          currentText,
          tab.controller.selection.baseOffset,
        );

        if (adjusted != null) {
          isProcessingAutoFormat = true;

          tab.controller.value = TextEditingValue(
            text: adjusted.text,
            selection: TextSelection.collapsed(offset: adjusted.cursor),
          );

          isProcessingAutoFormat = false;
        }
      }

      // ------------------------------------------------------------
      // Auto-Closing für Anführungszeichen
      // ------------------------------------------------------------

      if (textChanged &&
          isVbFile &&
          currentText.length == lastText.length + 1 &&
          tab.controller.selection.baseOffset > 0 &&
          tab.controller.selection.baseOffset <= currentText.length &&
          currentText[tab.controller.selection.baseOffset - 1] == '"') {
        final adjusted = applyAutoCloseQuote(
          currentText,
          tab.controller.selection.baseOffset,
        );

        if (adjusted != null) {
          isProcessingAutoFormat = true;

          tab.controller.value = TextEditingValue(
            text: adjusted.text,
            selection: TextSelection.collapsed(offset: adjusted.cursor),
          );

          isProcessingAutoFormat = false;
        }
      }

      // ------------------------------------------------------------
      // Syntax-Hint ermitteln
      // ------------------------------------------------------------

      final syntaxResult = tab == _currentTab
          ? _findSyntaxAndParamForCursor(tab)
          : null;

      final lineColumn = tab == _currentTab ? _lineColumnFor(tab) : null;

      if (tab == _currentTab) {
        _activeOpenParenIndex = syntaxResult?.openParenIndex;
      }

      // ------------------------------------------------------------
      // Textänderung:
      // Ein alter "dismissed"-Status gehört nicht mehr zum neuen Text.
      //
      // Wichtig:
      // Esc schließt nur den aktuellen Tooltip. Sobald der Benutzer
      // danach etwas löscht/eingibt, darf ein neuer Tooltip erscheinen.
      // ------------------------------------------------------------

      if (textChanged) {
        _dismissedParenIndex = null;
      }

      setState(() {
        if (textChanged && !tab.modified) {
          tab.markModified();
        }

        if (tab == _currentTab) {
          _currentSyntaxInfo = syntaxResult?.info;
          _currentParamIndex = syntaxResult?.paramIndex ?? 0;

          if (lineColumn != null) {
            _currentLine = lineColumn.line;
            _currentColumn = lineColumn.column;
          }
        }
      });

      // ------------------------------------------------------------
      // Syntax-Hint anzeigen / verstecken
      // ------------------------------------------------------------

      if (tab == _currentTab) {
        final shouldShow =
            syntaxResult != null &&
            syntaxResult.openParenIndex != _dismissedParenIndex;

        if (shouldShow) {
          _updateSyntaxHintOverlay(
            tab,
            syntaxResult!.info,
            syntaxResult.paramIndex,
            tab.controller.text,
            syntaxResult.openParenIndex,
          );
        } else {
          _syntaxHint.hide();
        }
      }

      // ------------------------------------------------------------
      // Autocomplete
      // ------------------------------------------------------------

      if (tab == _currentTab && textChanged) {
        _handleAutocompleteTrigger(tab);
      }

      // ------------------------------------------------------------
      // Textzustand merken
      // ------------------------------------------------------------

      lastText = tab.controller.text;
    });
  }

  ({int line, int column}) _lineColumnFor(EditorTab tab) {
    final text = tab.controller.text;
    final cursor = tab.controller.selection.baseOffset;

    if (cursor < 0) {
      return (line: 1, column: 1);
    }

    final safeCursor = cursor > text.length ? text.length : cursor;
    final textBeforeCursor = text.substring(0, safeCursor);

    final line = '\n'.allMatches(textBeforeCursor).length + 1;
    final lastNewline = textBeforeCursor.lastIndexOf('\n');
    final column = safeCursor - lastNewline;

    return (line: line, column: column);
  }

  ({int line, int column}) _lineColumnForOffset(String text, int offset) {
    final safeOffset = offset < 0
        ? 0
        : (offset > text.length ? text.length : offset);

    final textBeforeOffset = text.substring(0, safeOffset);

    final line = '\n'.allMatches(textBeforeOffset).length + 1;
    final lastNewline = textBeforeOffset.lastIndexOf('\n');
    final column = safeOffset - lastNewline;

    return (line: line, column: column);
  }

  ({VbxSyntaxInfo info, int paramIndex, int openParenIndex})?
  _findSyntaxAndParamForCursor(EditorTab tab) {
    final text = tab.controller.text;
    final cursor = tab.controller.selection.baseOffset;

    if (cursor < 0 || cursor > text.length) {
      return null;
    }

    // ------------------------------------------------------------
    // Nächste nicht geschlossene "(" vor dem Cursor suchen.
    // ------------------------------------------------------------

    var depth = 0;
    var inString = false;
    int? openParenIndex;

    for (var i = cursor - 1; i >= 0; i--) {
      final ch = text[i];

      if (ch == '"') {
        inString = !inString;
        continue;
      }

      if (inString) {
        continue;
      }

      if (ch == ')') {
        depth++;
        continue;
      }

      if (ch == '(') {
        if (depth == 0) {
          openParenIndex = i;
          break;
        }

        depth--;
      }

      // ----------------------------------------------------------
      // Wenn wir eine neue Zeile erreichen und dort kein
      // geöffneter Aufruf begonnen wurde, nicht auf einen alten
      // Funktionsaufruf aus einer vorherigen Zeile zurückfallen.
      //
      // Dadurch passiert nicht mehr:
      //
      //   Print app.StartupPath(
      //
      //   Print app.ExecutablePath
      //                         ^
      //
      // -> Tooltip von StartupPath
      // ----------------------------------------------------------

      if (ch == '\n' && depth == 0) {
        break;
      }
    }

    if (openParenIndex == null) {
      return null;
    }

    // ------------------------------------------------------------
    // Funktionsname vor der "(" ermitteln:
    // modul.Funktion oder Funktion
    // ------------------------------------------------------------

    final beforeParen = text.substring(0, openParenIndex);

    final nameMatch = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)(\.([A-Za-z_][A-Za-z0-9_]*))?$',
    ).firstMatch(beforeParen);

    if (nameMatch == null) {
      return null;
    }

    final fullName = nameMatch.group(3) != null
        ? '${nameMatch.group(1)}.${nameMatch.group(3)}'
        : nameMatch.group(1)!;

    final info = _syntaxService.findFullName(fullName);

    if (info == null) {
      return null;
    }

    // ------------------------------------------------------------
    // Aktuellen Parameterindex bestimmen
    // ------------------------------------------------------------

    final inside = text.substring(openParenIndex + 1, cursor);

    var paramDepth = 0;
    var insideParamString = false;
    var paramIndex = 0;

    for (var i = 0; i < inside.length; i++) {
      final ch = inside[i];

      if (ch == '"') {
        insideParamString = !insideParamString;
        continue;
      }

      if (insideParamString) {
        continue;
      }

      if (ch == '(' || ch == '[') {
        paramDepth++;
        continue;
      }

      if (ch == ')' || ch == ']') {
        paramDepth--;
        continue;
      }

      if (ch == ',' && paramDepth == 0) {
        paramIndex++;
      }
    }

    return (info: info, paramIndex: paramIndex, openParenIndex: openParenIndex);
  }

  void _updateSyntaxHintOverlay(
    EditorTab tab,
    VbxSyntaxInfo info,
    int paramIndex,
    String text,
    int anchorOffset,
  ) {
    if (_bodyContext == null) {
      return;
    }

    const toolbarHeight = 48.0;
    const tabHeight = 40.0;

    const gutterWidth = 44.0;

    // Padding(
    //   padding: EdgeInsets.all(4)
    // )
    // +
    // InputDecoration.contentPadding:
    //   EdgeInsets.all(8)
    const editorPadding = 12.0;

    // Muss zum TextField passen.
    final lineHeight = _fontSize * 1.4;

    final safeOffset = anchorOffset.clamp(0, text.length);

    // Anfang der aktuellen Zeile.
    final lineStart = safeOffset == 0
        ? 0
        : text.lastIndexOf('\n', safeOffset - 1) + 1;

    // Nullbasierter Zeilenindex.
    final lineIndex = '\n'.allMatches(text.substring(0, safeOffset)).length;

    // Text von Zeilenanfang bis zur "(".
    final textBeforeAnchorOnLine = text.substring(lineStart, safeOffset);

    final painter = TextPainter(
      text: TextSpan(
        text: textBeforeAnchorOnLine,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: _fontSize,
          height: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final scrollOffset = tab.scrollController.hasClients
        ? tab.scrollController.offset
        : 0.0;

    final dx = gutterWidth + editorPadding + painter.width;

    // Obere Kante der aktuellen Textzeile.
    final lineY =
        toolbarHeight +
        tabHeight +
        editorPadding +
        (lineIndex * lineHeight) -
        scrollOffset;

    // Tooltip unterhalb der aktuellen Zeile.
    final dy = lineY + lineHeight;

    final position = Offset(dx, dy);

    if (_syntaxHint.isVisible) {
      _syntaxHint.update(
        position: position,
        info: info,
        paramIndex: paramIndex,
        isDark: _isDarkTheme,
      );
    } else {
      _syntaxHint.show(
        context: _bodyContext!,
        position: position,
        info: info,
        paramIndex: paramIndex,
        isDark: _isDarkTheme,
      );
    }
  }
}
