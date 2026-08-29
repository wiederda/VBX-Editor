import 'dart:io';

class VbxVersionService {
  final String executable;

  VbxVersionService({
    required this.executable,
  });

  Future<String?> getVersion() async {
    try {
      final result = await Process.run(
        executable,
        ['-v'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout.toString().trim();

      if (output.isEmpty) {
        return null;
      }

      return output;
    } catch (_) {
      return null;
    }
  }
}