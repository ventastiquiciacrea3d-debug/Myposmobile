// lib/models/ui_state.dart
import 'package:flutter/foundation.dart';
import 'order.dart';
import 'inventory_movement.dart';
import 'product.dart';

/// ✓ OPTIMIZADO: Clases de estado inmutable para uso con Selector
///
/// Estas clases encapsulan solo el estado necesario para renderizar
/// ListViews específicos, evitando rebuilds innecesarios cuando cambian
/// otras partes del provider.
///
/// Beneficios:
/// - Menos rebuilds de widgets (solo cuando cambia el estado relevante)
/// - Mejor performance en listas largas (> 20 items)
/// - Separación clara de responsabilidades

/// Estado para ListView de historial de pedidos
@immutable
class OrderListState {
  final List<Order> orders;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const OrderListState({
    required this.orders,
    required this.isLoading,
    required this.isLoadingMore,
    this.error,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderListState &&
          runtimeType == other.runtimeType &&
          listEquals(orders, other.orders) &&
          isLoading == other.isLoading &&
          isLoadingMore == other.isLoadingMore &&
          error == other.error;

  @override
  int get hashCode =>
      orders.hashCode ^
      isLoading.hashCode ^
      isLoadingMore.hashCode ^
      (error?.hashCode ?? 0);

  @override
  String toString() {
    return 'OrderListState(orders: ${orders.length}, isLoading: $isLoading, isLoadingMore: $isLoadingMore, error: $error)';
  }
}

/// Estado para ListView de movimientos de inventario
@immutable
class InventoryMovementListState {
  final List<InventoryMovement> movements;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const InventoryMovementListState({
    required this.movements,
    required this.isLoading,
    required this.isLoadingMore,
    this.error,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryMovementListState &&
          runtimeType == other.runtimeType &&
          listEquals(movements, other.movements) &&
          isLoading == other.isLoading &&
          isLoadingMore == other.isLoadingMore &&
          error == other.error;

  @override
  int get hashCode =>
      movements.hashCode ^
      isLoading.hashCode ^
      isLoadingMore.hashCode ^
      (error?.hashCode ?? 0);

  @override
  String toString() {
    return 'InventoryMovementListState(movements: ${movements.length}, isLoading: $isLoading, isLoadingMore: $isLoadingMore, error: $error)';
  }
}

/// Estado para ListView de búsqueda de productos
@immutable
class ProductSearchListState {
  final List<Product> results;
  final bool isLoadingMore;
  final bool canLoadMore;

  const ProductSearchListState({
    required this.results,
    required this.isLoadingMore,
    required this.canLoadMore,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductSearchListState &&
          runtimeType == other.runtimeType &&
          listEquals(results, other.results) &&
          isLoadingMore == other.isLoadingMore &&
          canLoadMore == other.canLoadMore;

  @override
  int get hashCode =>
      results.hashCode ^
      isLoadingMore.hashCode ^
      canLoadMore.hashCode;

  @override
  String toString() {
    return 'ProductSearchListState(results: ${results.length}, isLoadingMore: $isLoadingMore, canLoadMore: $canLoadMore)';
  }
}
