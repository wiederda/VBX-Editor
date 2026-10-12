import 'dart:io';
import 'dart:convert';

typedef OutputCallback = void Function(String chunk);

class VbxRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool cancelled;

  VbxRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.cancelled = false,
  });

  bool get success => exitCode == 0 && !cancelled;
}

class VbxRunnerService {
  final String executable;

  Process? _process;

  bool _cancelRequested = false;

  VbxRunnerService({required this.executable});

  bool get isRunning => _process != null;

  Future<VbxRunResult> run(
    String filePath, {
    OutputCallback? onStdout,
    OutputCallback? onStderr,
  }) {
    return _execute([filePath], onStdout: onStdout, onStderr: onStderr);
  }

  /// Führt einen Befehl aus:
  /// vbx <command> <filePath>
  Future<VbxRunResult> runCommand(
    String command,
    String filePath, {
    OutputCallback? onStdout,
    OutputCallback? onStderr,
  }) {
    return _execute(
      [command, filePath],
      onStdout: onStdout,
      onStderr: onStderr,
    );
  }

  /// Bricht den aktuell laufenden Prozess ab.
  bool stop() {
    final process = _process;

    if (process == null) {
      return false;
    }

    _cancelRequested = true;

    process.kill();

    return true;
  }

  Future<VbxRunResult> _execute(
    List<String> args, {
    OutputCallback? onStdout,
    OutputCallback? onStderr,
  }) async {
    if (_process != null) {
      return VbxRunResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Es läuft bereits ein VBX-Prozess.',
      );
    }

    _cancelRequested = false;

    try {
      final process = await Process.start(executable, args, runInShell: false);

      _process = process;

      final outBuf = StringBuffer();
      final errBuf = StringBuffer();

      final stdoutDone = process.stdout.transform(utf8.decoder).forEach((c) {
        final clean = _stripAnsi(c);
        outBuf.write(clean);
        onStdout?.call(clean);
      });

      final stderrDone = process.stderr.transform(utf8.decoder).forEach((c) {
        final clean = _stripAnsi(c);
        errBuf.write(clean);
        onStderr?.call(clean);
      });

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);

      return VbxRunResult(
        exitCode: exitCode,
        stdout: outBuf.toString(),
        stderr: errBuf.toString(),
        cancelled: _cancelRequested,
      );
    } catch (e) {
      return VbxRunResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
        cancelled: _cancelRequested,
      );
    } finally {
      _process = null;
    }
  }

  String _stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '');
  }
}
