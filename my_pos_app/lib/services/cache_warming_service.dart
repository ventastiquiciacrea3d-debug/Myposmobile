// lib/services/cache_warming_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../repositories/order_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/product_repository.dart';
import '../locator.dart';

/// ✓ PROPUESTA 1: Cache Warming Service - Servicio de precarga de caché
///
/// Responsabilidades:
/// 1. ✅ Coordinar precarga de datos críticos durante app startup
/// 2. ✅ Estrategias configurables (aggressive, moderate, minimal)
/// 3. ✅ Ejecución en background sin bloquear UI
/// 4. ✅ Métricas de tiempo y éxito
/// 5. ✅ Manejo de errores sin detener app startup
enum CacheWarmingStrategy {
  /// Precarga mínima - solo órdenes recientes (5)
  minimal,

  /// Precarga moderada - órdenes (10) + inventario (15)
  moderate,

  /// Precarga agresiva - órdenes (20) + inventario (25) + productos populares
  aggressive,
}

class CacheWarmingService {
  final OrderRepository _orderRepository = getIt<OrderRepository>();
  final InventoryRepository _inventoryRepository = getIt<InventoryRepository>();
  final ProductRepository _productRepository = getIt<ProductRepository>();

  bool _isWarming = false;
  DateTime? _lastWarmingTimestamp;
  Duration? _lastWarmingDuration;
  Map<String, bool> _lastWarmingResults = {};

  bool get isWarming => _isWarming;
  DateTime? get lastWarmingTimestamp => _lastWarmingTimestamp;
  Duration? get lastWarmingDuration => _lastWarmingDuration;
  Map<String, bool> get lastWarmingResults => Map.unmodifiable(_lastWarmingResults);

  CacheWarmingService() {
    debugPrint("[CacheWarmingService] ✓ Initialized.");
  }

  /// Precalentar caché según estrategia seleccionada
  Future<void> warmCache({
    CacheWarmingStrategy strategy = CacheWarmingStrategy.moderate,
  }) async {
    if (_isWarming) {
      debugPrint("[CacheWarmingService] ⏸️ Cache warming already in progress. Skipping.");
      return;
    }

    _isWarming = true;
    _lastWarmingResults.clear();
    final startTime = DateTime.now();

    debugPrint("[CacheWarmingService] 🔥 Starting cache warming with strategy: ${strategy.name}");

    try {
      switch (strategy) {
        case CacheWarmingStrategy.minimal:
          await _warmMinimal();
          break;
        case CacheWarmingStrategy.moderate:
          await _warmModerate();
          break;
        case CacheWarmingStrategy.aggressive:
          await _warmAggressive();
          break;
      }

      _lastWarmingTimestamp = DateTime.now();
      _lastWarmingDuration = _lastWarmingTimestamp!.difference(startTime);

      final successCount = _lastWarmingResults.values.where((v) => v).length;
      final totalCount = _lastWarmingResults.length;

      debugPrint("[CacheWarmingService] ✅ Cache warming completed. "
          "Success: $successCount/$totalCount, "
          "Duration: ${_lastWarmingDuration!.inMilliseconds}ms");
    } catch (e) {
      debugPrint("[CacheWarmingService] ⚠️ Cache warming failed: $e");
    } finally {
      _isWarming = false;
    }
  }

  /// Estrategia MINIMAL: Solo órdenes recientes
  Future<void> _warmMinimal() async {
    debugPrint("... 📦 [MINIMAL] Warming orders (5)");
    await _warmOrders(count: 5);
  }

  /// Estrategia MODERATE: Órdenes + Inventario
  Future<void> _warmModerate() async {
    debugPrint("... 📦 [MODERATE] Warming orders (10) + inventory (15)");

    // Ejecutar en paralelo para mejor performance
    await Future.wait([
      _warmOrders(count: 10),
      _warmInventory(count: 15),
    ]);
  }

  /// Estrategia AGGRESSIVE: Órdenes + Inventario + Productos
  Future<void> _warmAggressive() async {
    debugPrint("... 📦 [AGGRESSIVE] Warming orders (20) + inventory (25) + products");

    // Ejecutar en paralelo para mejor performance
    await Future.wait([
      _warmOrders(count: 20),
      _warmInventory(count: 25),
      _warmProducts(),
    ]);
  }

  /// Precalentar órdenes
  Future<void> _warmOrders({required int count}) async {
    try {
      await _orderRepository.warmCache(count: count);
      _lastWarmingResults['orders'] = true;
      debugPrint("... ✅ Orders cache warmed successfully");
    } catch (e) {
      _lastWarmingResults['orders'] = false;
      debugPrint("... ❌ Orders cache warming failed: $e");
    }
  }

  /// Precalentar inventario
  Future<void> _warmInventory({required int count}) async {
    try {
      await _inventoryRepository.warmCache(count: count);
      _lastWarmingResults['inventory'] = true;
      debugPrint("... ✅ Inventory cache warmed successfully");
    } catch (e) {
      _lastWarmingResults['inventory'] = false;
      debugPrint("... ❌ Inventory cache warming failed: $e");
    }
  }

  /// Precalentar productos (buscar caché de productos más populares)
  Future<void> _warmProducts() async {
    try {
      // Intentar precalentar algunos productos comunes desde caché
      // (ProductRepository ya tiene SWR implementado)
      debugPrint("... 🔍 Warming product search cache");

      // Simplemente hacer una búsqueda vacía para triggear cache warming
      await _productRepository.searchProductsByTerm('', limit: 20);

      _lastWarmingResults['products'] = true;
      debugPrint("... ✅ Products cache warmed successfully");
    } catch (e) {
      _lastWarmingResults['products'] = false;
      debugPrint("... ❌ Products cache warming failed: $e");
    }
  }

  /// Invalidar todos los cachés
  Future<void> invalidateAllCaches() async {
    debugPrint("[CacheWarmingService] 🗑️ Invalidating all caches");
    try {
      await Future.wait([
        _orderRepository.clearCompletedOrdersCache(),
        _inventoryRepository.invalidateInventoryCache(),
      ]);
      debugPrint("... ✅ All caches invalidated successfully");
    } catch (e) {
      debugPrint("... ⚠️ Cache invalidation failed: $e");
    }
  }

  /// Obtener estadísticas de último warming
  Map<String, dynamic> getWarmingStatistics() {
    return {
      'isWarming': _isWarming,
      'lastWarmingTimestamp': _lastWarmingTimestamp?.toIso8601String(),
      'lastWarmingDurationMs': _lastWarmingDuration?.inMilliseconds,
      'lastWarmingResults': _lastWarmingResults,
      'successRate': _lastWarmingResults.isEmpty
          ? 0.0
          : _lastWarmingResults.values.where((v) => v).length / _lastWarmingResults.length,
    };
  }

  void dispose() {
    debugPrint("[CacheWarmingService] Disposed.");
  }
}
