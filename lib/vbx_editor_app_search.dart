part of 'vbx_editor_app.dart';

extension _VbxEditorAppSearch on _VbxEditorAppState {
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
}
