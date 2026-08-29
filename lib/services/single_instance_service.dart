import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sorgt dafür, dass nur eine Instanz von VBX Editor läuft. Wird die App
/// erneut gestartet (z. B. über "Öffnen mit" im Explorer), wird der
/// übergebene Dateipfad an die bereits laufende Instanz weitergereicht,
/// statt ein zweites Fenster zu öffnen -- die neu gestartete Instanz
/// beendet sich danach sofort selbst.
class SingleInstanceService {
  // Fester, möglichst unwahrscheinlich kollidierender lokaler Port.
  static const int _port = 51737;

  ServerSocket? _server;
  final _fileOpenController = StreamController<String>.broadcast();

  /// Feuert für jede Datei, die von einer weiteren (sich sofort wieder
  /// beendenden) Instanz weitergereicht wurde. Ein leerer String bedeutet
  /// "nur nach vorne holen", ohne eine bestimmte Datei zu öffnen.
  Stream<String> get onFileOpenRequested => _fileOpenController.stream;

  /// Versucht, die "primäre" Instanz zu werden.
  ///
  /// Gibt true zurück, wenn diese Instanz die primäre ist (der Server
  /// konnte gestartet werden) -- die App soll dann normal weiterstarten.
  ///
  /// Gibt false zurück, wenn bereits eine andere Instanz läuft. In dem
  /// Fall wurde [filePath] (falls vorhanden) bereits an sie gesendet,
  /// und der Aufrufer sollte den Prozess sofort beenden.
  Future<bool> becomePrimaryOrForward(String? filePath) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
    } catch (_) {
      // Port bereits belegt -> es läuft schon eine Instanz.
      await _forwardToPrimary(filePath);
      return false;
    }

    _server!.listen((socket) {
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _fileOpenController.add(line);
          });
    });

    return true;
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
      // Primäre Instanz nicht erreichbar -- diese Instanz beendet sich
      // trotzdem gleich, es gibt nichts weiter zu tun.
    }
  }

  void dispose() {
    _server?.close();
    _fileOpenController.close();
  }
}
