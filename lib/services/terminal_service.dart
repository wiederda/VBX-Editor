import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm2/xterm.dart';

/// Startet eine Shell über ein echtes Pseudo-Terminal (ConPTY unter Windows).
/// Im Unterschied zu einem einfachen Process.start() mit Pipes übernimmt
/// hier die Konsolen-API selbst das Echo der Eingabe, Cursor-Steuerung,
/// Größenänderungen etc. -- genau das, was ein interaktives Terminal
/// (wie in VS Code) braucht.
class VbxTerminalService {
  Pty? _pty;
  Terminal? _terminal;

  bool get isRunning => _pty != null;

  Future<void> start(Terminal terminal) async {
    if (_pty != null) {
      return;
    }

    _terminal = terminal;

    final shell = _shellCommand();

    final pty = Pty.start(
      shell.executable,
      arguments: shell.arguments,
      environment: Platform.environment,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );

    _pty = pty;

    // Ausgabe der Shell (inkl. Echo, ANSI-Codes) -> Terminal-Anzeige.
    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    // Tastatureingaben im Terminal -> an die Shell weiterreichen.
    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    // Fenstergröße des Terminals an die Shell weitergeben (wichtig für
    // Programme, die die Terminalbreite kennen müssen, z. B. für Umbrüche).
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      pty.resize(height, width);
    };

    pty.exitCode.then((exitCode) {
      if (identical(_pty, pty)) {
        _pty = null;

        terminal.write('\r\n[Prozess beendet: $exitCode]\r\n');
      }
    });
  }

  Future<void> stop() async {
    final pty = _pty;

    if (pty == null) {
      return;
    }

    _pty = null;

    try {
      pty.kill();
    } catch (_) {
      // Prozess ist möglicherweise bereits beendet.
    }
  }

  ({String executable, List<String> arguments}) _shellCommand() {
    if (Platform.isWindows) {
      return (executable: 'cmd.exe', arguments: []);
    }

    if (Platform.isMacOS) {
      return (executable: '/bin/zsh', arguments: []);
    }

    return (executable: '/bin/bash', arguments: []);
  }

  Future<void> dispose() async {
    await stop();
    _terminal = null;
  }
}
