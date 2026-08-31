import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'editor_auto_format.dart';
import 'models/editor_tab.dart';
import 'services/config_service.dart';
import 'services/docs_service.dart';
import 'services/file_service.dart';
import 'services/highlight_service.dart';
import 'services/runner_service.dart';
import 'services/session_service.dart';
import 'services/single_instance_service.dart';
import 'services/syntax_service.dart';
import 'services/usage_check_service.dart';
import 'services/version_service.dart';
import 'templates.dart';
import 'widgets/autocomplete_overlay.dart';
import 'widgets/docs_panel.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/vbx_console.dart';
import 'widgets/comment_icons.dart';
import 'widgets/stop_icon.dart';

class VbxEditorApp extends StatefulWidget {
  final ConfigService configService;
  final String? initialFilePath;
  final SingleInstanceService singleInstanceService;

  const VbxEditorApp({
    super.key,
    required this.configService,
    required this.singleInstanceService,
    this.initialFilePath,
  });

  @override
  State<VbxEditorApp> createState() => _VbxEditorAppState();
}

class _VbxEditorAppState extends State<VbxEditorApp> with WindowListener {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final List<EditorTab> _tabs = [];
  final FileService _fileService = FileService();
  late final VbxVersionService _versionService;
  late final VbxRunnerService _runnerService;
  final VbxHighlightService _highlightService = VbxHighlightService();
  final VbxSyntaxService _syntaxService = VbxSyntaxService();
  final VbxUsageCheckService _usageCheckService = VbxUsageCheckService();
  final VbxDocsService _docsService = VbxDocsService();
  final VbxSessionService _sessionService = VbxSessionService();
  final AutocompleteController _autocomplete = AutocompleteController();

  TextSelection? _runOutputSelection;
  bool _docsVisible = false;
  double _fontSize = 14.0;
  BuildContext? _bodyContext;
  int _activeTab = 0;
  int _untitledCounter = 0;
  int _currentLine = 1;
  int _currentColumn = 1;
  int _outputPanel = 0;

  String _runOutput = '';
  bool _isRunning = false;
  bool _isBuilding = false;
  bool _panelVisible = false;
  bool get _isDarkTheme => widget.configService.theme == 'dark';

  StreamSubscription<String>? _fileOpenSubscription;

  String _vbxVersion = 'Version wird ermittelt ...';
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  int _searchMatchIndex = -1;
  List<int> _searchMatches = [];

  VbxSyntaxInfo? _currentSyntaxInfo;

  @override
  void initState() {
    super.initState();

    windowManager.addListener(this);
    windowManager.setPreventClose(true);

    _fontSize = widget.configService.fontSize;

    final executable = widget.configService.vbxExecutable;

    _versionService = VbxVersionService(executable: executable);
    _runnerService = VbxRunnerService(executable: executable);

    _startupSequence();
    _loadVbxVersion();
    _loadHighlight();
    _loadSyntax();
    _usageCheckService.load();

    _docsService.loadFromCache().then((_) {
      if (mounted) {
        setState(() {});
      }
    });

    _fileOpenSubscription = widget.singleInstanceService.onFileOpenRequested
        .listen((path) async {
          await windowManager.show();
          await windowManager.focus();

          if (path.isNotEmpty) {
            await _openFilePath(path);
          }
        });
  }

  Future<void> _startupSequence() async {
    await _restoreSessionOrCreateInitialTab();

    if (widget.initialFilePath != null) {
      await _openFilePath(widget.initialFilePath!);
    }
  }

  bool get _currentTabIsExecutable {
    final tab = _currentTab;

    if (tab == null) {
      return false;
    }

    // Ein noch nicht gespeicherter Tab (kein Pfad) gilt als VBX,
    // da er ja standardmäßig als .vb gespeichert wird.
    if (tab.filePath == null) {
      return true;
    }

    return FileService.isExecutable(tab.filePath);
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

  @override
  void onWindowClose() async {
    // Sofort ausblenden, damit die App optisch direkt "weg" ist.
    await windowManager.hide();

    // Danach in Ruhe im Hintergrund speichern.
    await _saveSession();

    // Erst jetzt den Prozess wirklich beenden.
    await windowManager.destroy();
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
    if (!_isRunning && !_isBuilding) {
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

  void _updateSearchMatches() {
    final tab = _currentTab;

    if (tab == null) {
      _searchMatches = [];
      _searchMatchIndex = -1;
      return;
    }

    final searchText = _searchController.text;

    if (searchText.isEmpty) {
      _searchMatches = [];
      _searchMatchIndex = -1;
      return;
    }

    final text = tab.controller.text;
    final matches = <int>[];

    var index = 0;

    while (index < text.length) {
      final found = text.indexOf(searchText, index);

      if (found == -1) {
        break;
      }

      matches.add(found);
      index = found + searchText.length;
    }

    _searchMatches = matches;

    if (_searchMatches.isEmpty) {
      _searchMatchIndex = -1;
      return;
    }

    // Aktuelle Cursorposition möglichst berücksichtigen.
    final cursor = tab.controller.selection.baseOffset;

    var selected = _searchMatches.indexWhere((match) => match >= cursor);

    if (selected == -1) {
      selected = 0;
    }

    _searchMatchIndex = selected;
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

  String _newUntitledName() {
    _untitledCounter++;

    return 'Unbenannt-${_untitledCounter}.vb';
  }

  void _openSearch() {
    setState(() {
      _searchVisible = true;
    });
  }

  void _closeSearch() {
    setState(() {
      _searchVisible = false;
      _searchController.clear();
    });
  }

  void _findNext() {
    final tab = _currentTab;

    if (tab == null || _searchController.text.isEmpty) {
      return;
    }

    _updateSearchMatches();

    if (_searchMatches.isEmpty) {
      return;
    }

    if (_searchMatchIndex == -1) {
      _searchMatchIndex = 0;
    } else {
      _searchMatchIndex = (_searchMatchIndex + 1) % _searchMatches.length;
    }

    _selectCurrentSearchMatch();
  }

  void _findPrevious() {
    final tab = _currentTab;

    if (tab == null || _searchController.text.isEmpty) {
      return;
    }

    _updateSearchMatches();

    if (_searchMatches.isEmpty) {
      return;
    }

    if (_searchMatchIndex == -1) {
      _searchMatchIndex = _searchMatches.length - 1;
    } else {
      _searchMatchIndex =
          (_searchMatchIndex - 1 + _searchMatches.length) %
          _searchMatches.length;
    }

    _selectCurrentSearchMatch();
  }

  void _selectCurrentSearchMatch() {
    final tab = _currentTab;
    if (tab == null) {
      return;
    }

    final searchText = _searchController.text;
    if (searchText.isEmpty) {
      return;
    }

    final text = tab.controller.text;
    final cursor = tab.controller.selection.baseOffset;

    if (cursor < 0 || cursor > text.length) {
      return;
    }

    var index = text.indexOf(searchText, cursor);

    if (index == -1) {
      index = text.indexOf(searchText);
    }

    if (index == -1) {
      return;
    }

    tab.controller.selection = TextSelection(
      baseOffset: index,
      extentOffset: index + searchText.length,
    );

    tab.focusNode.requestFocus();
  }

  bool get _hasSelection {
    final tab = _currentTab;

    if (tab == null) {
      return false;
    }

    final selection = tab.controller.selection;

    return selection.start != selection.end;
  }

  ({int lineStart, int lineEnd, List<String> lines}) _selectedLineRange(
    EditorTab tab,
  ) {
    final text = tab.controller.text;
    final selection = tab.controller.selection;

    var start = selection.start;
    var end = selection.end;

    if (start < 0) start = 0;
    if (end < 0) end = start;
    if (start > text.length) start = text.length;
    if (end > text.length) end = text.length;

    if (start > end) {
      final tmp = start;
      start = end;
      end = tmp;
    }

    // Auf ganze Zeilen erweitern.
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;

    var searchFrom = end;
    if (end > start && end > 0 && text[end - 1] == '\n') {
      // Endet die Auswahl genau auf einem Zeilenumbruch, die leere
      // Folgezeile nicht mehr mit einbeziehen.
      searchFrom = end - 1;
    }

    var lineEnd = text.indexOf('\n', searchFrom);
    if (lineEnd == -1) lineEnd = text.length;

    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');

    return (lineStart: lineStart, lineEnd: lineEnd, lines: lines);
  }

  void _applyLineEdit(
    EditorTab tab,
    int lineStart,
    int lineEnd,
    List<String> newLines,
  ) {
    final text = tab.controller.text;
    final block = text.substring(lineStart, lineEnd);
    final newBlock = newLines.join('\n');

    final newText =
        text.substring(0, lineStart) + newBlock + text.substring(lineEnd);

    final lengthDiff = newBlock.length - block.length;

    setState(() {
      tab.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: lineStart,
          extentOffset: lineEnd + lengthDiff,
        ),
      );
    });
  }

  void _commentSelectedLines() {
    final tab = _currentTab;

    if (tab == null || !_hasSelection) {
      return;
    }

    final range = _selectedLineRange(tab);

    final newLines = range.lines.map((l) {
      if (l.trim().isEmpty) {
        return l;
      }

      final indentMatch = RegExp(r'^(\s*)').firstMatch(l)!;
      final indent = indentMatch.group(1)!;

      return "$indent' ${l.substring(indent.length)}";
    }).toList();

    _applyLineEdit(tab, range.lineStart, range.lineEnd, newLines);
  }

  void _uncommentSelectedLines() {
    final tab = _currentTab;

    if (tab == null || !_hasSelection) {
      return;
    }

    final range = _selectedLineRange(tab);
    final commentPrefixRegex = RegExp(r"^(\s*)'\s?");

    final newLines = range.lines.map((l) {
      final match = commentPrefixRegex.firstMatch(l);

      if (match == null) {
        return l;
      }

      final ws = match.group(1)!;
      return ws + l.substring(match.end);
    }).toList();

    _applyLineEdit(tab, range.lineStart, range.lineEnd, newLines);
  }

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
        .where((f) => f.name.toLowerCase().startsWith(partial))
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

  void _createInitialTab() {
    final tab = EditorTab(
      name: _newUntitledName(),
      content: kDefaultTabTemplate,
      highlightConfig: _highlightService.config,
    );

    _attachEditorListener(tab);

    _tabs.add(tab);
  }

  void _attachEditorListener(EditorTab tab) {
    String lastText = tab.controller.text;
    bool isProcessingAutoFormat = false;

    tab.controller.addListener(() {
      if (!mounted || isProcessingAutoFormat) {
        return;
      }

      final currentText = tab.controller.text;
      final textChanged = currentText != lastText;

      // Auto-Einrückung / Block-Abschluss: genau ein Zeichen eingefügt,
      // und zwar ein Zeilenumbruch (Enter gedrückt).
      if (textChanged &&
          (tab.filePath == null || FileService.isExecutable(tab.filePath)) &&
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

      lastText = tab.controller.text;

      final syntaxInfo = tab == _currentTab
          ? _findSyntaxForCurrentLine(tab)
          : null;

      final lineColumn = tab == _currentTab ? _lineColumnFor(tab) : null;

      setState(() {
        if (textChanged && !tab.modified) {
          tab.markModified();
        }

        if (tab == _currentTab) {
          _currentSyntaxInfo = syntaxInfo;

          if (lineColumn != null) {
            _currentLine = lineColumn.line;
            _currentColumn = lineColumn.column;
          }
        }
      });

      if (tab == _currentTab && textChanged) {
        _handleAutocompleteTrigger(tab);
      }
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

  VbxSyntaxInfo? _findSyntaxForCurrentLine(EditorTab tab) {
    final text = tab.controller.text;
    final cursor = tab.controller.selection.baseOffset;

    if (cursor < 0 || cursor > text.length) {
      return null;
    }

    // Anfang der aktuellen Zeile
    final lineStart = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;

    // Text von Zeilenanfang bis Cursor
    final line = text.substring(lineStart, cursor);

    // ------------------------------------------------------------
    // 1. Modul-Funktion
    //
    // Beispiel:
    //   array.Create(
    //   json.Load(
    //   app.CurrentDirectory(
    // ------------------------------------------------------------

    final moduleMatch = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\($',
    ).firstMatch(line);

    if (moduleMatch != null) {
      final fullName = '${moduleMatch.group(1)}.${moduleMatch.group(2)}';

      return _syntaxService.findFullName(fullName);
    }

    // ------------------------------------------------------------
    // 2. Globale Funktion
    //
    // Beispiel:
    //   Split(
    //   Worker(
    //   ToLower(
    //
    // Diese werden intern als global.<funktion> gesucht.
    // ------------------------------------------------------------

    final globalMatch = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\($',
    ).firstMatch(line);

    if (globalMatch != null) {
      final functionName = globalMatch.group(1)!;

      return _syntaxService.findFullName(functionName);
    }

    return null;
  }

  EditorTab? get _currentTab {
    if (_tabs.isEmpty) {
      return null;
    }

    if (_activeTab >= _tabs.length) {
      return _tabs.last;
    }

    return _tabs[_activeTab];
  }

  bool get _currentTabHasContent {
    final tab = _currentTab;

    if (tab == null) {
      return false;
    }

    final text = tab.controller.text.trim();

    if (text.isEmpty) {
      return false;
    }

    if (text == kDefaultTabTemplate.trim()) {
      return false;
    }

    return true;
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
    final lower = path.toLowerCase();
    final isKnownExtension = FileService.allowedExtensions.any(
      (ext) => lower.endsWith('.$ext'),
    );

    if (!isKnownExtension) {
      setState(() {
        _runOutput = 'Dateityp wird nicht unterstützt: ${_fileName(path)}';
      });
      return;
    }

    final file = File(path);

    if (!await file.exists()) {
      return;
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

  String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
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

  @override
  void dispose() {
    _fileOpenSubscription?.cancel();
    widget.singleInstanceService.dispose();
    _searchController.dispose();

    for (final tab in _tabs) {
      tab.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'VBX Editor',
      theme: ThemeData(
        brightness: widget.configService.theme == 'dark'
            ? Brightness.dark
            : Brightness.light,
        useMaterial3: true,
      ),
      home: CallbackShortcuts(
        bindings: {
          LogicalKeySet(
            LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyS,
          ): () {
            _saveCurrentFile();
          },
          LogicalKeySet(
            LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyZ,
          ): () {
            _currentTab?.undoController.undo();
          },
          LogicalKeySet(
            LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyY,
          ): () {
            _currentTab?.undoController.redo();
          },
        },
        child: Scaffold(
          body: Builder(
            builder: (bodyContext) {
              _bodyContext = bodyContext;

              return Column(
                children: [
                  _buildToolbar(),
                  _buildTabs(),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: DropTarget(
                                  onDragDone: (details) {
                                    _handleDroppedFiles(details.files);
                                  },
                                  child: _buildEditor(),
                                ),
                              ),
                              _buildOutputPanel(),
                            ],
                          ),
                        ),
                        if (_docsVisible)
                          DocsPanel(
                            docsService: _docsService,
                            onClose: () {
                              setState(() {
                                _docsVisible = false;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                  _buildStatusBar(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final active = index == _activeTab;

                return Material(
                  color: active
                      ? widget.configService.theme == 'dark'
                            ? Colors.grey.shade900
                            : Colors.grey.shade300
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _activeTab = index;
                        _currentSyntaxInfo = _findSyntaxForCurrentLine(
                          _tabs[index],
                        );

                        final lineColumn = _lineColumnFor(_tabs[index]);
                        _currentLine = lineColumn.line;
                        _currentColumn = lineColumn.column;
                      });
                    },
                    child: Container(
                      width: 150,
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                          bottom: active
                              ? BorderSide(
                                  width: 2,
                                  color: widget.configService.theme == 'dark'
                                      ? Colors.white
                                      : Colors.black,
                                )
                              : BorderSide.none,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 4,
                              ),
                              child: Text(
                                tab.displayName,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            height: 40,
                            child: IconButton(
                              tooltip: 'Tab schließen',
                              padding: EdgeInsets.zero,
                              onPressed: () => _closeTab(index),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Colors.grey.shade800)),
            ),
            child: IconButton(
              tooltip: 'Neuer Tab',
              onPressed: _newTab,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Neue Datei',
            onPressed: _newTab,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Datei neu laden',
            onPressed: _currentTab?.filePath != null
                ? _reloadCurrentFile
                : null,
            icon: const Icon(Icons.restore),
          ),
          IconButton(
            tooltip: 'Datei öffnen',
            onPressed: _openFile,
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: 'Speichern',
            onPressed: _currentTabHasContent && (_currentTab?.modified ?? false)
                ? _saveCurrentFile
                : null,
            icon: const Icon(Icons.save),
          ),
          IconButton(
            tooltip: 'Speichern unter ...',
            onPressed: _currentTabHasContent ? _saveCurrentFileAs : null,
            icon: const Icon(Icons.save_as),
          ),
          const VerticalDivider(),
          IconButton(
            tooltip: 'Ausführen (F5)',
            onPressed:
                !_currentTabHasContent ||
                    !_currentTabIsExecutable ||
                    _isRunning ||
                    _isBuilding
                ? null
                : _runCurrentFile,
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Abbrechen',
            onPressed: (_isRunning || _isBuilding) ? _stopCurrentFile : null,
            icon: StopIcon(
              color: (_isRunning || _isBuilding)
                  ? (_isDarkTheme ? Colors.white : Colors.black87)
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Build',
            onPressed:
                !_currentTabHasContent ||
                    !_currentTabIsExecutable ||
                    _isBuilding ||
                    _isRunning
                ? null
                : _buildCurrentFile,
            icon: const Icon(Icons.build),
          ),
          IconButton(
            tooltip: 'Einstellungen',
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: _navigatorKey.currentContext!,
                builder: (context) =>
                    SettingsDialog(configService: widget.configService),
              );

              if (changed == true && mounted) {
                setState(() {
                  _fontSize = widget.configService.fontSize;
                });
              }
            },
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Auskommentieren',
            onPressed: _hasSelection ? _commentSelectedLines : null,
            icon: CommentIcon(
              uncomment: false,
              color: _hasSelection
                  ? (_isDarkTheme ? Colors.white : Colors.black87)
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Einkommentieren',
            onPressed: _hasSelection ? _uncommentSelectedLines : null,
            icon: CommentIcon(
              uncomment: true,
              color: _hasSelection
                  ? (_isDarkTheme ? Colors.white : Colors.black87)
                  : null,
            ),
          ),
          IconButton(
            tooltip: _panelVisible
                ? 'Panel ausblenden'
                : 'Ausgabe/Konsole einblenden',
            onPressed: () {
              setState(() {
                _panelVisible = !_panelVisible;
              });
            },
            icon: const Icon(Icons.terminal),
          ),
          IconButton(
            tooltip: 'Hilfe',
            onPressed: () {
              setState(() {
                _docsVisible = !_docsVisible;
              });
            },
            icon: const Icon(Icons.help_outline),
          ),

          const Spacer(),

          // ---------------------------------------------------------
          // Suche
          // ---------------------------------------------------------
          if (_searchVisible) ...[
            SizedBox(
              width: 250,
              height: 38,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Suchen ...',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Suche schließen',
                    onPressed: _closeSearch,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
                onChanged: (_) {
                  setState(() {
                    _updateSearchMatches();
                  });
                },
                onSubmitted: (_) => _findNext(),
              ),
            ),

            IconButton(
              tooltip: 'Vorheriger Treffer',
              onPressed: _findPrevious,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),

            IconButton(
              tooltip: 'Nächster Treffer',
              onPressed: _findNext,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],

          IconButton(
            tooltip: _searchVisible ? 'Suche schließen' : 'Suchen',
            onPressed: _searchVisible ? _closeSearch : _openSearch,
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final tab = _currentTab;

    if (tab == null) {
      return const SizedBox();
    }

    final lineCount = '\n'.allMatches(tab.controller.text).length + 1;

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLineNumbers(tab, lineCount),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }

                      // ------------------------------------------------------------
                      // Suche
                      // ------------------------------------------------------------

                      if (_searchVisible) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _findNext();
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _findPrevious();
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.enter) {
                          _findNext();
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          _closeSearch();
                          return KeyEventResult.handled;
                        }
                      }

                      // ------------------------------------------------------------
                      // Autocomplete
                      // ------------------------------------------------------------

                      if (!_autocomplete.isVisible) {
                        return KeyEventResult.ignored;
                      }

                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        _autocomplete.moveSelection(1);
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _autocomplete.moveSelection(-1);
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.tab) {
                        _autocomplete.confirmSelection();
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        _autocomplete.hide();
                        return KeyEventResult.handled;
                      }

                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: tab.controller,
                      scrollController: tab.scrollController,
                      focusNode: tab.focusNode,
                      undoController: tab.undoController,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: _fontSize,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        _buildSyntaxHint(),
      ],
    );
  }

  Widget _buildLineNumbers(EditorTab tab, int lineCount) {
    final isDark = _isDarkTheme;

    return Container(
      width: 44,
      padding: const EdgeInsets.only(top: 12, right: 6),
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
      child: ClipRect(
        child: SingleChildScrollView(
          controller: tab.gutterScrollController,
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(lineCount, (i) {
              return Text(
                '${i + 1}',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: _fontSize,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildSyntaxHint() {
    final info = _currentSyntaxInfo;

    if (info == null) {
      return const SizedBox.shrink();
    }

    final isDark = _isDarkTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            info.syntax,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontFamily: 'Consolas',
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              info.description,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black54,
                fontFamily: 'Consolas',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final isDark = _isDarkTheme;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
      child: Row(
        children: [
          Text(
            'VBX',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _vbxVersion,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          const Spacer(),
          Text(
            'Zeile $_currentLine, Spalte $_currentColumn',
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputPanelHeader() {
    final isDark = _isDarkTheme;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () {
              setState(() {
                _outputPanel = 0;
              });
            },
            child: const Text('Ausgabe'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _outputPanel = 1;
                _panelVisible = true;
              });
            },
            child: const Text('Konsole'),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Panel ausblenden',
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _panelVisible = false;
              });
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputPanel() {
    if (!_panelVisible) {
      return const SizedBox.shrink();
    }

    final isDark = _isDarkTheme;

    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.grey.shade100,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildOutputPanelHeader(),
          Expanded(
            child: Stack(
              children: [
                Offstage(
                  offstage: _outputPanel != 0,
                  child: _buildRunOutputContent(),
                ),
                Offstage(
                  offstage: _outputPanel != 1,
                  child: _buildConsoleContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleContent() {
    return VbxConsole(isDark: _isDarkTheme, fontSize: _fontSize);
  }

  Widget _buildRunOutputContent() {
    final isDark = _isDarkTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onSecondaryTapUp: (_) {
            final selection = _runOutputSelection;

            if (selection == null || selection.isCollapsed) {
              return;
            }

            final start = selection.start.clamp(0, _runOutput.length);
            final end = selection.end.clamp(0, _runOutput.length);

            final text = _runOutput.substring(
              start < end ? start : end,
              start < end ? end : start,
            );

            if (text.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: text));
            }
          },
          child: SelectableText(
            _runOutput,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: _fontSize,
              color: isDark ? Colors.white : Colors.black,
            ),
            onSelectionChanged: (selection, cause) {
              _runOutputSelection = selection;
            },
          ),
        ),
      ),
    );
  }
}
