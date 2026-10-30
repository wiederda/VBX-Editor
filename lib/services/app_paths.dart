import 'dart:io';

/// Resolves the per-user directories used by VBX Editor on each platform.
class VbxAppPaths {
  static const String _appName = 'VBX Editor';
  static const String _linuxAppName = 'vbx-editor';

  static Directory get configDirectory {
    if (Platform.isWindows) {
      return Directory(_join([_requiredEnvironment('APPDATA'), _appName]));
    }

    if (Platform.isLinux) {
      final base = _xdgDirectory('XDG_CONFIG_HOME', '.config');
      return Directory('${base.path}$_separator$_linuxAppName');
    }

    if (Platform.isMacOS) {
      return Directory(
        _join([
          _requiredEnvironment('HOME'),
          'Library',
          'Application Support',
          _appName,
        ]),
      );
    }

    throw UnsupportedError('Dieses Betriebssystem wird nicht unterstützt.');
  }

  static Directory get docsCacheDirectory {
    if (Platform.isWindows) {
      return Directory(
        _join([_requiredEnvironment('APPDATA'), _appName, 'docs_cache']),
      );
    }

    if (Platform.isLinux) {
      final base = _xdgDirectory('XDG_CACHE_HOME', '.cache');
      return Directory('${base.path}$_separator$_linuxAppName');
    }

    if (Platform.isMacOS) {
      return Directory(
        _join([_requiredEnvironment('HOME'), 'Library', 'Caches', _appName]),
      );
    }

    throw UnsupportedError('Dieses Betriebssystem wird nicht unterstützt.');
  }

  static Directory _xdgDirectory(String variable, String homeFallback) {
    final configured = Platform.environment[variable];
    if (configured != null &&
        configured.isNotEmpty &&
        configured.startsWith(_separator)) {
      return Directory(configured);
    }

    return Directory('${_requiredEnvironment('HOME')}$_separator$homeFallback');
  }

  static String _requiredEnvironment(String name) {
    final value = Platform.environment[name];
    if (value == null || value.isEmpty) {
      throw StateError('$name konnte nicht ermittelt werden.');
    }
    return value;
  }

  static String get _separator => Platform.pathSeparator;

  static String _join(List<String> segments) => segments.join(_separator);
}
