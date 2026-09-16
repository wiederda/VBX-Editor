import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

class FileService {
  static const List<String> executableExtensions = ['vb'];

  static const List<String> allowedExtensions = [
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

  // Wie viele Bytes für die inhaltsbasierte Text-Erkennung gelesen
  // werden (looksLikeTextFile). Reicht, um Binärdateien zuverlässig
  // zu erkennen, ohne bei großen Dateien die komplette Datei lesen
  // zu müssen.
  static const int _textSniffByteLimit = 8000;

  Future<File?> openVbxFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );

    if (result == null || result.files.single.path == null) {
      return null;
    }

    final path = result.files.single.path!;

    return File(path);
  }

  /// Speichert die Datei unter ihrer eigenen Endung. Wird nur für neue,
  /// noch nie gespeicherte Dateien nach der Endung gefragt -- dann
  /// standardmäßig als .vb (das Hauptformat der App).
  Future<String?> saveVbxFile({
    required String content,
    String? currentPath,
  }) async {
    String? path = currentPath;

    if (path == null) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Datei speichern',
        fileName: 'Unbenannt.vb',
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
    }

    if (path == null) {
      return null;
    }

    final hasKnownExtension = allowedExtensions.any(
      (ext) => path!.toLowerCase().endsWith('.$ext'),
    );

    if (!hasKnownExtension) {
      path += '.vb';
    }

    final file = File(path);

    await file.writeAsString(content);

    return path;
  }

  Future<String> readFile(File file) async {
    return file.readAsString();
  }

  /// Prüft anhand der Dateiendung, ob eine Datei als VBX-Skript
  /// ausführbar ist (.vb). Alles andere (txt, json, ini, csv, ...)
  /// ist nur zum Anzeigen/Bearbeiten/Speichern gedacht.
  static bool isExecutable(String? path) {
    if (path == null) {
      return false;
    }

    return path.toLowerCase().endsWith('.vb');
  }

  /// Prüft den tatsächlichen INHALT einer Datei, statt sich nur auf
  /// die Endung zu verlassen -- gedacht als Fallback für Dateien mit
  /// unbekannter/fehlender Endung (z.B. "backup.txt.old"), die trotzdem
  /// reiner Text sind.
  ///
  /// Liest die ersten paar KB und prüft:
  ///   1. Keine Null-Bytes (0x00) -- klassisches Binär-Indiz, in
  ///      echtem Text praktisch nie vorhanden.
  ///   2. Der gelesene Ausschnitt lässt sich als gültiges UTF-8
  ///      dekodieren (konsistent mit readFile(), das intern ebenfalls
  ///      UTF-8 erwartet).
  ///
  /// Da der gelesene Ausschnitt mitten in einer Mehrbyte-UTF-8-Sequenz
  /// abschneiden kann, wird bei einem Dekodierfehler einmalig mit den
  /// letzten 3 Bytes weniger erneut versucht, bevor die Datei als
  /// "kein Text" gilt.
  static Future<bool> looksLikeTextFile(File file) async {
    RandomAccessFile? raf;

    try {
      raf = await file.open();

      final length = await raf.length();
      final readLength = length < _textSniffByteLimit
          ? length
          : _textSniffByteLimit;

      final bytes = await raf.read(readLength);

      if (bytes.contains(0)) {
        return false;
      }

      if (_decodesAsUtf8(bytes)) {
        return true;
      }

      // Möglicherweise nur am Ende mitten in einer Mehrbyte-Sequenz
      // abgeschnitten -- ein zweites Mal mit etwas kürzerem Ausschnitt
      // versuchen, bevor endgültig "kein Text" entschieden wird.
      if (bytes.length > 3) {
        return _decodesAsUtf8(bytes.sublist(0, bytes.length - 3));
      }

      return false;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  static bool _decodesAsUtf8(List<int> bytes) {
    try {
      utf8.decode(bytes, allowMalformed: false);
      return true;
    } on FormatException {
      return false;
    }
  }
}
