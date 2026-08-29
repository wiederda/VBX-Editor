import 'dart:async';
import 'dart:convert';
import 'dart:io';

class VbxTerminalService {
  Process? _process;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Stream<String> get output => _outputController.stream;
  bool get isRunning => _process != null;
  Future<void> start() async {
    if (_process != null) {
      return;
    }
    final command = _shellCommand();
    _process = await Process.start(
      command.executable,
      command.arguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    _stdoutSubscription = _process!.stdout
        .transform(utf8.decoder)
        .listen(_outputController.add);
    _stderrSubscription = _process!.stderr
        .transform(utf8.decoder)
        .listen(_outputController.add);
    _process!.exitCode.then((_) {
      _process = null;
    });
  }

  void write(String text) {
    final process = _process;
    if (process == null) {
      return;
    }
    process.stdin.write(text);
  }

  void writeLine(String text) {
    write('$text\r\n');
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      return;
    }
    _process = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  ({String executable, List<String> arguments}) _shellCommand() {
    if (Platform.isWindows) {
      return (executable: 'cmd.exe', arguments: ['/K']);
    }
    if (Platform.isMacOS) {
      return (executable: '/bin/zsh', arguments: []);
    }
    return (executable: '/bin/bash', arguments: []);
  }

  Future<void> dispose() async {
    await stop();
    await _outputController.close();
  }
}
