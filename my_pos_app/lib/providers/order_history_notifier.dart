// lib/providers/order_history_notifier.dart
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/order.dart';
import '../repositories/order_repository.dart';
import '../config/constants.dart';
import 'order_state.dart';
import 'shared_providers.dart';

part 'order_history_notifier.g.dart';

/// ✓ FASE 1 RIVERPOD: Notifier para el historial de órdenes con paginación
/// Reemplaza la parte de historial de OrderProvider
@riverpod
class OrderHistory extends _$OrderHistory {
  late OrderRepository _orderRepository;

  @override
  OrderHistoryState build() {
    debugPrint("[OrderHistory] build() called - Initializing");

    _orderRepository = ref.read(orderRepositoryProvider);

    return OrderHistoryState.initial();
  }

  /// Obtener historial de órdenes con paginación
  Future<void> getOrderHistory({
    String? searchTerm,
    String? status,
    bool refresh = false,
  }) async {
    // Evitar llamadas concurrentes
    if ((state.isLoading || state.isLoadingMore) && !refresh) return;

    if (refresh) {
      state = OrderHistoryState.refresh();
    } else {
      if (state.currentPage == 1) {
        state = OrderHistoryState.loading(state);
      } else {
        state = OrderHistoryState.loadingMore(state);
      }
    }

    try {
      final response = await _orderRepository.getOrderHistory(
        page: state.currentPage,
        perPage: 20,
      );

      final List<Order> newOrders = response['orders'];
      final int totalPages = response['total_pages'];

      List<Order> updatedOrders = List.from(state.orders);

      if (refresh || state.currentPage == 1) {
        // Incluir órdenes pendientes locales
        final List<Order> pendingOrders = _orderRepository
            .getPendingOrders()
            .values
            .where((o) => o.id != hiveCurrentOrderPendingKey)
            .toList();

        updatedOrders = [...pendingOrders];
      }

      // Evitar duplicados
      for (var newOrder in newOrders) {
        if (!updatedOrders.any((o) => o.id == newOrder.id)) {
          updatedOrders.add(newOrder);
        }
      }

      // Ordenar por fecha descendente
      updatedOrders.sort((a, b) => b.date.compareTo(a.date));

      final canLoadMore = state.currentPage < totalPages;

      state = OrderHistoryState(
        orders: updatedOrders,
        currentPage: canLoadMore ? state.currentPage + 1 : state.currentPage,
        totalPages: totalPages,
        isLoading: false,
        isLoadingMore: false,
        canLoadMore: canLoadMore,
        error: null,
      );
    } catch (e) {
      debugPrint("[OrderHistory] Error loading history: $e");
      state = OrderHistoryState.error(state, e.toString());
    }
  }

  /// Limpiar historial y reiniciar paginación
  void clear() {
    state = OrderHistoryState.initial();
  }
}
