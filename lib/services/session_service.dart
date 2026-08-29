import 'dart:convert';
import 'dart:io';

class SessionTabState {
  final String? path;
  final bool modified;
  final String? unsavedContent;

  SessionTabState({this.path, required this.modified, this.unsavedContent});

  Map<String, dynamic> toJson() => {
    'path': path,
    'modified': modified,
    // Inhalt IMMER mitspeichern, wenn geändert -- unabhängig davon,
    // ob schon ein Pfad existiert.
    'unsavedContent': modified ? unsavedContent : null,
  };

  factory SessionTabState.fromJson(Map<String, dynamic> json) {
    return SessionTabState(
      path: json['path'] as String?,
      modified: json['modified'] as bool? ?? false,
      unsavedContent: json['unsavedContent'] as String?,
    );
  }
}

class SessionData {
  final List<SessionTabState> tabs;
  final int activeIndex;

  SessionData({required this.tabs, required this.activeIndex});
}

class VbxSessionService {
  Future<File> _sessionFile() async {
    final appData = Platform.environment['APPDATA'];

    if (appData == null || appData.isEmpty) {
      throw Exception('APPDATA konnte nicht ermittelt werden.');
    }

    final dir = Directory('$appData${Platform.pathSeparator}VBX Editor');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return File('${dir.path}${Platform.pathSeparator}session.json');
  }

  Future<void> save(List<SessionTabState> tabs, int activeIndex) async {
    final file = await _sessionFile();

    final data = {
      'activeIndex': activeIndex,
      'tabs': tabs.map((t) => t.toJson()).toList(),
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<SessionData?> load() async {
    final file = await _sessionFile();

    if (!await file.exists()) {
      return null;
    }

    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final tabsJson = decoded['tabs'];

      if (tabsJson is! List) {
        return null;
      }

      final tabs = tabsJson
          .whereType<Map>()
          .map((m) => SessionTabState.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      final activeIndex = (decoded['activeIndex'] as num?)?.toInt() ?? 0;

      return SessionData(tabs: tabs, activeIndex: activeIndex);
    } catch (_) {
      return null;
    }
  }
}
