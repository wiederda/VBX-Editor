import 'dart:convert';
import 'dart:io';

class ConfigService {
  Map<String, dynamic> _config = {};

  late final File _configFile;

  bool get fileAssociationEnabled {
    return _config['fileAssociationEnabled'] == true;
  }

  Future<void> setFileAssociationEnabled(bool value) async {
    _config['fileAssociationEnabled'] = value;
    await _save();
  }

  Future<void> initialize() async {
    final appData = Platform.environment['APPDATA'];

    if (appData == null || appData.isEmpty) {
      throw Exception('APPDATA konnte nicht ermittelt werden.');
    }

    final configDir = Directory('$appData${Platform.pathSeparator}VBX Editor');

    await configDir.create(recursive: true);

    _configFile = File('${configDir.path}${Platform.pathSeparator}config.json');

    if (await _configFile.exists()) {
      await _load();

      // Gespeicherten VBX-Pfad prüfen.
      final executable = vbxExecutable;

      if (!await File(executable).exists()) {
        final found = await _findVbxExecutable();

        if (found != null) {
          _setVbxExecutable(found);
          await _save();
        }
      }

      return;
    }

    await _createDefaultConfig();
  }

  Future<void> _load() async {
    try {
      final text = await _configFile.readAsString();

      final decoded = jsonDecode(text);

      if (decoded is Map<String, dynamic>) {
        _config = decoded;
        return;
      }

      await _createDefaultConfig();
    } catch (_) {
      await _createDefaultConfig();
    }
  }

  Future<void> _createDefaultConfig() async {
    final vbx = await _findVbxExecutable();

    _config = {
      'theme': 'white',
      'vbx': {'executable': vbx ?? 'vbx.exe'},
    };

    await _save();
  }

  Future<void> _save() async {
    const encoder = JsonEncoder.withIndent('  ');

    await _configFile.writeAsString(encoder.convert(_config));
  }

  Future<String?> _findVbxExecutable() async {
    // ------------------------------------------------------------
    // 1. VBX neben dem Editor
    // ------------------------------------------------------------

    final localVbx = File(
      '${Directory.current.path}${Platform.pathSeparator}vbx.exe',
    );

    if (await localVbx.exists()) {
      return localVbx.absolute.path;
    }

    // ------------------------------------------------------------
    // 2. VBX über PATH
    // ------------------------------------------------------------

    try {
      final result = await Process.run('where', ['vbx.exe'], runInShell: true);

      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();

        if (output.isNotEmpty) {
          final lines = output
              .split(RegExp(r'\r?\n'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty);

          for (final path in lines) {
            final file = File(path);

            if (await file.exists()) {
              return file.absolute.path;
            }
          }
        }
      }
    } catch (_) {
      // Suche über PATH fehlgeschlagen.
    }

    return null;
  }

  void _setVbxExecutable(String path) {
    final vbx = _config['vbx'];

    if (vbx is Map<String, dynamic>) {
      vbx['executable'] = path;
      return;
    }

    _config['vbx'] = {'executable': path};
  }

  String get theme {
    return _config['theme']?.toString() ?? 'white';
  }

  Future<void> setTheme(String theme) async {
    if (theme != 'dark' && theme != 'white') {
      return;
    }

    _config['theme'] = theme;

    await _save();
  }

  Future<void> setVbxExecutable(String path) async {
    _setVbxExecutable(path);

    await _save();
  }

  String get vbxExecutable {
    final vbx = _config['vbx'];

    if (vbx is Map) {
      return vbx['executable']?.toString() ?? 'vbx.exe';
    }

    return 'vbx.exe';
  }

  double get fontSize {
    final value = _config['fontSize'];

    if (value is num) {
      return value.toDouble();
    }

    return 14.0;
  }

  Future<void> setFontSize(double fontSize) async {
    if (fontSize < 8 || fontSize > 32) {
      return;
    }

    _config['fontSize'] = fontSize;

    await _save();
  }
}
