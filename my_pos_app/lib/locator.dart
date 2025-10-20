// lib/locator.dart
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_pos_mobile_barcode/models/inventory_adjustment_cache.dart';
import 'package:my_pos_mobile_barcode/models/inventory_movement.dart';
import 'package:my_pos_mobile_barcode/models/label_print_item.dart';
import 'package:my_pos_mobile_barcode/models/order.dart';
import 'package:my_pos_mobile_barcode/models/product.dart';
import 'package:my_pos_mobile_barcode/models/sync_operation.dart';
import 'package:my_pos_mobile_barcode/services/scanner_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repositories/inventory_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/product_repository.dart';
import 'services/connectivity_service.dart';
import 'services/csv_service.dart';
import 'services/storage_service.dart';
import 'services/sync_manager.dart';
import 'services/woocommerce_service.dart';

final getIt = GetIt.instance;

/// Función pública para registrar todos los adaptadores de Hive.
/// Puede ser llamada desde el hilo principal y desde el servicio de fondo.
void registerHiveAdapters() {
  try {
    // Se usa un try-catch por si un adaptador ya está registrado durante un hot-reload.
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(InventoryMovementTypeAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(InventoryMovementLineAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(InventoryMovementAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(LabelPrintItemAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(InventoryAdjustmentCacheAdapter());
    if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(SyncOperationTypeAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(SyncOperationAdapter());
  } catch (e) {
    debugPrint("[registerHiveAdapters] Advertencia durante registro: $e");
  }
}

/// Inicializador principal para todos los servicios de la aplicación.
Future<void> setupLocator() async {
  // SINGLETONS (Services & Core)
  // Register SharedPreferences first as other services might depend on it.
  getIt.registerSingletonAsync<SharedPreferences>(() async {
    return await SharedPreferences.getInstance();
  });

  // Now, other services can depend on SharedPreferences being ready.
  getIt.registerSingletonAsync<StorageService>(() async {
    // Wait for SharedPreferences to be ready before initializing StorageService
    await getIt.isReady<SharedPreferences>();
    final storageService = StorageService();
    await storageService.init();
    return storageService;
  }, dependsOn: [SharedPreferences]);

  // Make other services depend on StorageService to ensure correct order
  getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService());
  getIt.registerLazySingleton<CsvService>(() => CsvService());

  getIt.registerLazySingleton<WooCommerceService>(() => WooCommerceService(
    storageService: getIt<StorageService>(),
    connectivityService: getIt<ConnectivityService>(),
  ));

  // Se registra el ScannerService que faltaba.
  getIt.registerLazySingleton<ScannerService>(() => ScannerService());

  getIt.registerLazySingleton<SyncManager>(() => SyncManager(
    wooCommerceService: getIt<WooCommerceService>(),
    storageService: getIt<StorageService>(),
    connectivityService: getIt<ConnectivityService>(),
  ));

  // REPOSITORIES
  getIt.registerLazySingleton<ProductRepository>(() => ProductRepository());
  getIt.registerLazySingleton<OrderRepository>(() => OrderRepository());
  getIt.registerLazySingleton<InventoryRepository>(() => InventoryRepository());

  // Ensure all async singletons are ready before proceeding
  await getIt.allReady();
}


/// Inicializador ligero SOLO para el servicio de fondo.
/// Registra únicamente lo necesario para que la sincronización funcione en un Isolate.
Future<void> setupBackgroundLocator() async {
  // Asegura que las dependencias se registren solo una vez.
  if (!getIt.isRegistered<SharedPreferences>()) {
    getIt.registerSingletonAsync<SharedPreferences>(() async {
      return await SharedPreferences.getInstance();
    });
  }

  if (!getIt.isRegistered<StorageService>()) {
    getIt.registerSingletonAsync<StorageService>(() async {
      await getIt.isReady<SharedPreferences>();
      final storageService = StorageService();
      await storageService.init();
      return storageService;
    }, dependsOn: [SharedPreferences]);
  }

  if (!getIt.isRegistered<ConnectivityService>()) {
    getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService());
  }

  if (!getIt.isRegistered<WooCommerceService>()) {
    getIt.registerLazySingleton<WooCommerceService>(() => WooCommerceService(
      storageService: getIt<StorageService>(),
      connectivityService: getIt<ConnectivityService>(),
    ));
  }

  if (!getIt.isRegistered<SyncManager>()) {
    getIt.registerLazySingleton<SyncManager>(() => SyncManager(
      wooCommerceService: getIt<WooCommerceService>(),
      storageService: getIt<StorageService>(),
      connectivityService: getIt<ConnectivityService>(),
    ));
  }

  // Wait for async singletons in the background isolate
  await getIt.allReady();
}