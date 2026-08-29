import 'dart:convert';

import 'package:flutter/services.dart';

class VbxSyntaxInfo {
  final String name;
  final String syntax;
  final String description;

  VbxSyntaxInfo({
    required this.name,
    required this.syntax,
    required this.description,
  });
}

class VbxSyntaxService {
  Map<String, dynamic>? _data;

  Future<void> load() async {
    final jsonString = await rootBundle.loadString('assets/vbx.json');
    _data = jsonDecode(jsonString);
  }

  // ------------------------------------------------------------
  // Einzelne Funktion
  // ------------------------------------------------------------

  VbxSyntaxInfo? findFullName(String fullName) {
    if (_data == null) {
      return null;
    }

    final syntax = _data!['syntax'];

    if (syntax is! Map) {
      return null;
    }

    final parts = fullName.split('.');

    String module;
    String function;

    // ------------------------------------------------------------
    // global: Split(...)
    // ------------------------------------------------------------

    if (parts.length == 1) {
      module = 'global';
      function = parts[0];
    }
    // ------------------------------------------------------------
    // Namespace: app.CurrentDirectory()
    // ------------------------------------------------------------
    else if (parts.length == 2) {
      module = parts[0];
      function = parts[1];
    } else {
      return null;
    }

    final moduleData = syntax[module];

    if (moduleData is! Map) {
      return null;
    }

    final functionData = moduleData[function];

    if (functionData is! Map) {
      return null;
    }

    return VbxSyntaxInfo(
      name: function,
      syntax: functionData['syntax']?.toString() ?? '',
      description: functionData['description']?.toString() ?? '',
    );
  }

  // ------------------------------------------------------------
  // Alle Funktionen eines Moduls
  // ------------------------------------------------------------

  List<VbxSyntaxInfo> findModuleFunctions(String module) {
    if (_data == null) {
      return [];
    }

    final syntax = _data!['syntax'];

    if (syntax is! Map) {
      return [];
    }

    final moduleData = syntax[module];

    if (moduleData is! Map) {
      return [];
    }

    final result = <VbxSyntaxInfo>[];

    for (final entry in moduleData.entries) {
      final functionData = entry.value;

      if (functionData is! Map) {
        continue;
      }

      result.add(
        VbxSyntaxInfo(
          name: entry.key.toString(),
          syntax: functionData['syntax']?.toString() ?? '',
          description: functionData['description']?.toString() ?? '',
        ),
      );
    }

    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return result;
  }
}
