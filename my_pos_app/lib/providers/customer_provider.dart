// lib/providers/customer_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/woocommerce_service.dart';
import '../locator.dart';

class CustomerProvider extends ChangeNotifier {
  final WooCommerceService _wooCommerceService = getIt<WooCommerceService>();

  List<Map<String, dynamic>> _recentCustomers = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoadingRecents = false;
  bool _isLoadingSearch = false;
  String? _error;
  Timer? _searchDebounce;
  String? _selectedCustomerId;
  String _selectedCustomerName = 'Cliente General';
  String _currentSearchQuery = '';
  bool _initialRecentsLoaded = false;
  bool _isDisposed = false;

  List<Map<String, dynamic>> get displayCustomers => _currentSearchQuery.isEmpty ? _recentCustomers : _searchResults;
  bool get isLoading => _currentSearchQuery.isEmpty ? _isLoadingRecents : _isLoadingSearch;
  String? get error => _error;
  String? get selectedCustomerId => _selectedCustomerId;
  String get selectedCustomerName => _selectedCustomerName;
  String get currentSearchQuery => _currentSearchQuery;
  bool get initialRecentsLoaded => _initialRecentsLoaded;
  bool get isDisposed => _isDisposed;

  CustomerProvider() {
    debugPrint("[CustomerProvider] Constructor called.");
    _fetchRecentCustomers();
  }

  Future<void> _fetchRecentCustomers() async {
    if (_isDisposed || _isLoadingRecents || _initialRecentsLoaded) {
      if (_isDisposed) debugPrint("[CustomerProvider._fetchRecentCustomers] Provider is disposed.");
      if (_isLoadingRecents) debugPrint("[CustomerProvider._fetchRecentCustomers] Already loading.");
      if (_initialRecentsLoaded) debugPrint("[CustomerProvider._fetchRecentCustomers] Recents already loaded.");
      return;
    }

    _isLoadingRecents = true;
    _error = null;
    if (!_isDisposed) notifyListeners();

    try {
      debugPrint("[CustomerProvider] Fetching recent customers...");
      // --- INICIO DE CORRECCIÓN ---
      final customers = await _wooCommerceService.getCustomers(
          perPage: 10, orderBy: 'registered_date', order: 'desc');
      // --- FIN DE CORRECCIÓN ---

      if (_isDisposed) { debugPrint("[CustomerProvider._fetchRecentCustomers] Disposed after awaiting service."); return; }

      _recentCustomers = customers;
      _initialRecentsLoaded = true;
      _error = null;
      debugPrint("... Recent customers loaded: ${_recentCustomers.length}.");

    } on NetworkException catch (e) {
      if (_isDisposed) return;
      _error = "Error de red al cargar clientes: ${e.message}";
      _recentCustomers = [];
      _initialRecentsLoaded = false;
    } on ApiException catch (e) {
      if (_isDisposed) return;
      _error = "Error API al cargar clientes: ${e.message}";
      _recentCustomers = [];
      _initialRecentsLoaded = false;
    } catch (e) {
      if (_isDisposed) return;
      _error = "Error inesperado al cargar recientes: ${e.toString()}";
      _recentCustomers = [];
      _initialRecentsLoaded = false;
    } finally {
      if (!_isDisposed) {
        _isLoadingRecents = false;
        notifyListeners();
      } else {
        debugPrint("[CustomerProvider._fetchRecentCustomers] Finally block reached after dispose.");
      }
    }
  }

  void searchCustomers(String query) {
    if (_isDisposed) { debugPrint("searchCustomers: Provider is disposed."); return; }

    final trimmedQuery = query.trim();
    _currentSearchQuery = trimmedQuery;
    _searchDebounce?.cancel();

    if (trimmedQuery.isEmpty) {
      if (_searchResults.isNotEmpty || _isLoadingSearch || _error != null) {
        _searchResults = [];
        _isLoadingSearch = false;
        _error = null;
        if (!_isDisposed) notifyListeners();
      }
      return;
    }

    if (trimmedQuery.length < 3) {
      if (_searchResults.isNotEmpty || _isLoadingSearch) {
        _searchResults = [];
        _isLoadingSearch = false;
        _error = "Ingresa al menos 3 caracteres para buscar.";
        if (!_isDisposed) notifyListeners();
      }
      return;
    }

    if (!_isLoadingSearch) {
      _isLoadingSearch = true;
      _error = null;
      if (!_isDisposed) notifyListeners();
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_currentSearchQuery == trimmedQuery && !_isDisposed) {
        _performApiSearch(trimmedQuery);
      }
    });
  }

  Future<void> _performApiSearch(String query) async {
    if (!_isLoadingSearch) {
      _isLoadingSearch = true;
      _error = null;
      if (!_isDisposed) notifyListeners();
    }

    List<Map<String, dynamic>> results = [];
    String? searchError;

    try {
      final keywords = query.toLowerCase().split(' ').where((s) => s.isNotEmpty).toList();
      final primaryKeyword = keywords.length > 1 ? (keywords..sort((a,b) => b.length.compareTo(a.length))).first : query;

      final apiResults = await _wooCommerceService.searchCustomersAPI(primaryKeyword);

      if (_isDisposed) { debugPrint("[CustomerProvider._performApiSearch] Disposed after awaiting service."); return; }

      if (keywords.length > 1) {
        results = apiResults.where((customer) {
          final searchableText = '${customer['first_name'] ?? ''} ${customer['last_name'] ?? ''} ${customer['email'] ?? ''}'.toLowerCase();
          return keywords.every((keyword) => searchableText.contains(keyword));
        }).toList();
      } else {
        results = apiResults;
      }
      searchError = null;

    } on NetworkException catch (e) {
      if (_isDisposed) return;
      searchError = "Error de red al buscar clientes: ${e.message}";
    } on ApiException catch (e) {
      if (_isDisposed) return;
      searchError = "Error API al buscar clientes: ${e.message}";
    } catch (e) {
      if (_isDisposed) return;
      searchError = "Error inesperado en búsqueda: ${e.toString()}";
    } finally {
      if (!_isDisposed && _currentSearchQuery == query) {
        _searchResults = results;
        _error = searchError;
        _isLoadingSearch = false;
        notifyListeners();
      } else if (!_isDisposed) {
        _isLoadingSearch = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    if (_isDisposed) { return; }
    _searchDebounce?.cancel();
    if (_currentSearchQuery.isNotEmpty || _searchResults.isNotEmpty || _isLoadingSearch || _error != null) {
      _currentSearchQuery = '';
      _searchResults = [];
      _isLoadingSearch = false;
      _error = null;
      if (!_isDisposed) notifyListeners();
    }
  }

  void selectCustomer(String? customerId, String customerName) {
    if (_isDisposed) { return; }

    final effectiveName = customerName.isNotEmpty ? customerName : 'Cliente General';
    if (_selectedCustomerId != customerId || _selectedCustomerName != effectiveName) {
      _selectedCustomerId = customerId;
      _selectedCustomerName = effectiveName;
      debugPrint("[CustomerProvider] Customer selected - ID: $_selectedCustomerId, Name: $_selectedCustomerName");
      clearSearch();
    }
  }

  void clearSelectedCustomer() {
    if (_isDisposed) { return; }
    selectCustomer(null, 'Cliente General');
  }

  Future<void> refreshRecentCustomers() async {
    debugPrint("[CustomerProvider] Refreshing recent customers...");
    _initialRecentsLoaded = false;
    await _fetchRecentCustomers();
  }

  @override
  void dispose() {
    debugPrint("[CustomerProvider] dispose() called.");
    _isDisposed = true;
    _searchDebounce?.cancel();
    super.dispose();
  }
}