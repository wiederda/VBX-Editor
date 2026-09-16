part of 'vbx_editor_app.dart';

extension _VbxEditorAppFiles on _VbxEditorAppState {
  void _createInitialTab() {
    final tab = EditorTab(
      name: _newUntitledName(),
      content: kDefaultTabTemplate,
      highlightConfig: _highlightService.config,
    );

    _attachEditorListener(tab);

    _tabs.add(tab);
  }

  void _newTab() {
    final tab = EditorTab(
      name: _newUntitledName(),
      content: kDefaultTabTemplate,
      highlightConfig: _highlightService.config,
    );

    _attachEditorListener(tab);

    setState(() {
      _tabs.add(tab);
      _activeTab = _tabs.length - 1;
    });
  }

  Future<void> _openFile() async {
    final file = await _fileService.openVbxFile();

    if (file == null) {
      return;
    }

    await _openFilePath(file.path);
  }

  Future<void> _openFilePath(String path) async {
    final file = File(path);

    if (!await file.exists()) {
      return;
    }

    final lower = path.toLowerCase();
    final isKnownExtension = FileService.allowedExtensions.any(
      (ext) => lower.endsWith('.$ext'),
    );

    if (!isKnownExtension) {
      // Endung unbekannt (z.B. "backup.txt.old") -- bevor die Datei
      // abgelehnt wird, den tatsächlichen Inhalt prüfen. Reiner Text
      // wird trotzdem geöffnet, statt sich rein auf die Endung zu
      // verlassen.
      final looksLikeText = await FileService.looksLikeTextFile(file);

      if (!looksLikeText) {
        setState(() {
          _runOutput = 'Dateityp wird nicht unterstützt: ${_fileName(path)}';
        });
        return;
      }
    }

    // Ist die Datei bereits geöffnet?
    final existingIndex = _tabs.indexWhere(
      (tab) =>
          tab.filePath != null &&
          File(tab.filePath!).absolute.path == file.absolute.path,
    );

    if (existingIndex >= 0) {
      setState(() {
        _activeTab = existingIndex;
      });

      return;
    }

    final content = await _fileService.readFile(file);

    final tab = EditorTab(
      name: _fileName(path),
      filePath: path,
      content: content,
      highlightConfig: _highlightService.config,
    );

    _attachEditorListener(tab);

    // Gerade geladene Datei ist noch nicht geändert.
    tab.markSaved();

    final currentTab = _currentTab;

    final isBlankTab =
        currentTab != null &&
        currentTab.filePath == null &&
        !currentTab.modified &&
        (currentTab.controller.text.trim().isEmpty ||
            currentTab.controller.text.trim() == kDefaultTabTemplate.trim());

    if (isBlankTab) {
      currentTab.dispose();

      setState(() {
        _tabs[_activeTab] = tab;
      });
    } else {
      setState(() {
        _tabs.add(tab);
        _activeTab = _tabs.length - 1;
      });
    }
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    for (final file in files) {
      await _openFilePath(file.path);
    }
  }

  void _reindentIfVb(EditorTab tab) {
    final isVb = tab.filePath == null || FileService.isExecutable(tab.filePath);

    if (!isVb) {
      return;
    }

    final reindented = reindentDocument(tab.controller.text);

    if (reindented == tab.controller.text) {
      return;
    }

    tab.controller.value = tab.controller.value.copyWith(
      text: reindented,
      selection: TextSelection.collapsed(offset: reindented.length),
    );
  }

  Future<void> _saveCurrentFile() async {
    final tab = _currentTab;

    if (tab == null || tab.controller.text.trim().isEmpty) {
      return;
    }

    _reindentIfVb(tab);

    final path = await _fileService.saveVbxFile(
      content: tab.controller.text,
      currentPath: tab.filePath,
    );

    if (path == null) {
      return;
    }

    setState(() {
      tab.filePath = path;
      tab.name = _fileName(path);
      tab.markSaved();
    });
  }

  Future<void> _saveCurrentFileAs() async {
    final tab = _currentTab;

    if (tab == null || tab.controller.text.trim().isEmpty) {
      return;
    }

    _reindentIfVb(tab);

    final path = await _fileService.saveVbxFile(
      content: tab.controller.text,
      currentPath: null,
    );

    if (path == null) {
      return;
    }

    setState(() {
      tab.filePath = path;
      tab.name = _fileName(path);
      tab.markSaved();
    });
  }

  Future<void> _reloadCurrentFile() async {
    final tab = _currentTab;

    if (tab == null || tab.filePath == null) {
      return;
    }

    if (tab.modified) {
      final confirmed = await showDialog<bool>(
        context: _navigatorKey.currentContext!,
        builder: (context) {
          return AlertDialog(
            title: const Text('Neu laden'),
            content: Text(
              '${tab.name} enthält ungespeicherte Änderungen. '
              'Diese gehen beim Neuladen verloren. Trotzdem neu laden?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Neu laden'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }
    }

    final file = File(tab.filePath!);

    if (!await file.exists()) {
      setState(() {
        _runOutput = 'Datei nicht gefunden: ${tab.filePath}';
      });
      return;
    }

    final content = await _fileService.readFile(file);

    if (!mounted) {
      return;
    }

    setState(() {
      tab.setContent(content);
    });
  }

  Future<void> _closeTab(int index) async {
    final tab = _tabs[index];

    if (tab.modified) {
      final result = await showDialog<String>(
        context: _navigatorKey.currentContext!,
        builder: (context) {
          return AlertDialog(
            title: Text('${tab.name} wurde geändert'),
            content: const Text('Möchtest du die Änderungen speichern?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'no'),
                child: const Text('Nein'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'yes'),
                child: const Text('Ja'),
              ),
            ],
          );
        },
      );

      if (result == null || result == 'cancel') {
        return;
      }

      if (result == 'yes') {
        await _saveTab(tab);

        if (tab.modified) {
          // Speichern wurde abgebrochen (z. B. Speichern-Dialog mit "Abbrechen").
          return;
        }
      }

      // result == 'no' -> Änderungen bewusst verwerfen, einfach weiter.
    }

    final wasLastTab = _tabs.length == 1;

    setState(() {
      tab.dispose();
      _tabs.removeAt(index);

      if (_activeTab > index) {
        _activeTab--;
      } else if (_activeTab >= _tabs.length && _tabs.isNotEmpty) {
        _activeTab = _tabs.length - 1;
      }

      // Tooltip gehörte ggf. zum gerade geschlossenen Tab -- sonst
      // bleibt er über dem jetzt sichtbaren, anderen Tab hängen,
      // obwohl dort gar nichts ausgelöst wurde. Für den neuen aktiven
      // Tab (falls noch einer übrig ist) neu bestimmen, ob dort ein
      // Tooltip passt.
      final newCurrentTab = _currentTab;

      if (newCurrentTab != null) {
        final result = _findSyntaxAndParamForCursor(newCurrentTab);

        _currentSyntaxInfo = result?.info;
        _currentParamIndex = result?.paramIndex ?? 0;
        _activeOpenParenIndex = result?.openParenIndex;
        _dismissedParenIndex = null;

        if (result != null) {
          _updateSyntaxHintOverlay(
            newCurrentTab,
            result.info,
            result.paramIndex,
            newCurrentTab.controller.text,
            result.openParenIndex,
          );
        } else {
          _syntaxHint.hide();
        }
      } else {
        _syntaxHint.hide();
      }
    });

    if (wasLastTab) {
      await _saveSession();
      exit(0);
    }
  }

  Future<void> _saveTab(EditorTab tab) async {
    _reindentIfVb(tab);

    final path = await _fileService.saveVbxFile(
      content: tab.controller.text,
      currentPath: tab.filePath,
    );

    if (path == null) {
      return;
    }

    setState(() {
      tab.filePath = path;
      tab.name = _fileName(path);
      tab.markSaved();
    });
  }
}
