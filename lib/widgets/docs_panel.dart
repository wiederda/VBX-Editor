import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/docs_service.dart';

class DocsPanel extends StatefulWidget {
  final VbxDocsService docsService;
  final VoidCallback onClose;

  const DocsPanel({
    super.key,
    required this.docsService,
    required this.onClose,
  });

  @override
  State<DocsPanel> createState() => _DocsPanelState();
}

class _DocsPanelState extends State<DocsPanel> {
  String? _selectedFile;
  bool _refreshing = false;
  String? _error;

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });

    try {
      await widget.docsService.refreshFromGitHub();
    } catch (e) {
      _error = 'Aktualisierung fehlgeschlagen: $e';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.docsService.entries;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 480,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
        border: Border(
          left: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Text(
                  'Hilfe',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Docs aktualisieren (GitHub)',
                  onPressed: _refreshing ? null : _refresh,
                  icon: _refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),

          Expanded(
            child: _selectedFile == null
                ? _buildList(entries)
                : _buildDetail(_selectedFile!),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<VbxDocEntry> entries) {
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Keine Docs im Cache.\nÜber das Aktualisieren-Symbol von GitHub laden.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];

        return ListTile(
          dense: true,
          title: Text(entry.moduleName),
          onTap: () {
            setState(() {
              _selectedFile = entry.fileName;
            });
          },
        );
      },
    );
  }

  Widget _buildDetail(String fileName) {
    final content = widget.docsService.contentFor(fileName) ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Zurück',
                onPressed: () {
                  setState(() {
                    _selectedFile = null;
                  });
                },
                icon: const Icon(Icons.arrow_back, size: 18),
              ),
              Text(
                fileName.replaceAll('.md', ''),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SelectionArea(
            child: Markdown(
              data: content,
              padding: const EdgeInsets.all(8),
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 13, height: 1.4, color: baseColor),
                h1: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: baseColor,
                ),
                h2: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: baseColor,
                ),
                h3: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: baseColor,
                ),
                code: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  backgroundColor: isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade300,
                  color: baseColor,
                ),
                codeblockDecoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                listBullet: TextStyle(fontSize: 13, color: baseColor),
                strong: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: baseColor,
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isDark
                          ? Colors.grey.shade600
                          : Colors.grey.shade400,
                      width: 3,
                    ),
                  ),
                ),
                h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
                h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
                h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
                pPadding: const EdgeInsets.only(bottom: 6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
