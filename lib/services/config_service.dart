import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

class ConfigService {
  Map<String, dynamic> _config = {};

  late final File _configFile;

  String get vbxcExecutable =>
      _config['vbxcExecutable']?.toString() ?? _defaultVbxcExecutable;

  String get _defaultVbxcExecutable => Platform.isWindows ? 'vbxc.exe' : 'vbxc';

  Future<void> setVbxcExecutable(String path) async {
    _config['vbxcExecutable'] = path;
    await _save();
  }

  bool get fileAssociationEnabled {
    return _config['fileAssociationEnabled'] == true;
  }

  Future<void> setFileAssociationEnabled(bool value) async {
    _config['fileAssociationEnabled'] = value;
    await _save();
  }

  Future<void> initialize() async {
    final configDir = VbxAppPaths.configDirectory;

    await configDir.create(recursive: true);

    _configFile = File('${configDir.path}${Platform.pathSeparator}config.json');

    if (await _configFile.exists()) {
      await _load();

      var configChanged = false;
      if (_config.remove('vbx') != null) {
        configChanged = true;
      }
      if (_config.remove('buildTarget') != null) {
        configChanged = true;
      }
      if (_config['vbxcExecutable'] == null) {
        _config['vbxcExecutable'] = _defaultVbxcExecutable;
        configChanged = true;
      }
      if (!Platform.isWindows && _config['vbxcExecutable'] == 'vbxc.exe') {
        _config['vbxcExecutable'] = _defaultVbxcExecutable;
        configChanged = true;
      }
      if (configChanged) await _save();

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
    _config = {'theme': 'white', 'vbxcExecutable': _defaultVbxcExecutable};

    await _save();
  }

  Future<void> _save() async {
    const encoder = JsonEncoder.withIndent('  ');

    await _configFile.writeAsString(encoder.convert(_config));
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
