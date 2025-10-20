// lib/repositories/order_repository.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../services/woocommerce_service.dart';
import '../services/storage_service.dart';
import '../locator.dart';

class OrderRepository {
  final WooCommerceService _wooCommerceService = getIt<WooCommerceService>();
  final StorageService _storageService = getIt<StorageService>();

  static const Duration orderDetailCacheTTL = Duration(hours: 1);
  static const Duration orderHistoryPageCacheTTL = Duration(minutes: 30);

  OrderRepository() {
    debugPrint("[OrderRepository] Initialized (TTL Cache Mode for Orders).");
  }

  Future<Order?> getOrderById(
      String orderId, {
        bool forceApi = false,
        Duration ttlDuration = orderDetailCacheTTL,
      }) async {
    debugPrint("[OrderRepository.getOrderById] Requesting Order ID: $orderId (forceApi: $forceApi, TTL: ${ttlDuration.inHours} hr)");

    if (orderId.startsWith('local_')) {
      debugPrint("... Attempting to fetch local pending order $orderId from storage.");
      return _storageService.getPendingOrderById(orderId);
    }

    Order? cachedOrder;
    DateTime? cacheTimestamp;

    if (!forceApi) {
      try {
        cachedOrder = _storageService.getCompletedOrderById(orderId);
        if (cachedOrder != null) {
          cacheTimestamp = _storageService.getOrderCacheTimestamp(orderId);
        } else {
          debugPrint("... Cache MISS for Order $orderId.");
        }
      } catch (e) {
        debugPrint("... Cache read error for Order $orderId: ${e.toString()}");
      }

      if (cachedOrder != null && cacheTimestamp != null && DateTime.now().isBefore(cacheTimestamp.add(ttlDuration))) {
        debugPrint("... [Cache HIT - Valid TTL] Returning cached Order $orderId immediately.");
        _fetchAndUpdateOrderInBackground(orderId);
        return cachedOrder;
      }
      else if (cachedOrder != null) {
        debugPrint("... [Cache HIT - STALE] Returning stale cached Order $orderId. Triggering background update.");
        _fetchAndUpdateOrderInBackground(orderId);
        return cachedOrder;
      }
    } else {
      debugPrint("... [Force API] Skipping cache check for Order $orderId.");
    }

    try {
      final Order? apiOrder = await _wooCommerceService.getOrderByIdAPI(orderId);
      if (apiOrder == null) {
        if (forceApi && cachedOrder != null) return cachedOrder;
        return null;
      }
      await _storageService.saveCompletedOrder(apiOrder);
      return apiOrder;
    } on OrderNotFoundException {
      if (forceApi && cachedOrder != null) return cachedOrder;
      return null;
    } on AuthenticationException { rethrow;
    } on NetworkException {
      if (cachedOrder != null) return cachedOrder;
      rethrow;
    } on ApiException {
      if (cachedOrder != null) return cachedOrder;
      rethrow;
    }
  }

  Future<void> _fetchAndUpdateOrderInBackground(String orderId) async {
    debugPrint("... [Background Update] Starting for Order $orderId");
    try {
      final Order? apiOrder = await _wooCommerceService.getOrderByIdAPI(orderId);
      if (apiOrder != null) {
        await _storageService.saveCompletedOrder(apiOrder);
        debugPrint("... [Background Update] Cache updated for Order $orderId.");
      }
    } catch (e) {
      debugPrint("... [Background Update] Failed for Order $orderId: ${e.toString()}");
    }
  }

  Future<Map<String, dynamic>> getOrderHistory({
    int page = 1,
    int perPage = 20,
    String? searchTerm,
    String? status,
    Duration ttlDuration = orderHistoryPageCacheTTL,
  }) async {
    debugPrint("[OrderRepository.getOrderHistory] Requesting Page: $page, PerPage: $perPage (TTL: ${ttlDuration.inMinutes} min)");
    List<Order> cachedPageOrders = [];
    DateTime? historyPageTimestamp;
    final String historyPageKey = 'order_history_p${page}_s${perPage}';

    if (page == 1) {
      try {
        cachedPageOrders = _storageService.getCompletedOrders(limit: perPage);
        if (cachedPageOrders.isNotEmpty) {
          historyPageTimestamp = _storageService.getOrderCacheTimestamp(historyPageKey);
          if (historyPageTimestamp != null && DateTime.now().isBefore(historyPageTimestamp.add(ttlDuration))) {
            _triggerBackgroundOrderHistoryUpdate(page: 1, perPage: perPage, cacheKey: historyPageKey);
            return {'orders': cachedPageOrders, 'total_pages': 1}; // Asumimos una página si solo hay caché
          } else if (historyPageTimestamp != null) {
            _triggerBackgroundOrderHistoryUpdate(page: 1, perPage: perPage, cacheKey: historyPageKey);
            return {'orders': cachedPageOrders, 'total_pages': 1};
          }
        }
      } catch (cacheError) {
        debugPrint("[OrderRepository] Error reading cache for history page 1: $cacheError.");
      }
    }

    try {
      final apiResponse = await _wooCommerceService.getOrderHistory(page: page, perPage: perPage, searchTerm: searchTerm, status: status);
      if (page == 1 && (apiResponse['orders'] as List).isNotEmpty) {
        await _storageService.setOrderCacheTimestamp(historyPageKey, DateTime.now());
      }
      return apiResponse;
    } on NetworkException {
      if (page == 1 && cachedPageOrders.isNotEmpty) return {'orders': cachedPageOrders, 'total_pages': 1};
      rethrow;
    } on AuthenticationException { rethrow;
    } on ApiException {
      if (page == 1 && cachedPageOrders.isNotEmpty) return {'orders': cachedPageOrders, 'total_pages': 1};
      rethrow;
    }
  }


  Future<void> _triggerBackgroundOrderHistoryUpdate({required int page, required int perPage, required String cacheKey}) async {
    debugPrint("... [Background Update] Starting for Order History $cacheKey");
    try {
      final apiResponse = await _wooCommerceService.getOrderHistory(page: page, perPage: perPage);
      if ((apiResponse['orders'] as List).isNotEmpty) {
        await _storageService.setOrderCacheTimestamp(cacheKey, DateTime.now());
      }
    } catch (e) {
      debugPrint("... [Background Update] FAILED for Order History $cacheKey: ${e.toString()}");
    }
  }

  Future<String?> createOrder(Order order) async {
    try {
      return await _wooCommerceService.createOrderAPI(order);
    } on ApiException { rethrow;
    } catch (e) {
      throw ApiException("Error inesperado al crear pedido: ${e.toString()}");
    }
  }

  // --- INICIO DE LA MODIFICACIÓN ---
  Future<Order> updateOrder(Order order) async {
    try {
      if (order.id == null || order.id!.isEmpty) {
        throw InvalidDataException("El ID del pedido es necesario para actualizar.");
      }
      return await _wooCommerceService.updateOrderAPI(order);
    } on ApiException { rethrow;
    } catch (e) {
      throw ApiException("Error inesperado al actualizar pedido: ${e.toString()}");
    }
  }
  // --- FIN DE LA MODIFICACIÓN ---

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await _wooCommerceService.updateOrderStatus(orderId, newStatus);
      _fetchAndUpdateOrderInBackground(orderId);
    } on ApiException { rethrow;
    } catch (e) {
      throw ApiException("Error inesperado al actualizar estado: ${e.toString()}");
    }
  }

  Map<String, Order> getPendingOrders() {
    return _storageService.getPendingOrders();
  }

  Future<Order?> getPendingOrderById(String localId) async {
    return _storageService.getPendingOrderById(localId);
  }

  Future<void> savePendingOrder(Order order, String localId) async {
    await _storageService.savePendingOrder(order, localId);
  }

  Future<void> removePendingOrder(String localId) async {
    await _storageService.removePendingOrder(localId);
  }

  Future<void> clearCompletedOrdersCache() async {
    await _storageService.clearCompletedOrdersCache();
  }

  void dispose() {
    debugPrint("[OrderRepository] Disposed.");
  }
}