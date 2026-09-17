import 'dart:convert';

import 'package:flutter/services.dart';

/// Eine Stelle im Code, an der ein Namespace verwendet wird.
class ModuleUsageIssue {
  final String module;
  final String function;

  /// 1-basierte Zeilennummer.
  final int line;

  /// Absolute Zeichenposition im gesamten Script.
  final int start;
  final int end;

  /// Wenn der Namespace eindeutig einem bekannten Namespace
  /// aus vbx.json ähnelt.
  ///
  /// Beispiel:
  ///   strin -> string
  final String? suggestedModule;

  /// true, wenn es sich um ein bekanntes optionales Modul handelt,
  /// das noch nicht per #use eingebunden wurde.
  final bool isOptionalModule;

  ModuleUsageIssue({
    required this.module,
    required this.function,
    required this.line,
    required this.start,
    required this.end,
    required this.isOptionalModule,
    this.suggestedModule,
  });
}

class VbxUsageCheckService {
  final Set<String> _coreModules = {};
  final Set<String> _optionalModules = {};
  final Set<String> _knownModules = {};

  bool _loaded = false;

  // Namespace.Funktion(-Aufrufe. Als Klassenfeld, damit check() und
  // usedOptionalModules() garantiert dieselbe Erkennung verwenden.
  static final RegExp _callRegex = RegExp(
    r'((?:[A-Za-z_][A-Za-z0-9_]*|[0-9]+[A-Za-z_][A-Za-z0-9_]*))\.([A-Za-z_][A-Za-z0-9_]*)\s*\(',
  );

  /// Bereitet eine Zeile für die Modul-Erkennung vor: entfernt einen
  /// Zeilen-Kommentar (') UND blendet String-Literal-Inhalte (inkl.
  /// ""-Escape) aus -- in einem einzigen Durchlauf, damit ein Apostroph
  /// INNERHALB eines Strings (z.B. "John's Skript") nicht fälschlich
  /// als Kommentar-Start erkannt wird. Ein Apostroph AUSSERHALB eines
  /// Strings beendet weiterhin die Zeile wie ein echter Kommentar.
  ///
  /// Ersetzt die früheren getrennten Methoden _stripLineComment und
  /// _blankOutStringLiterals: zwei getrennte Durchläufe konnten das
  /// John's-Skript-Problem nicht lösen, weil der Kommentar-Schnitt
  /// zuerst lief und zu dem Zeitpunkt noch nichts von String-Grenzen
  /// wusste. Zeilenlänge bleibt bis zum Kommentar-Beginn unverändert,
  /// damit start/end-Offsets in ModuleUsageIssue weiter stimmen.
  String _sanitizeLine(String line) {
    final buffer = StringBuffer();
    var inString = false;
    var i = 0;

    while (i < line.length) {
      final ch = line[i];

      if (ch == '"') {
        if (inString && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('  '); // "" (escapetes Anführungszeichen) im String
          i += 2;
          continue;
        }
        inString = !inString;
        buffer.write(' '); // das Anführungszeichen selbst ausblenden
        i++;
        continue;
      }

      if (ch == "'" && !inString) {
        // Kommentar beginnt hier, außerhalb eines Strings -- Rest der Zeile ignorieren.
        break;
      }

      buffer.write(inString ? ' ' : ch);
      i++;
    }

    return buffer.toString();
  }

  /// Lädt die bekannten Module aus assets/vbx.json.
  Future<void> load() async {
    final jsonString = await rootBundle.loadString('assets/vbx.json');
    final data = jsonDecode(jsonString);

    if (data is! Map) {
      throw const FormatException(
        'vbx.json enthält kein gültiges JSON-Objekt.',
      );
    }

    _coreModules.clear();
    _optionalModules.clear();
    _knownModules.clear();

    // ------------------------------------------------------------
    // Core-Module
    // ------------------------------------------------------------

    final core = data['coreModules'];

    if (core is List) {
      for (final module in core) {
        final name = module.toString().trim().toLowerCase();

        if (name.isNotEmpty) {
          _coreModules.add(name);
          _knownModules.add(name);
        }
      }
    }

    // ------------------------------------------------------------
    // Optionale Module
    // ------------------------------------------------------------

    final optional = data['optionalModules'];

    if (optional is List) {
      for (final module in optional) {
        final name = module.toString().trim().toLowerCase();

        if (name.isNotEmpty) {
          _optionalModules.add(name);
          _knownModules.add(name);
        }
      }
    }

    _loaded = true;
  }

  bool get isLoaded => _loaded;

  /// true, wenn [module] ein bekanntes optionales Modul ist
  /// (case-insensitive).
  bool isKnownOptionalModule(String module) {
    return _optionalModules.contains(module.trim().toLowerCase());
  }

  /// Prüft Namespace.Funktion()-Aufrufe.
  ///
  /// Regeln:
  ///
  /// Core:
  ///   immer verfügbar.
  ///
  /// Optional:
  ///   muss per #use eingebunden sein.
  ///
  /// Unbekannt:
  ///   wird gegen die bekannten Namespaces aus vbx.json geprüft.
  ///
  ///   Ist eine eindeutige Ähnlichkeit vorhanden, wird
  ///   suggestedModule gesetzt.
  ///
  ///   Andernfalls bleibt suggestedModule null und der Editor
  ///   kann die Stelle gelb markieren.
  List<ModuleUsageIssue> check(String scriptText) {
    if (!_loaded) {
      return [];
    }

    final lines = scriptText.split('\n');

    final declaredModules = <String>{};

    // ------------------------------------------------------------
    // 1. #use-Direktiven einsammeln
    // ------------------------------------------------------------

    final useLineRegex = RegExp(r'^\s*#use\s+(.+)\s*$', caseSensitive: false);

    for (final rawLine in lines) {
      final match = useLineRegex.firstMatch(rawLine);

      if (match == null) {
        continue;
      }

      final modules = match.group(1)!.split(',');

      for (final module in modules) {
        final name = module.trim().toLowerCase();

        if (name.isNotEmpty) {
          declaredModules.add(name);
        }
      }
    }

    // ------------------------------------------------------------
    // 2. Namespace.Funktion()-Aufrufe suchen
    // ------------------------------------------------------------

    final issues = <ModuleUsageIssue>[];

    // Verhindert doppelte Meldungen an exakt derselben Stelle.
    final alreadyFound = <String>{};

    var lineStartOffset = 0;

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = _sanitizeLine(lines[lineIndex]);

      for (final match in _callRegex.allMatches(line)) {
        final module = match.group(1)!;
        final function = match.group(2)!;

        final moduleLower = module.toLowerCase();

        final start = lineStartOffset + match.start;
        final end = lineStartOffset + match.start + module.length;

        final key = '$start:$end';

        if (!alreadyFound.add(key)) {
          continue;
        }

        // --------------------------------------------------------
        // Core-Modul -> alles OK
        // --------------------------------------------------------

        if (_coreModules.contains(moduleLower)) {
          continue;
        }

        // --------------------------------------------------------
        // Bekanntes optionales Modul
        // --------------------------------------------------------

        if (_optionalModules.contains(moduleLower)) {
          if (declaredModules.contains(moduleLower)) {
            continue;
          }

          issues.add(
            ModuleUsageIssue(
              module: module,
              function: function,
              line: lineIndex + 1,
              start: start,
              end: end,
              isOptionalModule: true,
            ),
          );

          continue;
        }

        // --------------------------------------------------------
        // Unbekannter Namespace
        // --------------------------------------------------------

        final suggestion = _findSuggestedModule(moduleLower);

        issues.add(
          ModuleUsageIssue(
            module: module,
            function: function,
            line: lineIndex + 1,
            start: start,
            end: end,
            isOptionalModule: false,
            suggestedModule: suggestion,
          ),
        );
      }

      // +1 für den entfernten \n
      lineStartOffset += lines[lineIndex].length + 1;
    }

    return issues;
  }

  /// Liefert alle bekannten optionalen Module, die im Skript
  /// tatsächlich per Namespace.Funktion(...) verwendet werden --
  /// unabhängig davon, ob sie bereits per #use deklariert sind.
  ///
  /// Dient dazu, im Editor nicht mehr benötigte Einträge in #use
  /// zu erkennen (Modul deklariert, aber im Skript nicht/nicht mehr
  /// aufgerufen).
  Set<String> usedOptionalModules(String scriptText) {
    if (!_loaded) {
      return {};
    }

    final lines = scriptText.split('\n');

    final used = <String>{};

    for (final rawLine in lines) {
      final line = _sanitizeLine(rawLine);

      for (final match in _callRegex.allMatches(line)) {
        final moduleLower = match.group(1)!.toLowerCase();

        if (_optionalModules.contains(moduleLower)) {
          used.add(moduleLower);
        }
      }
    }

    return used;
  }

  /// Liefert nur die tatsächlich unbekannten Namespaces zurück.
  ///
  /// Bekannte optionale Module werden hier bewusst nicht berücksichtigt.
  List<ModuleUsageIssue> unknownNamespaces(String scriptText) {
    return check(scriptText)
        .where(
          (issue) => !issue.isOptionalModule && issue.suggestedModule == null,
        )
        .toList();
  }

  /// Sucht einen eindeutigen bekannten Namespace.
  ///
  /// Es wird bewusst nichts vorgeschlagen, wenn mehrere Kandidaten
  /// gleich gut passen.
  String? _findSuggestedModule(String module) {
    if (_knownModules.isEmpty) {
      return null;
    }

    String? bestMatch;
    var bestDistance = 999;
    var equalBestMatches = 0;

    for (final known in _knownModules) {
      final distance = _levenshteinDistance(module, known);

      if (distance < bestDistance) {
        bestDistance = distance;
        bestMatch = known;
        equalBestMatches = 1;
      } else if (distance == bestDistance) {
        equalBestMatches++;
      }
    }

    // Nicht eindeutig.
    if (bestMatch == null || equalBestMatches != 1) {
      return null;
    }

    final maxDistance = switch (module.length) {
      <= 3 => 1,
      <= 6 => 2,
      _ => 3,
    };

    if (bestDistance > maxDistance) {
      return null;
    }

    return bestMatch;
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) {
      return 0;
    }

    if (a.isEmpty) {
      return b.length;
    }

    if (b.isEmpty) {
      return a.length;
    }

    var previous = List<int>.generate(b.length + 1, (index) => index);

    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);

      current[0] = i + 1;

      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;

        final insertion = current[j] + 1;
        final deletion = previous[j + 1] + 1;
        final substitution = previous[j] + cost;

        current[j + 1] = [
          insertion,
          deletion,
          substitution,
        ].reduce((a, b) => a < b ? a : b);
      }

      previous = current;
    }

    return previous[b.length];
  }
}
