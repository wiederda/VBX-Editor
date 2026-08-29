import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class VbxDocEntry {
  final String fileName; // z.B. "array.md"
  final String moduleName; // z.B. "array"

  VbxDocEntry({required this.fileName, required this.moduleName});
}

class VbxDocsService {
  // TODO: an dein echtes Repo anpassen
  static const String repoOwner = 'wiederda';
  static const String repoName = 'vbx';
  static const String branch = 'main';
  static const String docsPath = 'md';

  List<VbxDocEntry> _entries = [];
  final Map<String, String> _contentCache = {};

  List<VbxDocEntry> get entries => _entries;

  bool get hasCachedDocs => _entries.isNotEmpty;

  Future<Directory> _cacheDir() async {
    final appData = Platform.environment['APPDATA'];

    if (appData == null || appData.isEmpty) {
      throw Exception('APPDATA konnte nicht ermittelt werden.');
    }

    final dir = Directory(
      '$appData${Platform.pathSeparator}VBX Editor${Platform.pathSeparator}docs_cache',
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// "Allgemein" soll immer als erster Eintrag erscheinen,
  /// der Rest bleibt alphabetisch sortiert.
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

      return a.moduleName.compareTo(b.moduleName);
    });
  }

  /// Lädt beim App-Start ausschließlich aus dem lokalen Cache.
  /// Kein Netzwerkzugriff.
  Future<void> loadFromCache() async {
    final dir = await _cacheDir();

    if (!await dir.exists()) {
      return;
    }

    final files = await dir
        .list()
        .where((f) => f.path.endsWith('.md'))
        .toList();

    final entries = <VbxDocEntry>[];
    final cache = <String, String>{};

    for (final entity in files) {
      final fileName = entity.uri.pathSegments.last;
      final moduleName = fileName.replaceAll('.md', '');

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

  /// Lädt die Liste + Inhalte frisch von GitHub und überschreibt den Cache.
  /// Wird nur manuell aufgerufen (Button "Aktualisieren").
  Future<void> refreshFromGitHub() async {
    final listUrl = Uri.parse(
      'https://api.github.com/repos/$repoOwner/$repoName/contents/$docsPath?ref=$branch',
    );

    final listResponse = await http.get(
      listUrl,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (listResponse.statusCode != 200) {
      throw Exception(
        'Liste konnte nicht geladen werden (${listResponse.statusCode})',
      );
    }

    final List<dynamic> items = jsonDecode(listResponse.body);

    final mdFiles = items.where(
      (item) =>
          item['type'] == 'file' && (item['name'] as String).endsWith('.md'),
    );

    final dir = await _cacheDir();

    final entries = <VbxDocEntry>[];
    final cache = <String, String>{};

    for (final item in mdFiles) {
      final fileName = item['name'] as String;
      final downloadUrl = item['download_url'] as String?;

      if (downloadUrl == null) {
        continue;
      }

      final rawResponse = await http.get(Uri.parse(downloadUrl));

      if (rawResponse.statusCode != 200) {
        continue;
      }

      final content = utf8.decode(rawResponse.bodyBytes);
      final moduleName = fileName.replaceAll('.md', '');

      entries.add(VbxDocEntry(fileName: fileName, moduleName: moduleName));

      cache[fileName] = content;

      final localFile = File('${dir.path}/$fileName');
      await localFile.writeAsString(content);
    }

    _sortEntries(entries);

    _entries = entries;
    _contentCache
      ..clear()
      ..addAll(cache);
  }
}
