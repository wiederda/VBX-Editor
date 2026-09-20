part of 'vbx_editor_app.dart';

class WindowsAdmin {
  /// Prüft, ob der aktuelle Prozess mit Administratorrechten läuft.
  ///
  /// Gibt auf Windows true zurück, wenn der aktuelle Prozess
  /// Administratorrechte besitzt.
  ///
  /// Auf Nicht-Windows-Systemen wird false zurückgegeben.
  static bool isAdministrator() {
    if (!Platform.isWindows) {
      return false;
    }

    final shell32 = DynamicLibrary.open('shell32.dll');

    final isUserAnAdmin = shell32
        .lookupFunction<Int32 Function(), int Function()>('IsUserAnAdmin');

    return isUserAnAdmin() != 0;
  }

  /// Startet den VBX Editor über die Windows-UAC-Elevation
  /// als Administrator neu.
  ///
  /// Gibt true zurück, wenn Windows den neuen Prozess
  /// erfolgreich gestartet hat.
  ///
  /// Gibt false zurück, wenn der Start nicht durchgeführt
  /// werden konnte, z. B. bei Abbruch der UAC-Abfrage.
  static bool restartAsAdministrator({String? filePath}) {
    if (!Platform.isWindows) {
      return false;
    }

    final shell32 = DynamicLibrary.open('shell32.dll');

    final shellExecute = shell32
        .lookupFunction<
          IntPtr Function(
            IntPtr,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Int32,
          ),
          int Function(
            int,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            int,
          )
        >('ShellExecuteW');

    final operation = 'runas'.toNativeUtf16();
    final executable = Platform.resolvedExecutable.toNativeUtf16();
    final arguments = _buildArguments(filePath).toNativeUtf16();

    final result = shellExecute(
      0,
      operation,
      executable,
      arguments,
      nullptr,
      1,
    );

    calloc.free(operation);
    calloc.free(executable);
    calloc.free(arguments);

    // ShellExecuteW:
    //
    // Rückgabewert > 32 = erfolgreich gestartet
    // Rückgabewert <= 32 = Fehler bzw. Start abgebrochen
    return result > 32;
  }

  static String _buildArguments(String? filePath) {
    if (filePath == null || filePath.isEmpty) {
      return '--admin';
    }

    return '--admin --file ${_quoteArgument(filePath)}';
  }

  static String _quoteArgument(String value) {
    // Für Dateipfade müssen insbesondere Leerzeichen
    // berücksichtigt werden.
    //
    // Anführungszeichen innerhalb des Pfades werden escaped.
    final escaped = value.replaceAll('"', r'\"');

    return '"$escaped"';
  }
}
