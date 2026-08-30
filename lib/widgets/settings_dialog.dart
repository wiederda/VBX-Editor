import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/config_service.dart';
import '../services/file_association_service.dart';
import '../services/update_service.dart';
import '../services/version_service.dart';

class SettingsDialog extends StatefulWidget {
  final ConfigService configService;

  const SettingsDialog({super.key, required this.configService});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final VbxFileAssociationService _fileAssociationService =
      VbxFileAssociationService();
  final VbxUpdateService _updateService = VbxUpdateService();

  late String _theme;
  late final TextEditingController _pathController;
  late bool _fileAssociationEnabled;
  late double _fontSize;

  bool _saving = false;
  String? _error;

  bool _checkingUpdate = false;
  String? _updateStatus;
  VbxUpdateCheckResult? _pendingUpdate;

  static const List<double> _fontSizeOptions = [10, 12, 13, 14, 16, 18, 20, 24];

  @override
  void initState() {
    super.initState();
    _theme = widget.configService.theme;
    _pathController = TextEditingController(
      text: widget.configService.vbxExecutable,
    );
    _fileAssociationEnabled = widget.configService.fileAssociationEnabled;
    _fontSize = widget.configService.fontSize;
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

  Future<void> _checkForUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateStatus = null;
      _pendingUpdate = null;
    });

    try {
      final executable = _pathController.text.trim();

      final versionService = VbxVersionService(executable: executable);
      final currentVersion = await versionService.getVersion();

      final result = await _updateService.checkForUpdate(currentVersion);

      if (!mounted) {
        return;
      }

      setState(() {
        _checkingUpdate = false;

        if (result.isNewer) {
          _pendingUpdate = result;
          _updateStatus =
              'Update verfügbar: ${result.latestVersion} (aktuell: ${currentVersion ?? "unbekannt"})';
        } else {
          _updateStatus = 'VBX ist bereits aktuell (${result.latestVersion}).';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _checkingUpdate = false;
        _updateStatus = 'Update-Prüfung fehlgeschlagen: $e';
      });
    }
  }

  Future<void> _installUpdate() async {
    final update = _pendingUpdate;

    if (update == null) {
      return;
    }

    setState(() {
      _checkingUpdate = true;
      _updateStatus = 'Installiere ${update.latestVersion} ...';
    });

    try {
      await _updateService.downloadAndInstall(
        downloadUrl: update.downloadUrl,
        targetPath: _pathController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _checkingUpdate = false;
        _pendingUpdate = null;
        _updateStatus = 'VBX wurde auf ${update.latestVersion} aktualisiert.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _checkingUpdate = false;
        _updateStatus = 'Installation fehlgeschlagen: $e';
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
      await widget.configService.setFontSize(_fontSize);

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
            const Text('Schriftgröße (Editor)'),
            const SizedBox(height: 4),
            DropdownButton<double>(
              value: _fontSize,
              isExpanded: true,
              items: _fontSizeOptions
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text('${s.toInt()}px'),
                    ),
                  )
                  .toList(),
              onChanged: (size) {
                if (size == null) {
                  return;
                }

                setState(() {
                  _fontSize = size;
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
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _checkingUpdate ? null : _checkForUpdate,
                  icon: _checkingUpdate
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update, size: 16),
                  label: const Text('Nach Update suchen'),
                ),
                if (_pendingUpdate != null) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _checkingUpdate ? null : _installUpdate,
                    child: const Text('Installieren'),
                  ),
                ],
              ],
            ),
            if (_updateStatus != null) ...[
              const SizedBox(height: 6),
              Text(_updateStatus!, style: const TextStyle(fontSize: 12)),
            ],
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
