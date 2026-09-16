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
import 'widgets/dryrun_icons.dart';
import 'widgets/syntax_hint_overlay.dart';

part 'vbx_editor_app_session.dart';
part 'vbx_editor_app_files.dart';
part 'vbx_editor_app_run.dart';
part 'vbx_editor_app_search.dart';
part 'vbx_editor_app_editing.dart';
part 'vbx_editor_app_autocomplete.dart';
part 'vbx_editor_app_syntax_hint.dart';
part 'vbx_editor_app_ui.dart';

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

  final SyntaxHintController _syntaxHint = SyntaxHintController();

  // Referenz auf die Render-Box des Editor-TextFields. Wird genutzt,
  // um die Syntax-Hint-Position von der ECHTEN Bildschirmposition des
  // Feldes abzuleiten, statt sie aus geschätzten Konstanten
  // (Toolbar-/Tab-Höhe, Gutter-Breite, ...) zusammenzurechnen -- diese
  // Schätzungen drifteten in der Praxis ab und ließen den Tooltip die
  // gerade bearbeitete Zeile verdecken.
  final GlobalKey _editorFieldKey = GlobalKey();

  TextSelection? _runOutputSelection;

  bool _docsVisible = false;
  double _fontSize = 14.0;

  BuildContext? _bodyContext;

  int _activeTab = 0;
  int _untitledCounter = 0;

  int _currentLine = 1;
  int _currentColumn = 1;

  int _outputPanel = 0;

  int? _activeOpenParenIndex;
  int? _dismissedParenIndex;

  int _currentParamIndex = 0;

  String _runOutput = '';

  bool _isRunning = false;
  bool _isBuilding = false;
  bool _panelVisible = false;
  bool _isDryRunning = false;

  // Verhindert, dass der Close-Vorgang mehrfach gestartet wird.
  bool _isClosing = false;

  StreamSubscription<String>? _fileOpenSubscription;

  String _vbxVersion = 'Version wird ermittelt ...';

  bool _searchVisible = false;

  final TextEditingController _searchController = TextEditingController();

  int _searchMatchIndex = -1;

  List<int> _searchMatches = [];

  VbxSyntaxInfo? _currentSyntaxInfo;

  bool get _isDarkTheme => widget.configService.theme == 'dark';

  @override
  void initState() {
    super.initState();

    windowManager.addListener(this);
    _initWindow();

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

  Future<void> _initWindow() async {
    await windowManager.setPreventClose(true);
  }

  bool get _currentTabIsExecutable {
    final tab = _currentTab;

    if (tab == null) {
      return false;
    }

    // Ein noch nicht gespeicherter Tab (kein Pfad) gilt als VBX,
    // da er standardmäßig als .vb gespeichert wird.
    if (tab.filePath == null) {
      return true;
    }

    return FileService.isExecutable(tab.filePath);
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

  String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  String _newUntitledName() {
    _untitledCounter++;

    return 'Unbenannt-${_untitledCounter}.vb';
  }

  @override
  void onWindowClose() async {
    debugPrint('WINDOW CLOSE EVENT');

    if (_isClosing) {
      return;
    }

    _isClosing = true;

    // Fenster sofort ausblenden.
    await windowManager.hide();

    // Session speichern.
    await _saveSession();

    // Anwendung endgültig beenden.
    await windowManager.destroy();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);

    _syntaxHint.hide();

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
}
