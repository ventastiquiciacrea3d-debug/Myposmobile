// lib/providers/shared_providers.dart
// ✓ SOLUCIÓN ARQUITECTÓNICA: Providers compartidos centralizados
//
// Este archivo contiene TODAS las definiciones de providers de servicios,
// repositorios y recursos compartidos que son usados por múltiples notifiers.
//
// IMPORTANTE: Cada provider debe estar definido SOLO UNA VEZ en la aplicación.
// Las definiciones duplicadas causan conflictos en build_runner.

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/woocommerce_service.dart';
import '../services/storage_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_manager.dart';
import '../services/scanner_service.dart';
import '../services/cache_warming_service.dart';
import '../services/circuit_breaker_service.dart';
import '../services/transaction_service.dart';
import '../services/database_service.dart';
import '../services/ultra_optimized_polling_service.dart';
import '../repositories/product_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/inventory_repository.dart';
import '../locator.dart';
import '../main.dart' show initializeCoreServices;

part 'shared_providers.g.dart';

// ==================== CORE INITIALIZATION PROVIDER ====================

/// ✓ CORRECCIÓN: FutureProvider para inicialización de servicios core
/// NOTA: No podemos usar Isolate.run() porque Hive.initFlutter() requiere WidgetsBinding
/// que solo está disponible en el isolate principal. Ejecutamos de forma asíncrona normal.
@riverpod
Future<void> coreServices(CoreServicesRef ref) async {
  debugPrint("[coreServicesProvider] Starting core services initialization...");

  try {
    // Ejecutar directamente en el hilo principal de forma asíncrona
    // Hive requiere acceso a WidgetsFlutterBinding que no está disponible en isolates secundarios
    await initializeCoreServices(null);

    debugPrint("[coreServicesProvider] Core services initialization completed successfully");
  } catch (e, stackTrace) {
    debugPrint("[coreServicesProvider] ERROR during initialization: $e\n$stackTrace");
    rethrow;
  }
}

// ==================== SERVICE PROVIDERS ====================
// Estos providers acceden a servicios registrados en GetIt
// IMPORTANTE: Todos esperan a que coreServicesProvider se complete primero

@riverpod
ConnectivityService connectivityService(ConnectivityServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<ConnectivityService>();
}

@riverpod
StorageService storageService(StorageServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<StorageService>();
}

@riverpod
WooCommerceService wooCommerceService(WooCommerceServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<WooCommerceService>();
}

@riverpod
SyncManager syncManager(SyncManagerRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<SyncManager>();
}

@riverpod
ScannerService scannerService(ScannerServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<ScannerService>();
}

/// ✓ PROPUESTA 1: Cache Warming Service Provider
@riverpod
CacheWarmingService cacheWarmingService(CacheWarmingServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<CacheWarmingService>();
}

/// ✓ PROPUESTA 4: Circuit Breaker Service Provider
@riverpod
CircuitBreakerService circuitBreakerService(CircuitBreakerServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<CircuitBreakerService>();
}

/// ✓ PROPUESTA 3: Transaction Service Provider
@riverpod
TransactionService transactionService(TransactionServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<TransactionService>();
}

/// ✓ DELTA SYNC: Database Service Provider (ObjectBox)
@riverpod
DatabaseService databaseService(DatabaseServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<DatabaseService>();
}

/// 🟢 NUEVO: Ultra Optimized Polling Service Provider (PRIORIDAD 3 + sincronización de inventario externo)
@riverpod
UltraOptimizedPollingService ultraOptimizedPollingService(UltraOptimizedPollingServiceRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<UltraOptimizedPollingService>();
}

// ==================== REPOSITORY PROVIDERS ====================

@riverpod
ProductRepository productRepository(ProductRepositoryRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<ProductRepository>();
}

@riverpod
OrderRepository orderRepository(OrderRepositoryRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<OrderRepository>();
}

@riverpod
InventoryRepository inventoryRepository(InventoryRepositoryRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<InventoryRepository>();
}

// ==================== SHARED RESOURCES ====================

/// ✓ SharedPreferences provider
/// IMPORTANTE: GetIt ya ha inicializado SharedPreferences de forma asíncrona
/// en setupLocator(). Aquí solo lo obtenemos después de que coreServices esté listo.
@riverpod
SharedPreferences sharedPreferences(SharedPreferencesRef ref) {
  // Access GetIt directly - initialization order guaranteed by SplashScreen
  // waiting for coreServicesProvider to complete before using these providers
  return getIt<SharedPreferences>();
}
