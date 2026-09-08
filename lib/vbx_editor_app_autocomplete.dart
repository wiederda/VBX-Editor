part of 'vbx_editor_app.dart';

extension _VbxEditorAppAutocomplete on _VbxEditorAppState {
  void _handleAutocompleteTrigger(EditorTab tab) {
    final text = tab.controller.text;
    final cursor = tab.controller.selection.baseOffset;

    if (cursor <= 0 || cursor > text.length) {
      _autocomplete.hide();
      return;
    }

    final beforeCursor = text.substring(0, cursor);

    // ------------------------------------------------------------
    // Fall 1: modul.Funktion
    // ------------------------------------------------------------

    final moduleMatch = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z0-9_]*)$',
    ).firstMatch(beforeCursor);

    if (moduleMatch != null) {
      _handleModuleAutocomplete(tab, moduleMatch);
      return;
    }

    // ------------------------------------------------------------
    // Fall 2: lokale Variable (Dim/Public)
    // ------------------------------------------------------------

    _handleIdentifierAutocomplete(tab, beforeCursor);
  }

  void _handleModuleAutocomplete(EditorTab tab, RegExpMatch moduleMatch) {
    final module = moduleMatch.group(1)!;
    final partial = moduleMatch.group(2)!.toLowerCase();

    final allFunctions = _syntaxService.findModuleFunctions(module);

    if (allFunctions.isEmpty) {
      _autocomplete.hide();
      return;
    }

    final filtered = allFunctions
        .where(
          (f) =>
              f.name.toLowerCase().startsWith(partial) &&
              f.name.toLowerCase() != partial,
        )
        .toList();

    if (filtered.isEmpty) {
      _autocomplete.hide();
      return;
    }

    _showAutocompletePopup(
      tab,
      filtered,
      onSelect: (info) => _insertAutocompleteSelection(tab, info),
    );
  }

  void _handleIdentifierAutocomplete(EditorTab tab, String beforeCursor) {
    final identMatch = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)$',
    ).firstMatch(beforeCursor);

    if (identMatch == null) {
      _autocomplete.hide();
      return;
    }

    final partial = identMatch.group(1)!;

    // Erst ab 2 Zeichen vorschlagen, sonst poppt bei jedem einzelnen
    // Buchstaben eine Liste auf.
    if (partial.length < 2) {
      _autocomplete.hide();
      return;
    }

    // Während man selbst gerade "Dim xyz" / "Public xyz" tippt, nicht
    // den gerade entstehenden Namen sich selbst vorschlagen.
    final lineStart = beforeCursor.lastIndexOf('\n') + 1;
    final currentLine = beforeCursor.substring(lineStart);

    final isDeclarationLine = RegExp(
      r'^\s*(Dim|Public)\s+[A-Za-z_][A-Za-z0-9_]*$',
      caseSensitive: false,
    ).hasMatch(currentLine);

    if (isDeclarationLine) {
      _autocomplete.hide();
      return;
    }

    final declared = _findDeclaredIdentifiers(tab.controller.text);

    final partialLower = partial.toLowerCase();

    final filtered =
        declared
            .where(
              (name) =>
                  name.toLowerCase().startsWith(partialLower) &&
                  name.toLowerCase() != partialLower,
            )
            .toList()
          ..sort();

    if (filtered.isEmpty) {
      _autocomplete.hide();
      return;
    }

    final suggestions = filtered
        .map(
          (name) =>
              VbxSyntaxInfo(name: name, syntax: name, description: 'Variable'),
        )
        .toList();

    _showAutocompletePopup(
      tab,
      suggestions,
      onSelect: (info) => _insertIdentifierSelection(tab, info),
    );
  }

  List<String> _findDeclaredIdentifiers(String text) {
    final regex = RegExp(
      r'\b(?:Dim|Public)\s+([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false,
    );

    final names = <String>{};

    for (final match in regex.allMatches(text)) {
      final name = match.group(1);

      if (name != null) {
        names.add(name);
      }
    }

    return names.toList();
  }

  void _showAutocompletePopup(
    EditorTab tab,
    List<VbxSyntaxInfo> suggestions, {
    required void Function(VbxSyntaxInfo info) onSelect,
  }) {
    if (_autocomplete.isVisible) {
      _autocomplete.update(suggestions);
      return;
    }

    if (_bodyContext == null) {
      return;
    }

    final lineColumn = _lineColumnFor(tab);
    const lineHeight = 20.0;
    const charWidth = 8.4;

    final toolbarAndTabsHeight = 48.0 + 40.0;
    const editorPadding = 12.0;
    const gutterWidth = 44.0;

    final dx =
        gutterWidth + editorPadding + (lineColumn.column - 1) * charWidth;
    final dy =
        toolbarAndTabsHeight +
        editorPadding +
        lineColumn.line * lineHeight -
        (tab.scrollController.hasClients ? tab.scrollController.offset : 0);

    _autocomplete.show(
      context: _bodyContext!,
      position: Offset(dx, dy),
      suggestions: suggestions,
      onSelect: onSelect,
    );
  }

  void _insertIdentifierSelection(EditorTab tab, VbxSyntaxInfo info) {
    final text = tab.controller.text;
    final cursor = tab.controller.selection.baseOffset;

    if (cursor < 0 || cursor > text.length) {
      return;
    }

    final beforeCursor = text.substring(0, cursor);
    final match = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(beforeCursor);

    if (match == null) {
      return;
    }

    final partialStart = match.start;

    final newText =
        text.substring(0, partialStart) + info.name + text.substring(cursor);
    final newCursor = partialStart + info.name.length;

    tab.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    tab.focusNode.requestFocus();
  }

  void _insertAutocompleteSelection(EditorTab tab, VbxSyntaxInfo info) {
    final text = tab.controller.text;
    final cursor = tab.controller.selection.baseOffset;

    if (cursor < 0 || cursor > text.length) {
      return;
    }

    final beforeCursor = text.substring(0, cursor);
    final match = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z0-9_]*)$',
    ).firstMatch(beforeCursor);

    if (match == null) {
      return;
    }

    final partialStart = match.start + match.group(1)!.length + 1;

    final newText =
        text.substring(0, partialStart) +
        info.name +
        '(' +
        text.substring(cursor);

    final newCursor = partialStart + info.name.length + 1;

    tab.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    tab.focusNode.requestFocus();
  }
}
