import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sorgt dafür, dass nur eine Instanz von VBX Editor läuft.
///
/// Wird die App erneut gestartet, z. B. über "Öffnen mit" im Explorer,
/// wird der übergebene Dateipfad an die bereits laufende Instanz
/// weitergereicht, statt ein zweites Fenster zu öffnen.
///
/// Beim Neustart als Administrator gibt es einen speziellen Ablauf:
/// Die erhöhte Instanz wartet, bis die bisherige Instanz ihren Port
/// freigegeben hat, und übernimmt anschließend selbst die primäre
/// Instanz.
class SingleInstanceService {
  /// Fester, möglichst unwahrscheinlicher lokaler Port.
  static const int _port = 51737;

  /// Maximale Wartezeit beim Wechsel auf die Admin-Instanz.
  static const Duration _adminTakeoverTimeout = Duration(seconds: 15);

  ServerSocket? _server;

  final _fileOpenController = StreamController<String>.broadcast();

  /// Feuert für jede Datei, die von einer weiteren Instanz
  /// weitergereicht wurde.
  ///
  /// Ein leerer String bedeutet:
  /// "Nur nach vorne holen", ohne eine bestimmte Datei zu öffnen.
  Stream<String> get onFileOpenRequested => _fileOpenController.stream;

  /// Versucht, die "primäre" Instanz zu werden.
  ///
  /// Gibt true zurück, wenn diese Instanz die primäre ist.
  ///
  /// Gibt false zurück, wenn bereits eine andere Instanz läuft.
  /// In diesem Fall wurde [filePath] an die bestehende Instanz
  /// weitergereicht.
  Future<bool> becomePrimaryOrForward(String? filePath) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
    } catch (_) {
      // Port bereits belegt -> es läuft schon eine Instanz.
      await _forwardToPrimary(filePath);
      return false;
    }

    _listenForRequests();

    return true;
  }

  /// Wartet darauf, dass die bisherige Instanz ihren Port freigibt,
  /// und übernimmt anschließend selbst die primäre Instanz.
  ///
  /// Diese Methode wird ausschließlich beim Admin-Neustart verwendet.
  ///
  /// Wichtig:
  /// Es wird hier NICHT an die alte Instanz weitergeleitet.
  Future<bool> waitAndBecomePrimary() async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < _adminTakeoverTimeout) {
      try {
        _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);

        _listenForRequests();

        return true;
      } catch (_) {
        // Die alte Instanz läuft noch.
        //
        // Kurz warten und anschließend erneut versuchen.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    return false;
  }

  void _listenForRequests() {
    _server!.listen((socket) {
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _fileOpenController.add(line);
          });
    });
  }

  Future<void> _forwardToPrimary(String? filePath) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 2),
      );

      socket.write('${filePath ?? ''}\n');

      await socket.flush();
      await socket.close();
    } catch (_) {
      // Primäre Instanz nicht erreichbar.
      //
      // Die aufrufende Instanz beendet sich trotzdem.
    }
  }

  void dispose() {
    _server?.close();
    _server = null;

    _fileOpenController.close();
  }
}
