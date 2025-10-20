// lib/services/background_service.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../locator.dart';
import '../services/sync_manager.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  debugPrint("[Background Service] Isolate started.");

  try {
    final directory = await getApplicationDocumentsDirectory();
    Hive.init(directory.path);
    registerHiveAdapters(); // Llama a la función pública desde locator.dart
  } catch (e) {
    debugPrint("[Background Service] !! CRITICAL HIVE INIT ERROR: $e");
    service.stopSelf();
    return;
  }

  // Usamos el inicializador LIGERO para el servicio de fondo.
  await setupBackgroundLocator();

  final syncManager = getIt<SyncManager>();

  // Escucha eventos para iniciar o detener el servicio.
  service.on('start').listen((event) {
    debugPrint("[Background Service] 'start' event received. Setting up periodic timer.");
    // Se ejecuta un ciclo de sincronización cada 15 minutos.
    Timer.periodic(const Duration(minutes: 15), (timer) async {
      debugPrint("[Background Service] Periodic sync triggered by Timer.");
      try {
        await syncManager.triggerSync();
        debugPrint("[Background Service] triggerSync() finished.");
      } catch (e, stacktrace) {
        debugPrint("[Background Service] !! CRITICAL ERROR during periodic sync: $e");
        debugPrint("Stacktrace: $stacktrace");
      }
    });
  });

  service.on('stop').listen((event) {
    debugPrint("Background Service] 'stop' event received. Stopping service.");
    service.stopSelf();
  });

  // Invocamos 'start' para que el Timer.periodic comience su ciclo.
  service.invoke('start');
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  onStart(service);
  return true;
}

class AppBackgroundService {
  static final AppBackgroundService _instance = AppBackgroundService._internal();
  factory AppBackgroundService() => _instance;
  AppBackgroundService._internal();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  Future<void> initializeService() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: false, // No muestra una notificación persistente.
        autoStart: true,
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: onIosBackground,
        autoStart: true,
      ),
    );
    debugPrint("Background Service configured in main app.");
  }
}