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
}
