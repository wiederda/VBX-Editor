part of 'vbx_editor_app.dart';

extension _VbxEditorAppRun on _VbxEditorAppState {
  Future<void> _runCurrentFile() async {
    final tab = _currentTab;

    if (tab == null || tab.controller.text.trim().isEmpty) {
      return;
    }

    if (tab.filePath == null || tab.modified) {
      await _saveCurrentFile();
    }

    if (tab.filePath == null || tab.modified) {
      return;
    }

    final warnings = _usageCheckService.check(tab.controller.text);
    await _ensureUseDirectivesClean(warnings);

    if (tab.filePath == null || tab.modified) {
      return;
    }

    setState(() {
      _isRunning = true;
      _runOutput = '';
      _panelVisible = true;
      _outputPanel = 0;
    });

    final result = await _runnerService.run(tab.filePath!);

    if (!mounted) {
      return;
    }

    if (result.cancelled) {
      setState(() {
        _isRunning = false;
        _isBuilding = false;
        _runOutput = 'Vorgang wurde abgebrochen.';
      });

      tab.focusNode.requestFocus();
      return;
    }

    setState(() {
      _isRunning = false;

      if (result.stdout.isNotEmpty && result.stderr.isNotEmpty) {
        _runOutput = '${result.stdout}\n${result.stderr}';
      } else if (result.stdout.isNotEmpty) {
        _runOutput = result.stdout;
      } else {
        _runOutput = result.stderr;
      }
    });

    tab.focusNode.requestFocus();
  }

  void _stopCurrentFile() {
    if (!_isRunning && !_isBuilding && !_isDryRunning) {
      return;
    }

    _runnerService.stop();

    final tab = _currentTab;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        tab?.focusNode.requestFocus();
      }
    });
  }

  Future<void> _buildCurrentFile() async {
    final tab = _currentTab;

    if (tab == null || tab.controller.text.trim().isEmpty) {
      return;
    }

    if (tab.filePath == null || tab.modified) {
      await _saveCurrentFile();
    }

    if (tab.filePath == null || tab.modified) {
      return;
    }

    setState(() {
      _isBuilding = true;
      _runOutput = '';
      _panelVisible = true;
      _outputPanel = 0;
    });

    final result = await _runnerService.runCommand('Build', tab.filePath!);

    if (!mounted) {
      return;
    }

    setState(() {
      _isBuilding = false;

      if (result.cancelled) {
        _runOutput = 'Vorgang wurde abgebrochen.';
        return;
      }

      if (result.stdout.isNotEmpty && result.stderr.isNotEmpty) {
        _runOutput = '${result.stdout}\n${result.stderr}';
      } else if (result.stdout.isNotEmpty) {
        _runOutput = result.stdout;
      } else if (result.stderr.isNotEmpty) {
        _runOutput = result.stderr;
      } else {
        _runOutput = 'Build fertig (Exit-Code ${result.exitCode})';
      }
    });
  }

  Future<void> _dryRunCurrentFile() async {
    final tab = _currentTab;

    if (tab == null || tab.controller.text.trim().isEmpty) {
      return;
    }

    if (tab.filePath == null || tab.modified) {
      await _saveCurrentFile();
    }

    if (tab.filePath == null || tab.modified) {
      return;
    }

    final warnings = _usageCheckService.check(tab.controller.text);
    await _ensureUseDirectivesClean(warnings);

    if (tab.filePath == null || tab.modified) {
      return;
    }

    setState(() {
      _isDryRunning = true;
      _runOutput = '';
      _panelVisible = true;
      _outputPanel = 0;
    });

    final result = await _runnerService.runCommand('-dryrun', tab.filePath!);

    if (!mounted) {
      return;
    }

    setState(() {
      _isDryRunning = false;

      if (result.cancelled) {
        _runOutput = 'Vorgang wurde abgebrochen.';
        return;
      }

      if (result.stdout.isNotEmpty && result.stderr.isNotEmpty) {
        _runOutput = '${result.stdout}\n${result.stderr}';
      } else if (result.stdout.isNotEmpty) {
        _runOutput = result.stdout;
      } else if (result.stderr.isNotEmpty) {
        _runOutput = result.stderr;
      } else {
        _runOutput = 'Dry Run ok - keine Fehler gefunden.';
      }
    });

    tab.focusNode.requestFocus();
  }

  // ------------------------------------------------------------
  // Vereinheitlichte #use-Bereinigung.
  //
  // Läuft IMMER (nicht nur wenn Module fehlen), damit auch doppelte,
  // über die Datei verstreute ODER nicht mehr benötigte #use-Zeilen
  // konsolidiert werden.
  //
  // Ablauf:
  //   1. Module aus ALLEN #use-Zeilen sammeln (nicht nur der ersten).
  //   2. Bekannte optionale Module, die im Skript nicht (mehr)
  //      verwendet werden, wieder entfernen.
  //   3. Fehlende, aber tatsächlich verwendete optionale Module
  //      (aus den warnings) ergänzen.
  //   4. Alles auf eine einzige #use-Zeile reduzieren (oder die
  //      Zeile ganz entfernen, falls am Ende nichts übrig bleibt).
  // ------------------------------------------------------------
  Future<void> _ensureUseDirectivesClean(
    List<ModuleUsageIssue> warnings,
  ) async {
    final tab = _currentTab;

    if (tab == null) {
      return;
    }

    final missingModules = warnings
        .where((w) => w.isOptionalModule)
        .map((w) => w.module)
        .toSet();

    final text = tab.controller.text;
    var lines = text.split('\n');

    if (lines.isEmpty) {
      lines = [''];
    }

    final useDirectiveRegex = RegExp(r'^#use\s+(.*)$', caseSensitive: false);

    final existingModules = <String>{};
    final useLineIndices = <int>[];

    // Module aus ALLEN #use-Zeilen sammeln, nicht nur der ersten -
    // sonst gehen Module aus einer zweiten/dritten #use-Zeile beim
    // späteren Löschen verloren.
    for (var i = 0; i < lines.length; i++) {
      final match = useDirectiveRegex.firstMatch(lines[i].trim());

      if (match == null) {
        continue;
      }

      useLineIndices.add(i);

      final modules = match
          .group(1)!
          .split(',')
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty);

      existingModules.addAll(modules);
    }

    // Nicht mehr benötigte optionale Module entfernen. Nur bekannte
    // optionale Module werden angefasst - unbekannte/getippte Namen
    // in #use lassen wir bewusst unangetastet, damit hier nichts
    // "kaputt korrigiert" wird, was der Service nicht sicher kennt.
    final usedOptional = _usageCheckService.usedOptionalModules(text);

    existingModules.removeWhere((module) {
      final moduleLower = module.toLowerCase();

      return _usageCheckService.isKnownOptionalModule(moduleLower) &&
          !usedOptional.contains(moduleLower);
    });

    // Fehlende, tatsächlich verwendete optionale Module ergänzen.
    existingModules.addAll(missingModules);

    final allModules = existingModules.toList()..sort();
    final newUseLine = allModules.isEmpty
        ? null
        : '#use ${allModules.join(',')}';

    // Nichts zu tun: höchstens eine #use-Zeile vorhanden UND ihr
    // Inhalt entspricht bereits dem konsolidierten Ergebnis.
    final needsRewrite =
        useLineIndices.length > 1 ||
        (useLineIndices.length == 1 &&
            lines[useLineIndices.first].trim() != (newUseLine ?? '')) ||
        (useLineIndices.isEmpty && newUseLine != null);

    if (!needsRewrite) {
      return;
    }

    if (newUseLine == null) {
      // Alle Module wurden entfernt (keine mehr benötigt, keine
      // fehlend) -> #use-Zeile(n) komplett entfernen statt sie leer
      // zu lassen.
      for (var i = lines.length - 1; i >= 0; i--) {
        if (useDirectiveRegex.hasMatch(lines[i].trim())) {
          lines.removeAt(i);
        }
      }
    } else if (useLineIndices.isNotEmpty) {
      final firstUseIndex = useLineIndices.first;
      lines[firstUseIndex] = newUseLine;

      // Alle weiteren #use-Zeilen entfernen.
      for (var i = lines.length - 1; i > firstUseIndex; i--) {
        if (useDirectiveRegex.hasMatch(lines[i].trim())) {
          lines.removeAt(i);
        }
      }
    } else {
      // Keine #use-Zeile vorhanden: neue Zeile ganz oben einfügen.
      lines.insert(0, newUseLine);
    }

    final newText = lines.join('\n');

    // Cursorposition möglichst erhalten.
    final oldSelection = tab.controller.selection;

    var offset = oldSelection.baseOffset;

    if (offset < 0) {
      offset = 0;
    }

    // Wenn ganz oben eine neue Zeile eingefügt wurde, verschiebt sich
    // der Cursor um deren Länge.
    if (useLineIndices.isEmpty && newUseLine != null) {
      offset += newUseLine.length + 1;
    }

    if (offset > newText.length) {
      offset = newText.length;
    }

    tab.controller.value = tab.controller.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );

    await _saveCurrentFile();
  }

  bool _isUseCommentLine(String trimmedLine) {
    final withoutComment = trimmedLine.replaceFirst(RegExp(r"^'\s*"), '');

    return withoutComment.toLowerCase().startsWith('#use');
  }
}
