import 'dart:io';

class VbxRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  VbxRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;
}

class VbxRunnerService {
  final String executable;

  VbxRunnerService({required this.executable});

  Future<VbxRunResult> run(String filePath) async {
    return _execute([filePath]);
  }

  /// Führt einen Shell-Befehl aus, z. B. command = "Build".
  /// Ergebnis: vbx <command> <filePath>
  Future<VbxRunResult> runCommand(String command, String filePath) async {
    return _execute([command, filePath]);
  }

  Future<VbxRunResult> _execute(List<String> args) async {
    try {
      final result = await Process.run(executable, args, runInShell: true);

      return VbxRunResult(
        exitCode: result.exitCode,
        stdout: _stripAnsi(result.stdout.toString()),
        stderr: _stripAnsi(result.stderr.toString()),
      );
    } catch (e) {
      return VbxRunResult(exitCode: -1, stdout: '', stderr: e.toString());
    }
  }

  String _stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '');
  }
}
