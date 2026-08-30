import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class VbxUpdateCheckResult {
  final String latestVersion;
  final String downloadUrl;
  final bool isNewer;

  VbxUpdateCheckResult({
    required this.latestVersion,
    required this.downloadUrl,
    required this.isNewer,
  });
}

class VbxUpdateService {
  static const String repoOwner = 'wiederda';
  static const String repoName = 'vbx';
  static const String assetName = 'vbx.exe';

  Future<VbxUpdateCheckResult> checkForUpdate(String? currentVersionRaw) async {
    final url = Uri.parse(
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
    );

    final response = await http.get(
      url,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'GitHub-Release konnte nicht abgerufen werden (${response.statusCode}).',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    final tagName = data['tag_name']?.toString() ?? '';
    final assets = data['assets'] as List<dynamic>? ?? [];

    String? downloadUrl;

    for (final asset in assets) {
      final map = Map<String, dynamic>.from(asset as Map);

      if (map['name'] == assetName) {
        downloadUrl = map['browser_download_url']?.toString();
        break;
      }
    }

    if (downloadUrl == null) {
      throw Exception('Kein "$assetName" im neuesten Release gefunden.');
    }

    final isNewer = _isNewerVersion(currentVersionRaw, tagName);

    return VbxUpdateCheckResult(
      latestVersion: tagName,
      downloadUrl: downloadUrl,
      isNewer: isNewer,
    );
  }

  bool _isNewerVersion(String? current, String latestTag) {
    final currentParts = _extractVersionParts(current ?? '');
    final latestParts = _extractVersionParts(latestTag);

    if (currentParts.isEmpty) {
      // Aktuelle Version konnte nicht bestimmt werden -> sicherheitshalber
      // ein Update anbieten, statt fälschlich "aktuell" zu melden.
      return true;
    }

    final maxLength = currentParts.length > latestParts.length
        ? currentParts.length
        : latestParts.length;

    for (var i = 0; i < maxLength; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final l = i < latestParts.length ? latestParts[i] : 0;

      if (l > c) return true;
      if (l < c) return false;
    }

    return false;
  }

  List<int> _extractVersionParts(String text) {
    final match = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(text);

    if (match == null) {
      return [];
    }

    return [
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
    ];
  }

  /// Lädt die neue vbx.exe herunter und installiert sie unter [targetPath].
  /// Schlägt das direkte Schreiben fehl (z. B. weil vbx.exe unter
  /// "Program Files" liegt und Adminrechte nötig sind), wird per
  /// PowerShell ein erhöhter Kopiervorgang angestoßen (UAC-Abfrage).
  Future<void> downloadAndInstall({
    required String downloadUrl,
    required String targetPath,
  }) async {
    final response = await http.get(Uri.parse(downloadUrl));

    if (response.statusCode != 200) {
      throw Exception('Download fehlgeschlagen (${response.statusCode}).');
    }

    final tempDir = await Directory.systemTemp.createTemp('vbx_update_');
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}vbx.exe');

    await tempFile.writeAsBytes(response.bodyBytes);

    try {
      try {
        await tempFile.copy(targetPath);
      } on FileSystemException {
        // Vermutlich fehlende Rechte (z. B. Program Files) -> mit
        // erhöhten Rechten über PowerShell erneut versuchen.
        await _copyWithElevation(tempFile.path, targetPath);
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<void> _copyWithElevation(String sourcePath, String targetPath) async {
    // Startet einen erhöhten Prozess (UAC-Abfrage), der die Datei kopiert.
    final psCommand =
        "Start-Process -FilePath 'cmd.exe' "
        "-ArgumentList '/c copy /Y \"$sourcePath\" \"$targetPath\"' "
        "-Verb RunAs -Wait";

    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      psCommand,
    ], runInShell: true);

    if (result.exitCode != 0) {
      throw Exception(
        'Update konnte auch mit erhöhten Rechten nicht installiert werden.',
      );
    }

    if (!await File(targetPath).exists()) {
      throw Exception('Zieldatei nach Update nicht gefunden: $targetPath');
    }
  }
}
