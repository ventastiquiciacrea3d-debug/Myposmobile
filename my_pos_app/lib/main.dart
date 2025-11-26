// lib/main.dart
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_pos_mobile_barcode/models/product.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'models/sync_operation.dart';
import 'locator.dart';
import 'config/constants.dart';
import 'services/api_cache_manager.dart';
import 'services/auto_cleanup_service.dart';
// import 'services/delta_sync_service.dart'; // ⚠️ Deshabilitado - Requiere Firebase
import 'services/lazy_loading_service.dart';
import 'services/image_cache_system.dart';
import 'services/screen_state_service.dart';
// import 'services/background_sync_service.dart';  // ❌ ELIMINADO - WorkManager removido
import 'services/ultra_optimized_polling_service.dart';

Product parseProductJsonInBackground(String jsonString) {
  final Map<String, dynamic> jsonMap = json.decode(jsonString);
  return Product.fromJson(jsonMap);
}

/// ✓ OPTIMIZACIÓN: Función de nivel superior para inicializar servicios pesados
/// Se ejecuta en un isolate separado para no bloquear el hilo principal
Future<void> initializeCoreServices(SendPort? sendPort) async {
  debugPrint("[INIT_ISOLATE] Initializing core services in background...");

  try {
    // 1. Inicializar Hive
    final appDocumentDirectory = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDirectory.path);
    registerHiveAdapters();

    debugPrint("[INIT_ISOLATE] Hive initialized, opening boxes...");

    // 2. Abrir solo las cajas de Hive que NO han sido migradas
    await Future.wait([
      // ✅ AÚN EN HIVE - Solo SyncQueue
      Hive.openBox<SyncOperation>(hiveSyncQueueBoxName),

      // ❌ MIGRADO A SHAREDPREFERENCES - Ya no usa Hive
      // Hive.openBox(hiveSettingsBoxName),
      // Hive.openBox<InventoryAdjustmentCache>(hiveInventoryAdjustmentCacheBoxName),

      // ❌ MIGRADO A OBJECTBOX - Ya no usa Hive
      // Hive.openBox<Product>(hiveProductsBoxName),
      // Hive.openBox<Order>(hiveOrdersBoxName),
      // Hive.openBox<Order>(hivePendingOrdersBoxName),
      // Hive.openBox<LabelPrintItem>(hiveLabelQueueBoxName),
      // Hive.openBox<InventoryMovement>(hiveInventoryMovementsBoxName),

      // ❌ ELIMINADO - Código muerto
      // Hive.openBox<List<String>>(hiveBarcodeIndexBoxName),
    ]);

    debugPrint("[INIT_ISOLATE] Hive boxes opened successfully (SyncQueue only)");

    // 3. Inicializar cache HTTP
    await ApiCacheManager.initialize();

    debugPrint("[INIT_ISOLATE] ApiCacheManager initialized");

    // 4. Setup Service Locator
    await setupLocator();

    debugPrint("[INIT_ISOLATE] Service Locator configured successfully");

    // 5. ✅ DELTA SYNC: Services habilitados con ObjectBox
    try {
      // ⚠️ NOTA: DeltaSyncService (FCM) deshabilitado - Requiere Firebase
      final lazyLoadingService = getIt<LazyLoadingService>();
      final autoCleanupService = getIt<AutoCleanupService>();

      debugPrint("[INIT_ISOLATE] Initializing ObjectBox services...");

      // Load essential data (indices only)
      await lazyLoadingService.loadEssentialData();

      // Perform daily cleanup if needed
      await autoCleanupService.performDailyCleanup();

      debugPrint("[INIT_ISOLATE] ✅ ObjectBox services initialized successfully");
    } catch (e) {
      debugPrint("[INIT_ISOLATE] ⚠️ ObjectBox initialization failed (non-critical): $e");
      // Non-critical error - app can continue without ObjectBox services
    }

    // 6. ✅ OPTIMIZACIÓN EXTREMA: Services habilitados
    try {
      debugPrint("[INIT_ISOLATE] Initializing Optimization Extrema services...");

      // Image Cache System
      await ImageCacheSystem.instance.initialize();

      // Screen State Service
      final screenStateService = getIt<ScreenStateService>();
      screenStateService.initialize();

      // ❌ Background Sync Service - ELIMINADO (WorkManager removido)
      // El sync en background ahora es manejado por:
      // - UltraOptimizedPollingService (polling inteligente)
      // - SyncManager (cola persistente con reintentos)
      // - BackgroundService (flutter_background_service)

      // Ultra Optimized Polling Service
      final pollingService = getIt<UltraOptimizedPollingService>();
      await pollingService.initialize();
      // Note: pollingService.start() se llama en ScannerScreen o donde sea apropiado

      debugPrint("[INIT_ISOLATE] ✅ Optimization Extrema services initialized");
    } catch (e) {
      debugPrint("[INIT_ISOLATE] ⚠️ Optimization Extrema initialization failed (non-critical): $e");
      // Non-critical error - app can continue
    }

    if (sendPort != null) {
      sendPort.send('SUCCESS');
    }
  } catch (e, stackTrace) {
    debugPrint("[INIT_ISOLATE] ERROR: $e\n$stackTrace");
    if (sendPort != null) {
      sendPort.send('ERROR: $e');
    }
    rethrow;
  }
}

class ErrorMaterialApp extends StatelessWidget {
  final Object error;
  const ErrorMaterialApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "Error Crítico al Iniciar:\n\n$error\n\nPor favor, reinicia la aplicación.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✓ OPTIMIZACIÓN CRÍTICA: main() ahora ejecuta INSTANTÁNEAMENTE
/// La inicialización pesada se hace en el coreServicesProvider (FutureProvider)
/// que es observado por el SplashScreen
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("[MAIN] Starting application - INSTANT LAUNCH MODE");

  // SOLO configuraciones ULTRA-LIGERAS en main()
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await initializeDateFormatting('es_CR', null);
    Intl.defaultLocale = 'es_CR';
  } catch (_) {
    await initializeDateFormatting('es', null);
    Intl.defaultLocale = 'es';
  }

  debugPrint("[MAIN] Launching app instantly (deferred initialization in coreServicesProvider)...");

  // ✓✓✓ CRÍTICO: runApp() ejecuta INMEDIATAMENTE
  // La inicialización pesada (Hive, GetIt, BackgroundService) se hace en el FutureProvider
  runApp(const CoreApp());
}

/// ✓ FASE 2 RIVERPOD: Core app con ProviderScope (MultiProvider removido)
class CoreApp extends StatelessWidget {
  const CoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: MyPosApp(),
    );
  }
}