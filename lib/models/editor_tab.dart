import 'package:flutter/material.dart';

import '../services/highlight_service.dart';
import '../widgets/vbx_text_controller.dart';

class EditorTab {
  String name;
  String? filePath;

  final VbxTextEditingController controller;
  final FocusNode focusNode = FocusNode();

  // Für die Zeilennummern-Anzeige: Der Editor-Scroll-Controller treibt
  // den Gutter-Scroll-Controller synchron mit.
  final ScrollController scrollController = ScrollController();
  final ScrollController gutterScrollController = ScrollController();

  bool modified = false;

  EditorTab({
    required this.name,
    this.filePath,
    String content = '',
    VbxHighlightConfig? highlightConfig,
  }) : controller = VbxTextEditingController(
         text: content,
         config: highlightConfig,
       ) {
    scrollController.addListener(_syncGutterScroll);
  }

  void _syncGutterScroll() {
    if (!gutterScrollController.hasClients) {
      return;
    }

    final maxExtent = gutterScrollController.position.maxScrollExtent;
    final target = scrollController.offset.clamp(0.0, maxExtent);

    gutterScrollController.jumpTo(target);
  }

  String get displayName {
    return modified ? '$name *' : name;
  }

  void setHighlightConfig(VbxHighlightConfig? config) {
    controller.config = config;

    // Neu zeichnen, damit das Highlighting sofort aktualisiert wird.
    controller.notifyListeners();
  }

  void setContent(String content) {
    controller.text = content;
    modified = false;
  }

  void markSaved() {
    modified = false;
  }

  void markModified() {
    modified = true;
  }

  void dispose() {
    focusNode.dispose();
    scrollController.removeListener(_syncGutterScroll);
    scrollController.dispose();
    gutterScrollController.dispose();
    controller.dispose();
  }
}
