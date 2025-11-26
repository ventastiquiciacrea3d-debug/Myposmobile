// lib/providers/order_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';
import '../models/order.dart';

part 'order_state.freezed.dart';

/// ✓ FASE 1 RIVERPOD: Estado inmutable para la orden actual
/// Reemplaza las propiedades mutables de OrderProvider
@freezed
class CurrentOrderState with _$CurrentOrderState {
  const factory CurrentOrderState({
    Order? order,
    @Default(false) bool isLoading,
    @Default(false) bool isSaving,
    String? error,
    @Default(0.13) double taxRate,
    @Default(true) bool allowIndividualDiscounts,
  }) = _CurrentOrderState;

  const CurrentOrderState._();

  /// Factory para estado inicial
  factory CurrentOrderState.initial({
    required double taxRate,
    required bool allowIndividualDiscounts,
  }) {
    return CurrentOrderState(
      order: null,
      isLoading: false,
      isSaving: false,
      error: null,
      taxRate: taxRate,
      allowIndividualDiscounts: allowIndividualDiscounts,
    );
  }

  /// Factory para estado con error
  factory CurrentOrderState.error(CurrentOrderState state, String error) {
    return state.copyWith(
      error: error,
      isLoading: false,
      isSaving: false,
    );
  }

  /// Factory para estado cargando
  factory CurrentOrderState.loading(CurrentOrderState state) {
    return state.copyWith(
      isLoading: true,
      error: null,
    );
  }

  /// Factory para estado guardando
  factory CurrentOrderState.saving(CurrentOrderState state) {
    return state.copyWith(
      isSaving: true,
      error: null,
    );
  }
}

/// ✓ FASE 1 RIVERPOD: Estado inmutable para el historial de órdenes con paginación
/// Reemplaza las propiedades mutables de historial en OrderProvider
@freezed
class OrderHistoryState with _$OrderHistoryState {
  const factory OrderHistoryState({
    @Default([]) List<Order> orders,
    @Default(1) int currentPage,
    @Default(1) int totalPages,
    @Default(false) bool isLoading,
    @Default(false) bool isLoadingMore,
    @Default(true) bool canLoadMore,
    String? error,
  }) = _OrderHistoryState;

  const OrderHistoryState._();

  /// Factory para estado inicial
  factory OrderHistoryState.initial() {
    return const OrderHistoryState(
      orders: [],
      currentPage: 1,
      totalPages: 1,
      isLoading: false,
      isLoadingMore: false,
      canLoadMore: true,
      error: null,
    );
  }

  /// Factory para estado cargando página inicial
  factory OrderHistoryState.loading(OrderHistoryState state) {
    return state.copyWith(
      isLoading: true,
      error: null,
    );
  }

  /// Factory para estado cargando más páginas
  factory OrderHistoryState.loadingMore(OrderHistoryState state) {
    return state.copyWith(
      isLoadingMore: true,
      error: null,
    );
  }

  /// Factory para estado con error
  factory OrderHistoryState.error(OrderHistoryState state, String error) {
    return state.copyWith(
      error: error,
      isLoading: false,
      isLoadingMore: false,
    );
  }

  /// Factory para refresh (reinicio de paginación)
  factory OrderHistoryState.refresh() {
    return const OrderHistoryState(
      orders: [],
      currentPage: 1,
      totalPages: 1,
      isLoading: true,
      isLoadingMore: false,
      canLoadMore: true,
      error: null,
    );
  }
}

/// ✓ FASE 1 RIVERPOD: Data class inmutable para el resumen de orden
/// Reemplaza OrderSummaryData con freezed
@freezed
class OrderSummary with _$OrderSummary {
  const factory OrderSummary({
    required double subtotal,
    required double wcDiscount,
    required double manualDiscount,
    required double tax,
    required double total,
    required double taxRate,
  }) = _OrderSummary;

  const OrderSummary._();

  /// Factory para calcular desde una orden
  factory OrderSummary.fromOrder(Order order, double taxRate) {
    double subtotalBase = 0;
    double subtotalAfterWcDiscounts = 0;
    double totalManualDiscountApplied = 0;

    for (OrderItem item in order.items) {
      subtotalBase += (item.regularPrice ?? item.price) * item.quantity;
      subtotalAfterWcDiscounts += item.price * item.quantity;
      totalManualDiscountApplied += item.individualDiscount ?? 0.0;
    }

    final double wcItemDiscountsTotal = (subtotalBase - subtotalAfterWcDiscounts).clamp(0.0, double.infinity);
    final double subtotalForTaxCalculation = (subtotalAfterWcDiscounts - totalManualDiscountApplied).clamp(0.0, double.infinity);
    final double tax = subtotalForTaxCalculation * taxRate;
    final double total = (subtotalForTaxCalculation + tax).clamp(0.0, double.infinity);

    return OrderSummary(
      subtotal: subtotalBase,
      wcDiscount: wcItemDiscountsTotal,
      manualDiscount: totalManualDiscountApplied,
      tax: tax,
      total: total,
      taxRate: taxRate,
    );
  }

  /// Factory para estado vacío
  factory OrderSummary.empty(double taxRate) {
    return OrderSummary(
      subtotal: 0,
      wcDiscount: 0,
      manualDiscount: 0,
      tax: 0,
      total: 0,
      taxRate: taxRate,
    );
  }
}
