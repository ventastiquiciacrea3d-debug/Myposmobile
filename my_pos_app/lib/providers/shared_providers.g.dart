// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shared_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$coreServicesHash() => r'd0c61d57e37e750da66bd00d9a1bd9bf938cd712';

/// ✓ CORRECCIÓN: FutureProvider para inicialización de servicios core
/// NOTA: No podemos usar Isolate.run() porque Hive.initFlutter() requiere WidgetsBinding
/// que solo está disponible en el isolate principal. Ejecutamos de forma asíncrona normal.
///
/// Copied from [coreServices].
@ProviderFor(coreServices)
final coreServicesProvider = AutoDisposeFutureProvider<void>.internal(
  coreServices,
  name: r'coreServicesProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$coreServicesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CoreServicesRef = AutoDisposeFutureProviderRef<void>;
String _$connectivityServiceHash() =>
    r'48f05cc738a36ab187cb8fef2cf7daca17b0a537';

/// See also [connectivityService].
@ProviderFor(connectivityService)
final connectivityServiceProvider =
    AutoDisposeProvider<ConnectivityService>.internal(
  connectivityService,
  name: r'connectivityServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$connectivityServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ConnectivityServiceRef = AutoDisposeProviderRef<ConnectivityService>;
String _$storageServiceHash() => r'f526d23e704c8e832d676e6c2d15aa61000c0d03';

/// See also [storageService].
@ProviderFor(storageService)
final storageServiceProvider = AutoDisposeProvider<StorageService>.internal(
  storageService,
  name: r'storageServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$storageServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef StorageServiceRef = AutoDisposeProviderRef<StorageService>;
String _$wooCommerceServiceHash() =>
    r'e021f329b526ee6f644f4f8373d9113aa1badc29';

/// See also [wooCommerceService].
@ProviderFor(wooCommerceService)
final wooCommerceServiceProvider =
    AutoDisposeProvider<WooCommerceService>.internal(
  wooCommerceService,
  name: r'wooCommerceServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$wooCommerceServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WooCommerceServiceRef = AutoDisposeProviderRef<WooCommerceService>;
String _$syncManagerHash() => r'd3205cd17e351d126e878533ce1ace9d53e14e21';

/// See also [syncManager].
@ProviderFor(syncManager)
final syncManagerProvider = AutoDisposeProvider<SyncManager>.internal(
  syncManager,
  name: r'syncManagerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$syncManagerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SyncManagerRef = AutoDisposeProviderRef<SyncManager>;
String _$scannerServiceHash() => r'30b7d7982bca31627bc77386366ad961ef9b6e32';

/// See also [scannerService].
@ProviderFor(scannerService)
final scannerServiceProvider = AutoDisposeProvider<ScannerService>.internal(
  scannerService,
  name: r'scannerServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$scannerServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ScannerServiceRef = AutoDisposeProviderRef<ScannerService>;
String _$cacheWarmingServiceHash() =>
    r'80b39098412a71260a12bf572de7e5b3d8ce33e5';

/// ✓ PROPUESTA 1: Cache Warming Service Provider
///
/// Copied from [cacheWarmingService].
@ProviderFor(cacheWarmingService)
final cacheWarmingServiceProvider =
    AutoDisposeProvider<CacheWarmingService>.internal(
  cacheWarmingService,
  name: r'cacheWarmingServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$cacheWarmingServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CacheWarmingServiceRef = AutoDisposeProviderRef<CacheWarmingService>;
String _$circuitBreakerServiceHash() =>
    r'bea86628e0c3865011ed7339813385915d6a8312';

/// ✓ PROPUESTA 4: Circuit Breaker Service Provider
///
/// Copied from [circuitBreakerService].
@ProviderFor(circuitBreakerService)
final circuitBreakerServiceProvider =
    AutoDisposeProvider<CircuitBreakerService>.internal(
  circuitBreakerService,
  name: r'circuitBreakerServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$circuitBreakerServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CircuitBreakerServiceRef
    = AutoDisposeProviderRef<CircuitBreakerService>;
String _$transactionServiceHash() =>
    r'bd4dafbb0339bb0e138945a6f0436f07f54a013a';

/// ✓ PROPUESTA 3: Transaction Service Provider
///
/// Copied from [transactionService].
@ProviderFor(transactionService)
final transactionServiceProvider =
    AutoDisposeProvider<TransactionService>.internal(
  transactionService,
  name: r'transactionServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$transactionServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TransactionServiceRef = AutoDisposeProviderRef<TransactionService>;
String _$databaseServiceHash() => r'279e8aa65a7311ab3da02089a6431a554052f334';

/// ✓ DELTA SYNC: Database Service Provider (ObjectBox)
///
/// Copied from [databaseService].
@ProviderFor(databaseService)
final databaseServiceProvider = AutoDisposeProvider<DatabaseService>.internal(
  databaseService,
  name: r'databaseServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$databaseServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DatabaseServiceRef = AutoDisposeProviderRef<DatabaseService>;
String _$ultraOptimizedPollingServiceHash() =>
    r'5f41565344e9aba774e3db3e81099a444a73db01';

/// 🟢 NUEVO: Ultra Optimized Polling Service Provider (PRIORIDAD 3 + sincronización de inventario externo)
///
/// Copied from [ultraOptimizedPollingService].
@ProviderFor(ultraOptimizedPollingService)
final ultraOptimizedPollingServiceProvider =
    AutoDisposeProvider<UltraOptimizedPollingService>.internal(
  ultraOptimizedPollingService,
  name: r'ultraOptimizedPollingServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$ultraOptimizedPollingServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UltraOptimizedPollingServiceRef
    = AutoDisposeProviderRef<UltraOptimizedPollingService>;
String _$productRepositoryHash() => r'e32050a40236367a2652ee81856d084113ddd206';

/// See also [productRepository].
@ProviderFor(productRepository)
final productRepositoryProvider =
    AutoDisposeProvider<ProductRepository>.internal(
  productRepository,
  name: r'productRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$productRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ProductRepositoryRef = AutoDisposeProviderRef<ProductRepository>;
String _$orderRepositoryHash() => r'791cb9faa38c4443a42ca9b1d8581333ac432c43';

/// See also [orderRepository].
@ProviderFor(orderRepository)
final orderRepositoryProvider = AutoDisposeProvider<OrderRepository>.internal(
  orderRepository,
  name: r'orderRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$orderRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OrderRepositoryRef = AutoDisposeProviderRef<OrderRepository>;
String _$inventoryRepositoryHash() =>
    r'50963abf4c11f05ede30b1a31c51d980cde9ab99';

/// See also [inventoryRepository].
@ProviderFor(inventoryRepository)
final inventoryRepositoryProvider =
    AutoDisposeProvider<InventoryRepository>.internal(
  inventoryRepository,
  name: r'inventoryRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$inventoryRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef InventoryRepositoryRef = AutoDisposeProviderRef<InventoryRepository>;
String _$sharedPreferencesHash() => r'dcbc6c90e9480f0cf0d8be73030691bd31132693';

/// ✓ SharedPreferences provider
/// IMPORTANTE: GetIt ya ha inicializado SharedPreferences de forma asíncrona
/// en setupLocator(). Aquí solo lo obtenemos después de que coreServices esté listo.
///
/// Copied from [sharedPreferences].
@ProviderFor(sharedPreferences)
final sharedPreferencesProvider =
    AutoDisposeProvider<SharedPreferences>.internal(
  sharedPreferences,
  name: r'sharedPreferencesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sharedPreferencesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SharedPreferencesRef = AutoDisposeProviderRef<SharedPreferences>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
