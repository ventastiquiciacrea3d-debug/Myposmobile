// lib/providers/customer_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

part 'customer_state.freezed.dart';

/// ✓ FASE 2 RIVERPOD: Estado inmutable para Customer
@freezed
class CustomerState with _$CustomerState {
  const factory CustomerState({
    @Default([]) List<Map<String, dynamic>> recentCustomers,
    @Default([]) List<Map<String, dynamic>> searchResults,
    @Default(false) bool isLoadingRecents,
    @Default(false) bool isLoadingSearch,
    String? error,
    String? selectedCustomerId,
    @Default('Cliente General') String selectedCustomerName,
    @Default('') String currentSearchQuery,
    @Default(false) bool initialRecentsLoaded,
  }) = _CustomerState;

  const CustomerState._();

  factory CustomerState.initial() => const CustomerState();

  /// Clientes a mostrar: últimos 10 recientes si no hay búsqueda, resultados de búsqueda si hay query
  List<Map<String, dynamic>> get displayCustomers =>
      currentSearchQuery.isEmpty ? recentCustomers : searchResults;

  bool get isLoading =>
      currentSearchQuery.isEmpty ? isLoadingRecents : isLoadingSearch;
}
