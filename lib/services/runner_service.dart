import 'dart:io';
import 'dart:convert';

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

  Future<VbxRunResult> run(String filePath) async {
    return _execute([filePath]);
  }

  /// Führt einen Befehl aus:
  /// vbx <command> <filePath>
  Future<VbxRunResult> runCommand(String command, String filePath) async {
    return _execute([command, filePath]);
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

  Future<VbxRunResult> _execute(List<String> args) async {
    if (_process != null) {
      return VbxRunResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Es läuft bereits ein VBX-Prozess.',
      );
    }

    _cancelRequested = false;

    try {
      final process = await Process.start(
        executable,
        args,

        // Wichtig:
        // Kein Shell-Prozess dazwischen.
        runInShell: false,
      );

      _process = process;

      final stdoutFuture = process.stdout.transform(utf8.decoder).join();

      final stderrFuture = process.stderr.transform(utf8.decoder).join();

      final exitCode = await process.exitCode;

      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      return VbxRunResult(
        exitCode: exitCode,
        stdout: _stripAnsi(stdout),
        stderr: _stripAnsi(stderr),
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
