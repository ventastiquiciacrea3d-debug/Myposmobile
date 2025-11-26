// lib/repositories/order_repository.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/order.dart' as model;
import '../services/woocommerce_service.dart';
import '../services/storage_service.dart';
import '../locator.dart';

/// ✓ PROPUESTA 1: model.OrderRepository con patrón SWR (Stale-While-Revalidate) completo
///
/// Mejoras implementadas:
/// 1. ✅ Stream de eventos para notificar actualizaciones desde API
/// 2. ✅ Método getOrderByIdWithSWR() optimizado
/// 3. ✅ Método getOrderHistoryWithSWR() optimizado
/// 4. ✅ Background updates automáticos con cache stale
/// 5. ✅ Fallback a caché en errores de red
class OrderRepository {
  final WooCommerceService _wooCommerceService = getIt<WooCommerceService>();
  final StorageService _storageService = getIt<StorageService>();

  // ✓ PROPUESTA 1: Stream para notificar updates desde API
  final StreamController< model.Order> _orderUpdateController = StreamController< model.Order>.broadcast();
  Stream< model.Order> get onOrderUpdatedFromApi => _orderUpdateController.stream;

  static const Duration orderDetailCacheTTL = Duration(hours: 1);
  static const Duration orderHistoryPageCacheTTL = Duration(minutes: 30);

  OrderRepository() {
    debugPrint("[OrderRepository] ✓ Initialized with SWR pattern (TTL Cache Mode for Orders).");
  }

  /// ✓ PROPUESTA 1: Método SWR optimizado para obtener orden por ID
  /// Retorna caché inmediatamente si existe, actualiza en background si stale
  Future<model.Order?> getOrderByIdWithSWR(
    String orderId, {
    Duration ttlDuration = orderDetailCacheTTL,
  }) async {
    debugPrint("[OrderRepository.getOrderByIdWithSWR] 🔍 Requesting model.Order ID: $orderId (TTL: ${ttlDuration.inHours}h)");

    // Si es orden local, buscar en pending orders
    if (orderId.startsWith('local_')) {
      debugPrint("... 📦 Fetching local pending order $orderId from storage.");
      return _storageService.getPendingOrderById(orderId);
    }

    model.Order? cachedOrder;
    DateTime? cacheTimestamp;

    // Intentar leer de caché
    try {
      cachedOrder = _storageService.getCompletedOrderById(orderId);
      if (cachedOrder != null) {
        cacheTimestamp = _storageService.getOrderCacheTimestamp(orderId);
        debugPrint("... ✅ Cache HIT for model.Order $orderId");
      } else {
        debugPrint("... ❌ Cache MISS for model.Order $orderId");
      }
    } catch (e) {
      debugPrint("... ⚠️ Cache read error for model.Order $orderId: ${e.toString()}");
    }

    // ✓ PROPUESTA 1: Si hay caché válida, retornar inmediatamente
    if (cachedOrder != null && cacheTimestamp != null) {
      final isFresh = DateTime.now().isBefore(cacheTimestamp.add(ttlDuration));

      if (isFresh) {
        debugPrint("... 🟢 [FRESH] Returning cached model.Order $orderId. Triggering background refresh.");
        _fetchAndUpdateOrderInBackground(orderId); // Refresh en background de todas formas
        return cachedOrder;
      } else {
        debugPrint("... 🟡 [STALE] Returning stale cached model.Order $orderId. Triggering background update.");
        _fetchAndUpdateOrderInBackground(orderId); // Actualizar en background
        return cachedOrder;
      }
    }

    // ✓ Cache MISS - Fetch desde API
    try {
      debugPrint("... 📡 Fetching model.Order $orderId from API...");
      final model.Order? apiOrder = await _wooCommerceService.getOrderByIdAPI(orderId);

      if (apiOrder == null) {
        debugPrint("... ⚠️ model.Order $orderId not found on API");
        return cachedOrder; // Retornar caché si existe
      }

      await _storageService.saveCompletedOrder(apiOrder);
      _orderUpdateController.add(apiOrder); // Notificar listeners
      debugPrint("... ✅ model.Order $orderId fetched and cached successfully");

      return apiOrder;
    } on OrderNotFoundException {
      debugPrint("... ❌ model.Order $orderId not found (404)");
      return cachedOrder;
    } on AuthenticationException {
      rethrow;
    } on NetworkException {
      debugPrint("... 🔴 Network error. Falling back to cached model.Order $orderId");
      if (cachedOrder != null) return cachedOrder;
      rethrow;
    } on ApiException {
      debugPrint("... 🔴 API error. Falling back to cached model.Order $orderId");
      if (cachedOrder != null) return cachedOrder;
      rethrow;
    }
  }

  /// ✓ PROPUESTA 1: Background update silencioso para mantener caché fresco
  Future<void> _fetchAndUpdateOrderInBackground(String orderId) async {
    debugPrint("... 🔄 [Background Update] Starting for model.Order $orderId");
    try {
      final model.Order? apiOrder = await _wooCommerceService.getOrderByIdAPI(orderId);
      if (apiOrder != null) {
        await _storageService.saveCompletedOrder(apiOrder);
        _orderUpdateController.add(apiOrder); // Notificar listeners
        debugPrint("... ✅ [Background Update] Cache updated for model.Order $orderId");
      }
    } catch (e) {
      debugPrint("... ⚠️ [Background Update] Failed for model.Order $orderId: ${e.toString()}");
    }
  }

  /// ✓ PROPUESTA 1: Método SWR optimizado para historial de órdenes
  Future<Map<String, dynamic>> getOrderHistoryWithSWR({
    int page = 1,
    int perPage = 20,
    String? searchTerm,
    String? status,
    Duration ttlDuration = orderHistoryPageCacheTTL,
  }) async {
    debugPrint("[OrderRepository.getOrderHistoryWithSWR] 🔍 Page: $page, PerPage: $perPage (TTL: ${ttlDuration.inMinutes}min)");

    List< model.Order> cachedPageOrders = [];
    DateTime? historyPageTimestamp;
    final String historyPageKey = 'order_history_p${page}_s$perPage';

    // Solo cachear página 1 para simplificar
    if (page == 1) {
      try {
        cachedPageOrders = _storageService.getCompletedOrders(limit: perPage);

        if (cachedPageOrders.isNotEmpty) {
          historyPageTimestamp = _storageService.getOrderCacheTimestamp(historyPageKey);

          if (historyPageTimestamp != null) {
            final isFresh = DateTime.now().isBefore(historyPageTimestamp.add(ttlDuration));

            if (isFresh) {
              debugPrint("... 🟢 [FRESH] Returning cached history page 1. Triggering background refresh.");
              _triggerBackgroundOrderHistoryUpdate(page: 1, perPage: perPage, cacheKey: historyPageKey);
              return {'orders': cachedPageOrders, 'total_pages': 1};
            } else {
              debugPrint("... 🟡 [STALE] Returning stale cached history page 1. Triggering background update.");
              _triggerBackgroundOrderHistoryUpdate(page: 1, perPage: perPage, cacheKey: historyPageKey);
              return {'orders': cachedPageOrders, 'total_pages': 1};
            }
          }
        }
      } catch (cacheError) {
        debugPrint("... ⚠️ Error reading cache for history page 1: $cacheError");
      }
    }

    // Fetch desde API
    try {
      debugPrint("... 📡 Fetching model.Order History from API (page $page)...");
      final apiResponse = await _wooCommerceService.getOrderHistory(
        page: page,
        perPage: perPage,
        searchTerm: searchTerm,
        status: status,
      );

      // Cachear timestamp solo para página 1
      if (page == 1 && (apiResponse['orders'] as List).isNotEmpty) {
        await _storageService.setOrderCacheTimestamp(historyPageKey, DateTime.now());
      }

      debugPrint("... ✅ model.Order History fetched successfully (page $page)");
      return apiResponse;
    } on NetworkException {
      debugPrint("... 🔴 Network error. Falling back to cached history");
      if (page == 1 && cachedPageOrders.isNotEmpty) {
        return {'orders': cachedPageOrders, 'total_pages': 1};
      }
      rethrow;
    } on AuthenticationException {
      rethrow;
    } on ApiException {
      debugPrint("... 🔴 API error. Falling back to cached history");
      if (page == 1 && cachedPageOrders.isNotEmpty) {
        return {'orders': cachedPageOrders, 'total_pages': 1};
      }
      rethrow;
    }
  }

  /// ✓ PROPUESTA 1: Background update para historial
  Future<void> _triggerBackgroundOrderHistoryUpdate({
    required int page,
    required int perPage,
    required String cacheKey,
  }) async {
    debugPrint("... 🔄 [Background Update] Starting for model.Order History $cacheKey");
    try {
      final apiResponse = await _wooCommerceService.getOrderHistory(
        page: page,
        perPage: perPage,
      );

      if ((apiResponse['orders'] as List).isNotEmpty) {
        await _storageService.setOrderCacheTimestamp(cacheKey, DateTime.now());
        debugPrint("... ✅ [Background Update] History cache updated");
      }
    } catch (e) {
      debugPrint("... ⚠️ [Background Update] FAILED for model.Order History $cacheKey: ${e.toString()}");
    }
  }

  // ==================== MÉTODOS LEGACY (Backward compatibility) ====================

  /// Método legacy - usa getOrderByIdWithSWR internamente
  Future<model.Order?> getOrderById(
    String orderId, {
    bool forceApi = false,
    Duration ttlDuration = orderDetailCacheTTL,
  }) async {
    if (forceApi) {
      // Si forceApi, hacer fetch directo sin caché
      try {
        final model.Order? apiOrder = await _wooCommerceService.getOrderByIdAPI(orderId);
        if (apiOrder != null) {
          await _storageService.saveCompletedOrder(apiOrder);
        }
        return apiOrder;
      } catch (e) {
        // En error, intentar caché como fallback
        return _storageService.getCompletedOrderById(orderId);
      }
    }

    // Usar método SWR
    return getOrderByIdWithSWR(orderId, ttlDuration: ttlDuration);
  }

  /// Método legacy - usa getOrderHistoryWithSWR internamente
  Future<Map<String, dynamic>> getOrderHistory({
    int page = 1,
    int perPage = 20,
    String? searchTerm,
    String? status,
    Duration ttlDuration = orderHistoryPageCacheTTL,
  }) async {
    return getOrderHistoryWithSWR(
      page: page,
      perPage: perPage,
      searchTerm: searchTerm,
      status: status,
      ttlDuration: ttlDuration,
    );
  }

  // ==================== MÉTODOS CRUD ====================

  Future<String?> createOrder(model.Order order) async {
    try {
      return await _wooCommerceService.createOrderAPI(order);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException("Error inesperado al crear pedido: ${e.toString()}");
    }
  }

  Future<model.Order> updateOrder(model.Order order) async {
    try {
      if (order.id == null || order.id!.isEmpty) {
        throw InvalidDataException("El ID del pedido es necesario para actualizar.");
      }
      return await _wooCommerceService.updateOrderAPI(order);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException("Error inesperado al actualizar pedido: ${e.toString()}");
    }
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await _wooCommerceService.updateOrderStatus(orderId, newStatus);
      _fetchAndUpdateOrderInBackground(orderId);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException("Error inesperado al actualizar estado: ${e.toString()}");
    }
  }

  // ==================== PENDING ORDERS ====================

  Map<String, model.Order> getPendingOrders() {
    return _storageService.getPendingOrders();
  }

  Future<model.Order?> getPendingOrderById(String localId) async {
    return _storageService.getPendingOrderById(localId);
  }

  Future<void> savePendingOrder(model.Order order, String localId) async {
    await _storageService.savePendingOrder(order, localId);
  }

  Future<void> removePendingOrder(String localId) async {
    await _storageService.removePendingOrder(localId);
  }

  // ==================== CACHE MANAGEMENT ====================

  Future<void> clearCompletedOrdersCache() async {
    await _storageService.clearCompletedOrdersCache();
  }

  /// ✓ PROPUESTA 1: Método para invalidar caché de una orden específica
  /// NOTA: Comentado temporalmente - StorageService no tiene deleteOrderCacheTimestamp
  /*
  Future<void> invalidateOrderCache(String orderId) async {
    debugPrint("[OrderRepository] 🗑️ Invalidating cache for model.Order $orderId");
    await _storageService.deleteOrderCacheTimestamp(orderId);
  }
  */

  /// ✓ PROPUESTA 1: Método para pre-cargar órdenes en caché (cache warming)
  Future<void> warmCache({int count = 10}) async {
    debugPrint("[OrderRepository] 🔥 Warming cache with $count recent orders...");
    try {
      final response = await getOrderHistoryWithSWR(page: 1, perPage: count);
      debugPrint("... ✅ Cache warmed with ${(response['orders'] as List).length} orders");
    } catch (e) {
      debugPrint("... ⚠️ Cache warming failed: $e");
    }
  }

  void dispose() {
    _orderUpdateController.close();
    debugPrint("[OrderRepository] Disposed.");
  }
}
