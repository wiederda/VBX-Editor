import 'dart:io';

/// Registriert VBX Editor im Windows-Explorer-Kontextmenü ("Öffnen mit"),
/// ohne Adminrechte zu benötigen (nur HKEY_CURRENT_USER).
///
/// Setzt NICHT den Standard-Öffnen-Modus für irgendeine Dateiendung --
/// registriert nur zusätzlich als wählbare Anwendung ("Öffnen mit"-Liste),
/// analog zu Notepad++.
class VbxFileAssociationService {
  static const String _appKeyName = 'vbx_editor.exe';

  static const List<String> extensions = [
    'vb',
    'txt',
    'json',
    'ini',
    'csv',
    'xml',
    'yaml',
    'yml',
    'log',
    'cfg',
    'env',
  ];

  Future<bool> isRegistered() async {
    final result = await Process.run('reg', [
      'query',
      'HKCU\\Software\\Classes\\Applications\\$_appKeyName\\shell\\open\\command',
    ], runInShell: true);

    return result.exitCode == 0;
  }

  Future<void> register() async {
    final exePath = Platform.resolvedExecutable;
    final commandValue = '"$exePath" "%1"';

    await _regAdd(
      'HKCU\\Software\\Classes\\Applications\\$_appKeyName',
      'FriendlyAppName',
      'VBX Editor',
    );

    await _regAdd(
      'HKCU\\Software\\Classes\\Applications\\$_appKeyName\\shell\\open\\command',
      null,
      commandValue,
    );

    for (final ext in extensions) {
      await _regAdd(
        'HKCU\\Software\\Classes\\Applications\\$_appKeyName\\SupportedTypes',
        '.$ext',
        '',
      );
    }
  }

  Future<void> unregister() async {
    await Process.run('reg', [
      'delete',
      'HKCU\\Software\\Classes\\Applications\\$_appKeyName',
      '/f',
    ], runInShell: true);
  }

  Future<void> _regAdd(String keyPath, String? valueName, String data) async {
    final args = <String>['add', keyPath];

    if (valueName != null) {
      args.addAll(['/v', valueName]);
    } else {
      args.add('/ve');
    }

    args.addAll(['/d', data, '/f']);

    await Process.run('reg', args, runInShell: true);
  }
}
