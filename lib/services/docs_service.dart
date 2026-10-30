import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_paths.dart';

class VbxDocEntry {
  final String fileName;
  final String moduleName;

  VbxDocEntry({required this.fileName, required this.moduleName});
}

class VbxDocsService {
  static const String repoOwner = 'wiederda';
  static const String repoName = 'vbx';
  static const String branch = 'main';
  static const String docsPath = 'md';

  // Zentrales Repository für die Plugin-Dokumentation.
  //
  // Struktur:
  //
  // wiederda/vbx-plugins/
  // ├── yaml/
  // │   └── yaml.md
  // ├── docker/
  // │   └── docker.md
  // └── ...
  static const String pluginRepoName = 'vbx-plugins';
  static const String pluginBranch = 'main';

  List<VbxDocEntry> _entries = [];

  final Map<String, String> _contentCache = {};

  List<VbxDocEntry> get entries => _entries;

  bool get hasCachedDocs => _entries.isNotEmpty;

  Future<Directory> _cacheDir() async {
    final dir = VbxAppPaths.docsCacheDirectory;

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// "Allgemein" soll immer als erster Eintrag erscheinen.
  /// Der Rest bleibt alphabetisch sortiert.
  void _sortEntries(List<VbxDocEntry> entries) {
    entries.sort((a, b) {
      final aIsPinned = a.moduleName.toLowerCase() == 'allgemein';
      final bIsPinned = b.moduleName.toLowerCase() == 'allgemein';

      if (aIsPinned && !bIsPinned) {
        return -1;
      }

      if (bIsPinned && !aIsPinned) {
        return 1;
      }

      return a.moduleName.toLowerCase().compareTo(b.moduleName.toLowerCase());
    });
  }

  /// Lädt beim App-Start ausschließlich aus dem lokalen Cache.
  ///
  /// Kein Netzwerkzugriff.
  Future<void> loadFromCache() async {
    final dir = await _cacheDir();

    if (!await dir.exists()) {
      return;
    }

    final files = await dir
        .list()
        .where((f) => f.path.toLowerCase().endsWith('.md'))
        .toList();

    final entries = <VbxDocEntry>[];
    final cache = <String, String>{};

    for (final entity in files) {
      final fileName = entity.uri.pathSegments.last;

      final moduleName = fileName.replaceFirst(
        RegExp(r'\.md$', caseSensitive: false),
        '',
      );

      entries.add(VbxDocEntry(fileName: fileName, moduleName: moduleName));

      cache[fileName] = await File(entity.path).readAsString();
    }

    _sortEntries(entries);

    _entries = entries;

    _contentCache
      ..clear()
      ..addAll(cache);
  }

  String? contentFor(String fileName) {
    return _contentCache[fileName];
  }

  /// Lädt die zentrale Dokumentation und die Plugin-Dokumentationen
  /// vollständig neu.
  ///
  /// Die beiden Repositories werden zuerst komplett geladen.
  /// Erst wenn alles erfolgreich war, wird der bisherige Cache ersetzt.
  ///
  /// Dadurch bleiben bei einem Netzwerkfehler die bisher vorhandenen
  /// Dokumentationen erhalten.
  ///
  /// Nicht mehr vorhandene Markdown-Dateien werden beim erfolgreichen
  /// Aktualisieren automatisch aus dem lokalen Cache entfernt.
  Future<void> refreshFromGitHub() async {
    final cacheDir = await _cacheDir();

    final tempDir = Directory('${cacheDir.path}.new');

    final backupDir = Directory('${cacheDir.path}.old');

    // Eventuelle Reste eines vorherigen, abgebrochenen Updates entfernen.
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }

    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }

    await tempDir.create(recursive: true);

    final entries = <VbxDocEntry>[];
    final cache = <String, String>{};

    try {
      // ============================================================
      // Zentrale VBX-Dokumentation
      // ============================================================

      await _loadCentralDocs(dir: tempDir, entries: entries, cache: cache);

      // ============================================================
      // Plugin-Dokumentation
      // ============================================================

      await _loadPluginDocs(dir: tempDir, entries: entries, cache: cache);

      _sortEntries(entries);

      // ============================================================
      // Alle Quellen wurden erfolgreich geladen.
      //
      // Erst jetzt wird der bisherige Cache ersetzt.
      // ============================================================

      if (await cacheDir.exists()) {
        await cacheDir.rename(backupDir.path);
      }

      try {
        await tempDir.rename(cacheDir.path);
      } catch (_) {
        // Falls das Ersetzen des alten Cache-Verzeichnisses
        // fehlgeschlagen ist, versuchen wir den alten Zustand
        // wiederherzustellen.
        if (await backupDir.exists() && !await cacheDir.exists()) {
          await backupDir.rename(cacheDir.path);
        }

        rethrow;
      }

      // Der neue Cache ist erfolgreich aktiv.
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }

      _entries = entries;

      _contentCache
        ..clear()
        ..addAll(cache);
    } catch (_) {
      // Der neue temporäre Cache wird verworfen.
      //
      // Der bisherige Cache bleibt unverändert bestehen.
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }

      // Falls beim Austauschen bereits ein Backup angelegt wurde,
      // den alten Cache wiederherstellen.
      if (!await cacheDir.exists() && await backupDir.exists()) {
        await backupDir.rename(cacheDir.path);
      }

      rethrow;
    }
  }

  /// Lädt die Markdown-Dateien aus dem zentralen VBX-Repository.
  Future<void> _loadCentralDocs({
    required Directory dir,
    required List<VbxDocEntry> entries,
    required Map<String, String> cache,
  }) async {
    final listUrl = Uri.parse(
      'https://api.github.com/repos/'
      '$repoOwner/$repoName/contents/$docsPath?ref=$branch',
    );

    final listResponse = await http.get(
      listUrl,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (listResponse.statusCode != 200) {
      throw Exception(
        'Zentrale Dokumentation konnte nicht geladen werden '
        '(${listResponse.statusCode})',
      );
    }

    final decoded = jsonDecode(listResponse.body);

    if (decoded is! List) {
      throw Exception('Ungültige Antwort für die zentrale Dokumentation.');
    }

    final mdFiles = decoded.where(
      (item) =>
          item is Map &&
          item['type'] == 'file' &&
          item['name'] is String &&
          (item['name'] as String).toLowerCase().endsWith('.md'),
    );

    for (final item in mdFiles) {
      final fileName = item['name'] as String;
      final downloadUrl = item['download_url'] as String?;

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('Keine Download-URL für $fileName gefunden.');
      }

      final rawResponse = await http.get(Uri.parse(downloadUrl));

      if (rawResponse.statusCode != 200) {
        throw Exception(
          'Dokumentation $fileName konnte nicht geladen werden '
          '(${rawResponse.statusCode}).',
        );
      }

      final content = utf8.decode(rawResponse.bodyBytes);

      final moduleName = fileName.replaceFirst(
        RegExp(r'\.md$', caseSensitive: false),
        '',
      );

      entries.add(VbxDocEntry(fileName: fileName, moduleName: moduleName));

      cache[fileName] = content;

      final localFile = File('${dir.path}${Platform.pathSeparator}$fileName');

      await localFile.writeAsString(content, encoding: utf8);
    }
  }

  /// Lädt die Dokumentation aller Plugins aus:
  ///
  ///   wiederda/vbx-plugins
  ///
  /// Erwartete Struktur:
  ///
  ///   vbx-plugins/
  ///   ├── yaml/
  ///   │   └── yaml.md
  ///   ├── docker/
  ///   │   └── docker.md
  ///   └── ...
  ///
  /// Es werden keine Plugin-Namen fest im Editor hinterlegt.
  Future<void> _loadPluginDocs({
    required Directory dir,
    required List<VbxDocEntry> entries,
    required Map<String, String> cache,
  }) async {
    final rootUrl = Uri.parse(
      'https://api.github.com/repos/'
      '$repoOwner/$pluginRepoName/contents/'
      '?ref=$pluginBranch',
    );

    final rootResponse = await http.get(
      rootUrl,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (rootResponse.statusCode != 200) {
      throw Exception(
        'Plugin-Dokumentation konnte nicht geladen werden '
        '(${rootResponse.statusCode})',
      );
    }

    final decoded = jsonDecode(rootResponse.body);

    if (decoded is! List) {
      throw Exception('Ungültige Antwort für das Plugin-Repository.');
    }

    final pluginDirectories = decoded.where(
      (item) => item is Map && item['type'] == 'dir' && item['name'] is String,
    );

    for (final plugin in pluginDirectories) {
      final pluginName = plugin['name'] as String;

      await _loadPluginDoc(
        pluginName: pluginName,
        dir: dir,
        entries: entries,
        cache: cache,
      );
    }
  }

  /// Lädt die Markdown-Dateien eines einzelnen Plugins.
  ///
  /// Erwartete Struktur:
  ///
  ///   vbx-plugins/yaml/yaml.md
  Future<void> _loadPluginDoc({
    required String pluginName,
    required Directory dir,
    required List<VbxDocEntry> entries,
    required Map<String, String> cache,
  }) async {
    final pluginUrl = Uri.parse(
      'https://api.github.com/repos/'
      '$repoOwner/$pluginRepoName/contents/'
      '$pluginName?ref=$pluginBranch',
    );

    final response = await http.get(
      pluginUrl,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Plugin $pluginName konnte nicht geladen werden '
        '(${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      throw Exception('Ungültige Antwort für das Plugin $pluginName.');
    }

    final mdFiles = decoded.where(
      (item) =>
          item is Map &&
          item['type'] == 'file' &&
          item['name'] is String &&
          (item['name'] as String).toLowerCase().endsWith('.md'),
    );

    for (final item in mdFiles) {
      final fileName = item['name'] as String;
      final downloadUrl = item['download_url'] as String?;

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception(
          'Keine Download-URL für '
          '$pluginName/$fileName gefunden.',
        );
      }

      final rawResponse = await http.get(Uri.parse(downloadUrl));

      if (rawResponse.statusCode != 200) {
        throw Exception(
          'Plugin-Dokumentation $pluginName/$fileName konnte nicht '
          'geladen werden (${rawResponse.statusCode}).',
        );
      }

      final content = utf8.decode(rawResponse.bodyBytes);

      final moduleName = fileName.replaceFirst(
        RegExp(r'\.md$', caseSensitive: false),
        '',
      );

      entries.add(VbxDocEntry(fileName: fileName, moduleName: moduleName));

      cache[fileName] = content;

      final localFile = File('${dir.path}${Platform.pathSeparator}$fileName');

      await localFile.writeAsString(content, encoding: utf8);
    }
  }
}
