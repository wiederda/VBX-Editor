import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'vbx_editor_app.dart';
import 'services/config_service.dart';
import 'services/single_instance_service.dart';
import 'version.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isAdmin = false;
  String? initialFilePath;

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];

    if (Platform.isWindows && arg == '--admin') {
      isAdmin = true;
      continue;
    }

    if (arg == '--file' && i + 1 < args.length) {
      initialFilePath = args[++i];
      continue;
    }

    // Explorer / "Öffnen mit":
    //
    // vbx_editor.exe "C:\...\datei.vb"
    //
    // Ein normales Argument ohne -- wird weiterhin
    // als Dateipfad behandelt.
    if (!arg.startsWith('--') && initialFilePath == null) {
      initialFilePath = arg;
    }
  }

  final singleInstance = SingleInstanceService();

  if (isAdmin) {
    // Die alte normale Instanz läuft während des Admin-Neustarts
    // zunächst noch.
    //
    // Deshalb darf die Admin-Instanz hier NICHT forwarden.
    // Sie wartet stattdessen, bis die alte Instanz ihren Port
    // freigegeben hat und übernimmt ihn anschließend selbst.
    final isPrimary = await singleInstance.waitAndBecomePrimary();

    if (!isPrimary) {
      // Die alte Instanz wurde nicht beendet bzw. der Port konnte
      // innerhalb des Zeitlimits nicht übernommen werden.
      singleInstance.dispose();
      exit(1);
    }
  } else {
    // Normaler Start bzw. Explorer "Öffnen mit".
    //
    // Wenn bereits ein Editor läuft, wird der Dateipfad an diesen
    // weitergereicht und diese Instanz beendet sich anschließend.
    final isPrimary = await singleInstance.becomePrimaryOrForward(
      initialFilePath,
    );

    if (!isPrimary) {
      singleInstance.dispose();
      exit(0);
    }
  }

  await windowManager.ensureInitialized();
  await windowManager.setTitle(
    isAdmin
        ? 'Administrator: VBX Editor $kEditorVersion'
        : 'VBX Editor $kEditorVersion',
  );
  final configService = ConfigService();
  await configService.initialize();

  runApp(
    VbxEditorApp(
      configService: configService,
      initialFilePath: initialFilePath,
      singleInstanceService: singleInstance,
    ),
  );
}
