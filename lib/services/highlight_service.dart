import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VbxHighlightConfig {
  final Map<String, Color> colors;
  final Map<String, Color> colorsLight;

  final Set<String> keywords;
  final Set<String> booleans;
  final Set<String> logicals;
  final Set<String> directives;
  final Set<String> operators;
  //final Set<String> functions;

  final String lineComment;
  final String blockCommentStart;
  final String blockCommentEnd;

  VbxHighlightConfig({
    required this.colors,
    required this.colorsLight,
    required this.keywords,
    required this.booleans,
    required this.logicals,
    required this.directives,
    required this.operators,
    //  required this.functions,
    required this.lineComment,
    required this.blockCommentStart,
    required this.blockCommentEnd,
  });

  /// Liefert das passende Farbschema je nach Theme-Helligkeit.
  Map<String, Color> colorsFor(Brightness brightness) {
    return brightness == Brightness.dark ? colors : colorsLight;
  }

  factory VbxHighlightConfig.fromJson(Map<String, dynamic> json) {
    final colorJson = Map<String, dynamic>.from(json['colors'] ?? {});

    // Falls kein eigenes Light-Set definiert ist, auf 'colors' zurückfallen.
    final colorLightJson = Map<String, dynamic>.from(
      json['colors_light'] ?? json['colors'] ?? {},
    );

    Color parseColor(String? value, Color fallback) {
      if (value == null) {
        return fallback;
      }

      final hex = value.replaceFirst('#', '');

      if (hex.length != 6) {
        return fallback;
      }

      final rgb = int.tryParse(hex, radix: 16);

      if (rgb == null) {
        return fallback;
      }

      return Color(0xFF000000 | rgb);
    }

    Map<String, Color> buildColorMap(Map<String, dynamic> source) {
      return {
        'keyword': parseColor(source['keyword'], Colors.blue),
        'boolean': parseColor(source['boolean'], Colors.blue),
        'logical': parseColor(source['logical'], Colors.purple),
        'operator': parseColor(source['operator'], Colors.white),
        'string': parseColor(source['string'], Colors.orange),
        'number': parseColor(source['number'], Colors.green),
        'comment': parseColor(source['comment'], Colors.grey),
        'function': parseColor(source['function'], Colors.yellow),
        'directive': parseColor(source['directive'], Colors.purple),
      };
    }

    final commentJson = Map<String, dynamic>.from(json['comments'] ?? {});

    return VbxHighlightConfig(
      colors: buildColorMap(colorJson),
      colorsLight: buildColorMap(colorLightJson),

      keywords: Set<String>.from(json['keywords'] ?? []),

      booleans: Set<String>.from(json['booleans'] ?? []),

      logicals: Set<String>.from(json['logicals'] ?? []),

      directives: Set<String>.from(json['directives'] ?? []),

      operators: Set<String>.from(json['operators'] ?? []),

      //  functions: Set<String>.from(json['functions'] ?? []),
      lineComment: commentJson['line'] ?? "'",

      blockCommentStart: commentJson['blockStart'] ?? "/'",

      blockCommentEnd: commentJson['blockEnd'] ?? "'/",
    );
  }
}

class VbxHighlightService {
  VbxHighlightConfig? _config;

  Future<void> load() async {
    final jsonString = await rootBundle.loadString('assets/vbx.json');

    final json = jsonDecode(jsonString);

    _config = VbxHighlightConfig.fromJson(Map<String, dynamic>.from(json));
  }

  VbxHighlightConfig? get config => _config;
}
