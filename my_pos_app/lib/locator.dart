// lib/locator.dart
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_pos_mobile_barcode/models/customer.dart';
import 'package:my_pos_mobile_barcode/models/inventory_adjustment_cache.dart';
import 'package:my_pos_mobile_barcode/models/inventory_movement.dart';
import 'package:my_pos_mobile_barcode/models/label_print_item.dart';
import 'package:my_pos_mobile_barcode/models/order.dart' hide OrderItemAdapter; // ✅ FASE 3: Ocultar OrderItemAdapter de order.dart
import 'package:my_pos_mobile_barcode/models/order_item.dart'; // ✅ FASE 3: Usar OrderItemAdapter de order_item.dart
import 'package:my_pos_mobile_barcode/models/product.dart';
import 'package:my_pos_mobile_barcode/models/sync_operation.dart';
import 'package:my_pos_mobile_barcode/services/scanner_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repositories/inventory_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/product_repository.dart';
import 'services/auto_cleanup_service.dart';
import 'services/cache_warming_service.dart';
import 'services/circuit_breaker_service.dart';
import 'services/connectivity_service.dart';
import 'services/csv_service.dart';
import 'services/database_service.dart';
import 'services/delta_sync_service.dart'; // ✅ V3.1.0: Ahora SIN Firebase
import 'services/feedback_service.dart';
import 'services/lazy_loading_service.dart';
import 'services/storage_service.dart';
import 'services/sync_manager.dart';
import 'services/transaction_service.dart';
import 'services/woocommerce_service.dart';
import 'services/data_migration_service.dart';
import 'services/product_sync_service.dart'; // ✅ Servicio para descargar todos los productos
import 'services/local_search_service.dart'; // ✅ V3: Búsqueda SOLO LOCAL
import 'services/quote_share_service.dart'; // ✅ Servicio para compartir cotizaciones
import 'services/local_database_service.dart'; // ✅ Servicio de base de datos local SQLite
import 'services/customer_manager_service.dart'; // ✅ Servicio de gestión de clientes

// ✅ OPTIMIZACIÓN EXTREMA: Nuevos servicios de batería y almacenamiento
import 'services/event_driven_polling_service.dart';
import 'services/screen_state_service.dart';
// import 'services/background_sync_service.dart';  // ❌ ELIMINADO - WorkManager removido
import 'services/ultra_optimized_polling_service.dart';
import 'utils/attribute_compressor.dart';

final getIt = GetIt.instance;

/// Función pública para registrar adaptadores de Hive.
/// Solo registra adapters para datos que AÚN están en Hive (no migrados a ObjectBox).
void registerHiveAdapters() {
  try {
    // Se usa un try-catch por si un adaptador ya está registrado durante un hot-reload.

    // ❌ MIGRADOS A OBJECTBOX - Ya no se usan (mantener comentado para migración legacy)
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(InventoryMovementAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(LabelPrintItemAdapter());

    // ⚠️ MANTENER TEMPORALMENTE - Usado en DataMigrationService
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(InventoryMovementTypeAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(InventoryMovementLineAdapter());

    // ✅ AÚN EN HIVE - Configuración y sistema
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(InventoryAdjustmentCacheAdapter());
    if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(SyncOperationTypeAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(SyncOperationAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(SyncOperationStatusAdapter());

    // ✅ NUEVOS ADAPTADORES - Customer y OrderItem para pedidos mejorados
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(CustomerAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(OrderItemAdapter());
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

  // ✅ DELTA SYNC: ObjectBox database
  getIt.registerSingletonAsync<DatabaseService>(() async {
    await getIt.isReady<StorageService>();
    return await DatabaseService.getInstance();
  }, dependsOn: [StorageService]);

  // ✅ V3: Local Search Service - Búsqueda SOLO LOCAL (productos/variaciones)
  getIt.registerLazySingleton<LocalSearchService>(() => LocalSearchService(
    storageService: getIt<StorageService>(),
  ));

  // Make other services depend on StorageService to ensure correct order
  getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService());
  getIt.registerLazySingleton<CsvService>(() => CsvService());

  // ✓ PROPUESTA 4: Circuit Breaker Service para protección API
  getIt.registerLazySingleton<CircuitBreakerService>(() => CircuitBreakerService(
    config: const CircuitBreakerConfig(
      failureThreshold: 5,
      resetTimeout: Duration(seconds: 30),
      successThreshold: 2,
      requestTimeout: Duration(seconds: 15),
      failureWindow: Duration(minutes: 1),
    ),
  ));

  // ✓ PROPUESTA 7: Feedback Service para UI feedback visual
  getIt.registerLazySingleton<FeedbackService>(() => FeedbackService());

  // ✓ PROPUESTA 3: Transaction Service para transacciones ACID
  getIt.registerLazySingleton<TransactionService>(() => TransactionService());

  getIt.registerLazySingleton<WooCommerceService>(() => WooCommerceService(
    storageService: getIt<StorageService>(),
    connectivityService: getIt<ConnectivityService>(),
  ));

  // ✅ FASE 2: Local Database Service - Base de datos SQLite para clientes
  getIt.registerLazySingleton<LocalDatabaseService>(() => LocalDatabaseService());

  // ✅ FASE 2: Customer Manager Service - Gestión integrada de clientes
  getIt.registerLazySingleton<CustomerManagerService>(() => CustomerManagerService(
    localDb: getIt<LocalDatabaseService>(),
    wooService: getIt<WooCommerceService>(),
  ));

  // Se registra el ScannerService que faltaba.
  getIt.registerLazySingleton<ScannerService>(() => ScannerService());

  getIt.registerLazySingleton<SyncManager>(() => SyncManager(
    wooCommerceService: getIt<WooCommerceService>(),
    storageService: getIt<StorageService>(),
    connectivityService: getIt<ConnectivityService>(),
    databaseService: getIt<DatabaseService>(),
  ));

  // ✅ DELTA SYNC: Services for optimized product synchronization
  getIt.registerLazySingleton<LazyLoadingService>(() => LazyLoadingService(
    getIt<DatabaseService>(),
  ));

  getIt.registerLazySingleton<AutoCleanupService>(() => AutoCleanupService(
    getIt<DatabaseService>(),
  ));

  // ✅ V3.1.0: DeltaSyncService - Sincronización incremental sin Firebase
  getIt.registerLazySingleton<DeltaSyncService>(() => DeltaSyncService(
    wooService: getIt<WooCommerceService>(),
    storageService: getIt<StorageService>(),
  ));

  // Nota: DeltaSyncService se inicializará de forma lazy cuando se use por primera vez

  // ✅ OPTIMIZACIÓN EXTREMA: Servicios de polling inteligente y batería
  getIt.registerLazySingleton<UltraOptimizedPollingService>(() => UltraOptimizedPollingService(
    wooService: getIt<WooCommerceService>(),
  ));

  getIt.registerLazySingleton<ScreenStateService>(() => ScreenStateService(
    onScreenOff: () => debugPrint('[App] Screen OFF - pausing polling'),
    onScreenOn: () => debugPrint('[App] Screen ON - resuming polling'),
    onScreenUnlocked: () => debugPrint('[App] Screen UNLOCKED - active polling'),
  ));

  getIt.registerLazySingleton<EventDrivenPollingService>(() => EventDrivenPollingService(
    pollingService: getIt<UltraOptimizedPollingService>(),
  ));

  // ❌ BackgroundSyncService - ELIMINADO (WorkManager removido)
  // El sync en background ahora es manejado por UltraOptimizedPollingService + SyncManager

  // ✅ OPTIMIZACIÓN EXTREMA: Utilities
  getIt.registerLazySingleton<AttributeCompressor>(() => AttributeCompressor(
    getIt<DatabaseService>(),
  ));

  // REPOSITORIES
  getIt.registerLazySingleton<ProductRepository>(() => ProductRepository());
  getIt.registerLazySingleton<OrderRepository>(() => OrderRepository());
  getIt.registerLazySingleton<InventoryRepository>(() => InventoryRepository());

  // ✅ PRODUCT SYNC: Servicio para descargar todos los productos de WooCommerce
  getIt.registerLazySingleton<ProductSyncService>(() => ProductSyncService(
    wooService: getIt<WooCommerceService>(),
    productRepo: getIt<ProductRepository>(),
    storageService: getIt<StorageService>(),
  ));

  // ✓ PROPUESTA 1: Cache Warming Service (depende de repositories)
  getIt.registerLazySingleton<CacheWarmingService>(() => CacheWarmingService());

  // ✅ QUOTE SHARE SERVICE: Servicio para compartir cotizaciones en PDF y texto
  getIt.registerSingletonAsync<QuoteShareService>(() async {
    final quoteService = QuoteShareService();
    await quoteService.initialize();
    return quoteService;
  });

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
      await storageService.init(isBackgroundService: true); // ✅ CRÍTICO: Background service NO debe usar ObjectBox
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
      databaseService: null, // ✅ CRÍTICO: El background service NO debe usar ObjectBox
    ));
  }

  // Wait for async singletons in the background isolate
  await getIt.allReady();
}

/// ⚠️ DEPRECADO: DataMigrationService ya no necesita boxes Hive
/// Las migraciones Products, Orders, Labels, Settings ya se completaron
///
/// **Uso:** Solo para ejecutar migración una vez en SplashScreen (ya completado)
DataMigrationService createDataMigrationService() {
  final dbService = getIt<DatabaseService>();

  return DataMigrationService(
    dbService: dbService,
    settingsBox: null,  // ❌ MIGRADO a SharedPreferences - Ya no usa Hive
    productBox: null,  // ❌ MIGRADO a ObjectBox - Ya no usa Hive
    orderBox: null,  // ❌ MIGRADO a ObjectBox - Ya no usa Hive
    pendingOrderBox: null,  // ❌ MIGRADO a ObjectBox - Ya no usa Hive
    labelQueueBox: null,  // ❌ MIGRADO a ObjectBox - Ya no usa Hive
  );
}