import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/config_service.dart';
import 'services/single_instance_service.dart';
import 'version.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final initialFilePath = args.isNotEmpty ? args.first : null;

  final singleInstance = SingleInstanceService();
  final isPrimary = await singleInstance.becomePrimaryOrForward(
    initialFilePath,
  );

  if (!isPrimary) {
    // Datei wurde an die bereits laufende Instanz weitergereicht --
    // diese hier hat keine Aufgabe mehr und beendet sich sofort.
    exit(0);
  }

  await windowManager.ensureInitialized();
  await windowManager.setTitle('VBX Editor $kEditorVersion');

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
