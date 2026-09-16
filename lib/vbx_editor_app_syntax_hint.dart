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

    // ------------------------------------------------------------
    // Scroll-Listener: hält den Syntax-Hint beim Scrollen mit der
    // Zeile synchron (VB.NET-artig), statt an der alten Bildschirm-
    // position stehen zu bleiben. Ohne diesen Listener passiert beim
    // reinen Scrollen (ohne Tastatureingabe) gar kein Reposition-Call,
    // weil nur tab.controller (Text/Selektion) beobachtet wird.
    // ------------------------------------------------------------
    tab.scrollController.addListener(() {
      if (!mounted || tab != _currentTab || !_syntaxHint.isVisible) {
        return;
      }

      final info = _currentSyntaxInfo;
      final openParenIndex = _activeOpenParenIndex;

      if (info == null || openParenIndex == null) {
        _syntaxHint.hide();
        return;
      }

      _updateSyntaxHintOverlay(
        tab,
        info,
        _currentParamIndex,
        tab.controller.text,
        openParenIndex,
      );
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
      // geöffneten Aufruf begonnen wurde, nicht auf einen alten
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

  // ------------------------------------------------------------
  // Sucht rekursiv im Unterbaum von [context] nach dem
  // EditableTextState des zugrundeliegenden TextFields.
  //
  // TextField gibt sein internes EditableText nicht direkt über
  // einen eigenen Key her -- man muss danach suchen. Der übergebene
  // [context] sollte der Kontext des TextFields selbst sein (bzw.
  // eines direkten Vorfahren davon), damit hier nicht versehentlich
  // ein EditableText aus einem anderen TextField (z.B. der
  // Such-Leiste) gefunden wird.
  // ------------------------------------------------------------
  EditableTextState? _findEditableTextState(BuildContext context) {
    EditableTextState? result;

    context.visitChildElements((element) {
      if (result != null) {
        return;
      }

      if (element.widget is EditableText) {
        final state = (element as StatefulElement).state;

        if (state is EditableTextState) {
          result = state;
          return;
        }
      }

      result ??= _findEditableTextState(element);
    });

    return result;
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

    final fieldRenderObject = _editorFieldKey.currentContext
        ?.findRenderObject();
    final overlayRenderObject = Overlay.of(
      _bodyContext!,
    ).context.findRenderObject();

    if (fieldRenderObject is! RenderBox || overlayRenderObject is! RenderBox) {
      return;
    }

    // ------------------------------------------------------------
    // Statt die Y-Position aus einer geschätzten Zeilenhöhe
    // (lineIndex * lineHeight) hochzurechnen -- was bei jeder Zeile
    // einen winzigen Messfehler gegenüber der tatsächlich von
    // RenderEditable gezeichneten Zeilenhöhe aufsummierte ("Tooltip
    // wandert bei längeren Skripten immer weiter nach oben ab") --
    // fragen wir RenderEditable direkt nach der echten Cursor-
    // Position. Das ist exakt dieselbe Berechnung, die Flutter
    // intern für den blinkenden Text-Cursor verwendet, kennt also
    // Zeilenhöhe, Zeilenumbrüche und Scroll-Zustand bereits korrekt.
    // ------------------------------------------------------------

    final editableState = _findEditableTextState(
      _editorFieldKey.currentContext!,
    );

    if (editableState == null) {
      return;
    }

    final renderEditable = editableState.renderEditable;

    // Zusätzlicher Abstand zwischen der aktuellen Zeile und dem
    // Tooltip, damit dieser nicht direkt auf dem gerade getippten
    // Text bzw. der Zeile darunter klebt.
    const tooltipVerticalGap = 8.0;

    final safeOffset = anchorOffset.clamp(0, text.length);

    final caretRect = renderEditable.getLocalRectForCaret(
      TextPosition(offset: safeOffset),
    );

    final caretGlobal = renderEditable.localToGlobal(caretRect.bottomLeft);
    final caretInOverlay = overlayRenderObject.globalToLocal(caretGlobal);

    final dx = caretInOverlay.dx;
    final dy = caretInOverlay.dy + tooltipVerticalGap;

    // ------------------------------------------------------------
    // Sichtbarkeit prüfen: wurde die verankerte Zeile (z.B. durch
    // Scrollen) aus dem sichtbaren Editor-Bereich hinausgeschoben,
    // Tooltip ausblenden statt ihn hinter Toolbar/Output-Panel oder
    // weit außerhalb des Fensters zu zeichnen.
    // ------------------------------------------------------------

    final fieldOrigin = overlayRenderObject.globalToLocal(
      fieldRenderObject.localToGlobal(Offset.zero),
    );
    final fieldHeight = fieldRenderObject.size.height;
    final fieldTop = fieldOrigin.dy;
    final fieldBottom = fieldOrigin.dy + fieldHeight;

    if (caretInOverlay.dy < fieldTop || caretInOverlay.dy > fieldBottom) {
      _syntaxHint.hide();
      return;
    }

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
