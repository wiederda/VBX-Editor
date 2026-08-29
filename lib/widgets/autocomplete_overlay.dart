import 'package:flutter/material.dart';

import '../services/syntax_service.dart';

const double _kItemExtent = 26.0;
const double _kMaxListHeight = 220.0;

/// Verwaltet ein Overlay mit einer Autovervollständigungs-Liste,
/// angelehnt an Visual Studio IntelliSense.
class AutocompleteController {
  OverlayEntry? _entry;
  final ScrollController scrollController = ScrollController();

  List<VbxSyntaxInfo> suggestions = [];
  int selectedIndex = 0;

  /// Wird aufgerufen, wenn der Nutzer einen Vorschlag übernimmt
  /// (Enter/Tab/Doppelklick).
  void Function(VbxSyntaxInfo suggestion)? onSelect;

  bool get isVisible => _entry != null;

  void show({
    required BuildContext context,
    required Offset position,
    required List<VbxSyntaxInfo> suggestions,
    required void Function(VbxSyntaxInfo suggestion) onSelect,
  }) {
    this.suggestions = suggestions;
    this.onSelect = onSelect;
    selectedIndex = 0;

    hide();

    if (suggestions.isEmpty) {
      return;
    }

    final overlay = Overlay.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: position.dx,
          top: position.dy,
          child: _AutocompleteList(controller: this, isDark: isDark),
        );
      },
    );

    overlay.insert(_entry!);
  }

  /// Aktualisiert die Vorschlagsliste eines bereits sichtbaren Overlays
  /// (z. B. wenn der Nutzer weitertippt), ohne Position neu zu berechnen.
  void update(List<VbxSyntaxInfo> newSuggestions) {
    suggestions = newSuggestions;
    selectedIndex = 0;

    if (suggestions.isEmpty) {
      hide();
      return;
    }

    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }

    _entry?.markNeedsBuild();
  }

  void moveSelection(int delta) {
    if (suggestions.isEmpty) {
      return;
    }

    selectedIndex = (selectedIndex + delta) % suggestions.length;

    if (selectedIndex < 0) {
      selectedIndex += suggestions.length;
    }

    _scrollToSelected();

    _entry?.markNeedsBuild();
  }

  void _scrollToSelected() {
    if (!scrollController.hasClients) {
      return;
    }

    final itemTop = selectedIndex * _kItemExtent;
    final itemBottom = itemTop + _kItemExtent;

    final viewportHeight = scrollController.position.viewportDimension;
    final currentOffset = scrollController.offset;

    if (itemTop < currentOffset) {
      scrollController.jumpTo(itemTop);
    } else if (itemBottom > currentOffset + viewportHeight) {
      scrollController.jumpTo(itemBottom - viewportHeight);
    }
  }

  void confirmSelection() {
    if (suggestions.isEmpty) {
      return;
    }

    onSelect?.call(suggestions[selectedIndex]);
    hide();
  }

  void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _AutocompleteList extends StatefulWidget {
  final AutocompleteController controller;
  final bool isDark;

  const _AutocompleteList({required this.controller, required this.isDark});

  @override
  State<_AutocompleteList> createState() => _AutocompleteListState();
}

class _AutocompleteListState extends State<_AutocompleteList> {
  @override
  Widget build(BuildContext context) {
    final suggestions = widget.controller.suggestions;
    final selectedIndex = widget.controller.selectedIndex;
    final isDark = widget.isDark;

    final listHeight = (suggestions.length * _kItemExtent).clamp(
      0.0,
      _kMaxListHeight,
    );

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      color: isDark ? const Color(0xFF252526) : Colors.white,
      child: Container(
        width: 340,
        height: listHeight,
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ListView.builder(
          controller: widget.controller.scrollController,
          padding: EdgeInsets.zero,
          itemExtent: _kItemExtent,
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final info = suggestions[index];
            final selected = index == selectedIndex;

            return InkWell(
              onTap: () {
                widget.controller.selectedIndex = index;
                widget.controller.confirmSelection();
              },
              child: Container(
                color: selected
                    ? (isDark ? Colors.blue.shade900 : Colors.blue.shade100)
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(
                      Icons.functions,
                      size: 14,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        info.name,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
