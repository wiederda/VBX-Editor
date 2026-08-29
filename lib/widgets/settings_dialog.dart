import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/config_service.dart';
import '../services/file_association_service.dart';

class SettingsDialog extends StatefulWidget {
  final ConfigService configService;

  const SettingsDialog({super.key, required this.configService});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final VbxFileAssociationService _fileAssociationService =
      VbxFileAssociationService();

  late String _theme;
  late final TextEditingController _pathController;
  late bool _fileAssociationEnabled;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _theme = widget.configService.theme;
    _pathController = TextEditingController(
      text: widget.configService.vbxExecutable,
    );
    _fileAssociationEnabled = widget.configService.fileAssociationEnabled;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
    );

    final path = result?.files.single.path;

    if (path != null) {
      setState(() {
        _pathController.text = path;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.configService.setTheme(_theme);
      await widget.configService.setVbxExecutable(_pathController.text.trim());

      final wasEnabled = widget.configService.fileAssociationEnabled;

      if (_fileAssociationEnabled != wasEnabled) {
        if (_fileAssociationEnabled) {
          await _fileAssociationService.register();
        } else {
          await _fileAssociationService.unregister();
        }

        await widget.configService.setFileAssociationEnabled(
          _fileAssociationEnabled,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Explorer-Integration konnte nicht geändert werden: $e';
        });
      }
      return;
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Einstellungen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Theme'),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dark', label: Text('Dunkel')),
                ButtonSegment(value: 'white', label: Text('Hell')),
              ],
              selected: {_theme},
              onSelectionChanged: (selection) {
                setState(() {
                  _theme = selection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('VBX-Executable'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Durchsuchen',
                  onPressed: _browse,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _fileAssociationEnabled,
              title: const Text('Im Explorer-Kontextmenü registrieren'),
              subtitle: const Text(
                '"Öffnen mit VBX Editor" für unterstützte Dateitypen '
                '(.vb, .txt, .json, .ini, .csv, ...) anbieten.',
              ),
              onChanged: (value) {
                setState(() {
                  _fileAssociationEnabled = value ?? false;
                });
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Speichern'),
        ),
      ],
    );
  }
}
