// lib/providers/customer_notifier.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/woocommerce_service.dart';
import 'customer_state.dart';
import 'shared_providers.dart';

part 'customer_notifier.g.dart';

/// ✓ FASE 2 RIVERPOD: Customer Notifier
@riverpod
class Customer extends _$Customer {
  late WooCommerceService _wooCommerceService;
  Timer? _searchDebounce;

  @override
  CustomerState build() {
    debugPrint("[Customer] build() called - Initializing");

    _wooCommerceService = ref.read(wooCommerceServiceProvider);

    ref.onDispose(() {
      debugPrint("[Customer] Disposing");
      _searchDebounce?.cancel();
    });

    // ✓ CORRECCIÓN RACE CONDITION: Diferir la carga de clientes después de build()
    // para prevenir el error "Tried to read the state of an uninitialized provider"
    Future.microtask(() {
      _fetchRecentCustomers();
    });

    return CustomerState.initial();
  }

  Future<void> _fetchRecentCustomers() async {
    if (state.isLoadingRecents || state.initialRecentsLoaded) {
      return;
    }

    state = state.copyWith(isLoadingRecents: true, error: null);

    try {
      debugPrint("[Customer] Fetching recent customers...");
      final customers = await _wooCommerceService.getCustomers(
        perPage: 10,
        orderBy: 'registered_date',
        order: 'desc',
      );

      state = state.copyWith(
        recentCustomers: customers,
        initialRecentsLoaded: true,
        error: null,
        isLoadingRecents: false,
      );

      debugPrint("... Recent customers loaded: ${customers.length}");
    } on NetworkException catch (e) {
      state = state.copyWith(
        error: "Error de red al cargar clientes: ${e.message}",
        recentCustomers: [],
        initialRecentsLoaded: false,
        isLoadingRecents: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        error: "Error API al cargar clientes: ${e.message}",
        recentCustomers: [],
        initialRecentsLoaded: false,
        isLoadingRecents: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: "Error inesperado al cargar recientes: ${e.toString()}",
        recentCustomers: [],
        initialRecentsLoaded: false,
        isLoadingRecents: false,
      );
    }
  }

  void searchCustomers(String query) {
    final trimmedQuery = query.trim();
    _searchDebounce?.cancel();

    state = state.copyWith(currentSearchQuery: trimmedQuery);

    if (trimmedQuery.isEmpty) {
      state = state.copyWith(
        searchResults: [],
        isLoadingSearch: false,
        error: null,
      );
      return;
    }

    if (trimmedQuery.length < 3) {
      state = state.copyWith(
        searchResults: [],
        isLoadingSearch: false,
        error: "Ingresa al menos 3 caracteres para buscar.",
      );
      return;
    }

    state = state.copyWith(isLoadingSearch: true, error: null);

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (state.currentSearchQuery == trimmedQuery) {
        _performApiSearch(trimmedQuery);
      }
    });
  }

  Future<void> _performApiSearch(String query) async {
    state = state.copyWith(isLoadingSearch: true, error: null);

    List<Map<String, dynamic>> results = [];
    String? searchError;

    try {
      final keywords =
          query.toLowerCase().split(' ').where((s) => s.isNotEmpty).toList();
      final primaryKeyword = keywords.length > 1
          ? (keywords..sort((a, b) => b.length.compareTo(a.length))).first
          : query;

      final apiResults =
          await _wooCommerceService.searchCustomersAPI(primaryKeyword);

      if (keywords.length > 1) {
        results = apiResults.where((customer) {
          final searchableText =
              '${customer['first_name'] ?? ''} ${customer['last_name'] ?? ''} ${customer['email'] ?? ''}'
                  .toLowerCase();
          return keywords.every((keyword) => searchableText.contains(keyword));
        }).toList();
      } else {
        results = apiResults;
      }
      searchError = null;
    } on NetworkException catch (e) {
      searchError = "Error de red al buscar clientes: ${e.message}";
    } on ApiException catch (e) {
      searchError = "Error API al buscar clientes: ${e.message}";
    } catch (e) {
      searchError = "Error inesperado en búsqueda: ${e.toString()}";
    }

    if (state.currentSearchQuery == query) {
      state = state.copyWith(
        searchResults: results,
        error: searchError,
        isLoadingSearch: false,
      );
    }
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    state = state.copyWith(
      currentSearchQuery: '',
      searchResults: [],
      isLoadingSearch: false,
      error: null,
    );
  }

  void selectCustomer(String? customerId, String customerName) {
    final effectiveName =
        customerName.isNotEmpty ? customerName : 'Cliente General';

    if (state.selectedCustomerId != customerId ||
        state.selectedCustomerName != effectiveName) {
      state = state.copyWith(
        selectedCustomerId: customerId,
        selectedCustomerName: effectiveName,
      );

      debugPrint(
          "[Customer] Customer selected - ID: $customerId, Name: $effectiveName");
      clearSearch();
    }
  }

  void clearSelectedCustomer() {
    selectCustomer(null, 'Cliente General');
  }

  Future<void> refreshRecentCustomers() async {
    debugPrint("[Customer] Refreshing recent customers...");
    state = state.copyWith(initialRecentsLoaded: false);
    await _fetchRecentCustomers();
  }
}
