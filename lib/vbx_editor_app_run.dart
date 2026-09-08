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

    final optionalWarnings = warnings.where((w) => w.isOptionalModule).toList();

    if (optionalWarnings.isNotEmpty) {
      _autoInsertUseDirective(optionalWarnings);

      await _saveCurrentFile();

      if (tab.filePath == null || tab.modified) {
        return;
      }
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

  // --- Dialog für fehlende #use-Module (aktuell ungenutzt, da automatisch
  // eingefügt wird -- bleibt als Baustein für spätere Rückfrage-Option) ---
  Future<bool?> _showUsageWarningsDialog(List<ModuleUsageIssue> warnings) {
    return showDialog<bool>(
      context: _navigatorKey.currentContext!,
      builder: (context) {
        return AlertDialog(
          title: const Text('Mögliche fehlende #use-Module'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Folgende Namespaces werden verwendet, sind aber '
                  'weder Core-Module noch per #use deklariert:',
                ),
                const SizedBox(height: 8),
                ...warnings.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Zeile ${w.line}: ${w.module}.${w.function}(...)',
                      style: const TextStyle(fontFamily: 'Consolas'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Trotzdem ausführen'),
            ),
          ],
        );
      },
    );
  }

  void _autoInsertUseDirective(List<ModuleUsageIssue> warnings) {
    final tab = _currentTab;

    if (tab == null) {
      return;
    }

    // Nur optionale Module dürfen automatisch in #use eingetragen werden.
    final missingModules = warnings
        .where((w) => w.isOptionalModule)
        .map((w) => w.module)
        .toSet();

    // Es gibt nichts einzufügen.
    if (missingModules.isEmpty) {
      return;
    }

    final text = tab.controller.text;
    var lines = text.split('\n');

    if (lines.isEmpty) {
      lines = [''];
    }

    final useDirectiveRegex = RegExp(r'^#use\s+(.*)$', caseSensitive: false);

    // ------------------------------------------------------------
    // Vorhandene #use-Direktiven suchen.
    //
    // Wir akzeptieren nur die erste echte #use-Direktive.
    // Weitere #use-Zeilen werden entfernt.
    // ------------------------------------------------------------

    final existingModules = <String>{};
    int? firstUseIndex;

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      final match = useDirectiveRegex.firstMatch(trimmed);

      if (match == null) {
        continue;
      }

      if (firstUseIndex == null) {
        firstUseIndex = i;

        final modules = match
            .group(1)!
            .split(',')
            .map((m) => m.trim())
            .where((m) => m.isNotEmpty);

        existingModules.addAll(modules);
      }
    }

    // ------------------------------------------------------------
    // Fehlende optionale Module hinzufügen.
    // ------------------------------------------------------------

    existingModules.addAll(missingModules);

    final allModules = existingModules.toList()..sort();

    final newUseLine = '#use ${allModules.join(',')}';

    // ------------------------------------------------------------
    // Vorhandene #use-Zeile aktualisieren.
    // ------------------------------------------------------------

    if (firstUseIndex != null) {
      lines[firstUseIndex] = newUseLine;

      // Alle weiteren #use-Zeilen entfernen.
      for (var i = lines.length - 1; i > firstUseIndex!; i--) {
        if (useDirectiveRegex.hasMatch(lines[i].trim())) {
          lines.removeAt(i);
        }
      }
    } else {
      // Keine #use-Zeile vorhanden:
      // Neue #use-Zeile ganz oben einfügen.
      lines.insert(0, newUseLine);
    }

    final newText = lines.join('\n');

    // Cursorposition möglichst erhalten.
    final oldSelection = tab.controller.selection;

    var offset = oldSelection.baseOffset;

    if (offset < 0) {
      offset = 0;
    }

    // Wenn eine neue Zeile eingefügt wurde, verschiebt sich der Cursor
    // um deren Länge.
    if (firstUseIndex == null) {
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
  }

  bool _isUseCommentLine(String trimmedLine) {
    final withoutComment = trimmedLine.replaceFirst(RegExp(r"^'\s*"), '');

    return withoutComment.toLowerCase().startsWith('#use');
  }
}
