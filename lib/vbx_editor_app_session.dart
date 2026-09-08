part of 'vbx_editor_app.dart';

extension _VbxEditorAppSession on _VbxEditorAppState {
  Future<void> _startupSequence() async {
    await _restoreSessionOrCreateInitialTab();

    if (widget.initialFilePath != null) {
      await _openFilePath(widget.initialFilePath!);
    }
  }

  Future<void> _loadSyntax() async {
    await _syntaxService.load();

    final info = _syntaxService.findFullName('array.Create');

    if (info != null) {
      debugPrint(info.syntax);
      debugPrint(info.description);
    }
  }

  Future<void> _restoreSessionOrCreateInitialTab() async {
    final session = await _sessionService.load();

    if (session == null || session.tabs.isEmpty) {
      _createInitialTab();
      if (mounted) setState(() {});
      return;
    }

    for (final state in session.tabs) {
      EditorTab tab;

      if (state.path != null && await File(state.path!).exists()) {
        // Wenn es ungespeicherte Änderungen gab, DIE nehmen -- sonst
        // den aktuellen Stand von der Festplatte lesen.
        final content = state.modified && state.unsavedContent != null
            ? state.unsavedContent!
            : await File(state.path!).readAsString();

        tab = EditorTab(
          name: _fileName(state.path!),
          filePath: state.path,
          content: content,
          highlightConfig: _highlightService.config,
        );

        if (state.modified && state.unsavedContent != null) {
          tab.markModified();
        } else {
          tab.markSaved();
        }
      } else {
        tab = EditorTab(
          name: _newUntitledName(),
          content: state.unsavedContent ?? kDefaultTabTemplate,
          highlightConfig: _highlightService.config,
        );

        if ((state.unsavedContent ?? '').trim().isNotEmpty) {
          tab.markModified();
        }
      }

      _attachEditorListener(tab);
      _tabs.add(tab);
    }

    if (_tabs.isEmpty) {
      _createInitialTab();
    } else {
      _activeTab = session.activeIndex.clamp(0, _tabs.length - 1);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveSession() async {
    final states = _tabs
        .map(
          (t) => SessionTabState(
            path: t.filePath,
            modified: t.modified,
            unsavedContent: t.modified ? t.controller.text : null,
          ),
        )
        .toList();

    await _sessionService.save(states, _activeTab);
  }

  Future<void> _loadVbxVersion() async {
    final version = await _versionService.getVersion();

    if (!mounted) {
      return;
    }

    setState(() {
      _vbxVersion = version ?? 'VBX nicht gefunden';
    });
  }

  Future<void> _loadHighlight() async {
    await _highlightService.load();

    final config = _highlightService.config;

    if (!mounted || config == null) {
      return;
    }

    for (final tab in _tabs) {
      tab.setHighlightConfig(config);
    }

    setState(() {});
  }
}
