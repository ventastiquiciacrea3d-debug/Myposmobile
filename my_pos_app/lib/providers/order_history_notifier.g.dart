// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_history_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$orderHistoryHash() => r'a022592bee3622684d3765ef8ea87acd0465d731';

/// ✓ FASE 1 RIVERPOD: Notifier para el historial de órdenes con paginación
/// Reemplaza la parte de historial de OrderProvider
///
/// Copied from [OrderHistory].
@ProviderFor(OrderHistory)
final orderHistoryProvider =
    AutoDisposeNotifierProvider<OrderHistory, OrderHistoryState>.internal(
  OrderHistory.new,
  name: r'orderHistoryProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$orderHistoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$OrderHistory = AutoDisposeNotifier<OrderHistoryState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
