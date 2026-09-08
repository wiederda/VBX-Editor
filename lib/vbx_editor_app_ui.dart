part of 'vbx_editor_app.dart';

extension _VbxEditorAppUi on _VbxEditorAppState {
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

                        final result = _findSyntaxAndParamForCursor(
                          _tabs[index],
                        );
                        _currentSyntaxInfo = result?.info;
                        _currentParamIndex = result?.paramIndex ?? 0;

                        final lineColumn = _lineColumnFor(_tabs[index]);
                        _currentLine = lineColumn.line;
                        _currentColumn = lineColumn.column;

                        if (result != null) {
                          _updateSyntaxHintOverlay(
                            _tabs[index],
                            result.info,
                            result.paramIndex,
                            _tabs[index].controller.text,
                            result.openParenIndex,
                          );
                        } else {
                          _syntaxHint.hide();
                        }
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
                    _isBuilding ||
                    _isDryRunning
                ? null
                : _runCurrentFile,
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Abbrechen',
            onPressed: (_isRunning || _isBuilding || _isDryRunning)
                ? _stopCurrentFile
                : null,
            icon: StopIcon(
              color: (_isRunning || _isBuilding || _isDryRunning)
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
                    _isRunning ||
                    _isDryRunning
                ? null
                : _buildCurrentFile,
            icon: const Icon(Icons.build),
          ),
          IconButton(
            tooltip: 'Dry Run (nur prüfen, nicht ausführen)',
            onPressed:
                !_currentTabHasContent ||
                    !_currentTabIsExecutable ||
                    _isRunning ||
                    _isBuilding ||
                    _isDryRunning
                ? null
                : _dryRunCurrentFile,
            icon: DryRunIcon(
              color:
                  (!_currentTabHasContent ||
                      !_currentTabIsExecutable ||
                      _isRunning ||
                      _isBuilding ||
                      _isDryRunning)
                  ? null
                  : (_isDarkTheme ? Colors.white : Colors.black87),
            ),
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
                      // Escape: Autocomplete und Syntax-Hint schließen.
                      // ------------------------------------------------------------

                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        var handled = false;

                        if (_autocomplete.isVisible) {
                          _autocomplete.hide();
                          handled = true;
                        }

                        if (_syntaxHint.isVisible) {
                          _dismissedParenIndex = _activeOpenParenIndex;
                          _syntaxHint.hide();
                          handled = true;
                        }

                        if (handled) {
                          return KeyEventResult.handled;
                        }
                      }

                      // ------------------------------------------------------------
                      // Enter: Bei offenem Autocomplete Auswahl bestätigen (wie bisher).
                      // Andernfalls Syntax-Hint schließen, Zeilenumbruch aber normal
                      // einfügen lassen.
                      // ------------------------------------------------------------

                      if (event.logicalKey == LogicalKeyboardKey.enter) {
                        if (_autocomplete.isVisible) {
                          _autocomplete.confirmSelection();
                          return KeyEventResult.handled;
                        }

                        if (_syntaxHint.isVisible) {
                          _dismissedParenIndex = _activeOpenParenIndex;
                          _syntaxHint.hide();
                        }

                        return KeyEventResult.ignored;
                      }

                      // ------------------------------------------------------------
                      // Autocomplete (Pfeiltasten/Tab)
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

                      if (event.logicalKey == LogicalKeyboardKey.tab) {
                        _autocomplete.confirmSelection();
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
