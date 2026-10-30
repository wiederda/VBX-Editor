import 'dart:io';

import 'package:flutter/material.dart';

import '../services/file_service.dart';
import 'project_icons.dart';

class ProjectExplorer extends StatefulWidget {
  final String rootPath;
  final bool isDark;
  final ValueChanged<String> onFileSelected;
  final VoidCallback onClose;

  const ProjectExplorer({
    super.key,
    required this.rootPath,
    required this.isDark,
    required this.onFileSelected,
    required this.onClose,
  });

  @override
  State<ProjectExplorer> createState() => _ProjectExplorerState();
}

class _ProjectExplorerState extends State<ProjectExplorer> {
  final Map<String, Future<List<FileSystemEntity>>> _children = {};

  Future<List<FileSystemEntity>> _list(String path) => _children.putIfAbsent(
    path,
    () async {
      final listedEntries = await Directory(path)
          .list(followLinks: false)
          .toList();
      final entries = listedEntries.where((entry) {
        if (entry is Directory) return true;
        final lowerPath = entry.path.toLowerCase();
        return FileService.allowedExtensions.any(
          (extension) => lowerPath.endsWith('.$extension'),
        );
      }).toList();
      entries.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return _name(a.path).toLowerCase().compareTo(_name(b.path).toLowerCase());
      });
      return entries;
    },
  );

  String _name(String path) {
    final normalized = path.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
    return normalized.split('/').last;
  }

  @override
  void didUpdateWidget(covariant ProjectExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) _children.clear();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 38,
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('EXPLORER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Projektstruktur schließen',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  key: PageStorageKey(widget.rootPath),
                  initiallyExpanded: true,
                  tilePadding: const EdgeInsets.only(left: 8, right: 4),
                  childrenPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    _name(widget.rootPath).toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  children: [
                    FutureBuilder<List<FileSystemEntity>>(
                      future: _list(widget.rootPath),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const ListTile(dense: true, title: Text('Ordner kann nicht gelesen werden'));
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: LinearProgressIndicator(minHeight: 2),
                          );
                        }
                        return Column(
                          children: snapshot.data!
                              .map((entry) => _buildEntry(entry, 0))
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(FileSystemEntity entry, int depth) {
    final name = _name(entry.path);
    if (entry is Directory) {
      return ExpansionTile(
        key: PageStorageKey(entry.path),
        tilePadding: EdgeInsets.only(left: 8.0 + depth * 12, right: 4),
        childrenPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        dense: true,
        leading: const ExplorerFolderIcon(),
        title: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        children: [
          FutureBuilder<List<FileSystemEntity>>(
            future: _list(entry.path),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ListTile(dense: true, title: Text('Ordner kann nicht gelesen werden'));
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              return Column(
                children: snapshot.data!
                    .map((child) => _buildEntry(child, depth + 1))
                    .toList(),
              );
            },
          ),
        ],
      );
    }

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.only(left: 12.0 + depth * 12, right: 8),
      leading: const ExplorerFileIcon(),
      title: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
      onTap: () => widget.onFileSelected(entry.path),
    );
  }
}
