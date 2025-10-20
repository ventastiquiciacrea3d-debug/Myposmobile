// lib/providers/inventory_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../models/inventory_movement.dart';
import '../models/inventory_movement_extensions.dart';
import '../models/product.dart' as app_product;
import '../models/inventory_adjustment_cache.dart';
import '../models/label_print_item.dart';
import '../models/sync_operation.dart';
import '../services/sync_manager.dart';
import '../services/woocommerce_service.dart';
import '../config/constants.dart';
import '../locator.dart';
import '../repositories/inventory_repository.dart';
import 'label_provider.dart';

class ProductCategoryGroup {
  final int id;
  final String name;
  final List<app_product.Product> parentProducts;
  final Map<String, List<app_product.Product>> variationsByParentId;

  ProductCategoryGroup({
    required this.id,
    required this.name,
    required this.parentProducts,
    required this.variationsByParentId,
  });
}

class InventoryProvider extends ChangeNotifier {
  final InventoryRepository _inventoryRepository = getIt<InventoryRepository>();
  final SyncManager _syncManager = getIt<SyncManager>();
  final SharedPreferences sharedPreferences;

  // --- ESTADO PARA PAGINACIÓN DEL HISTORIAL ---
  List<InventoryMovement> _inventoryMovements = [];
  int _movementsCurrentPage = 1;
  bool _movementsIsLoading = false;
  bool _movementsIsLoadingMore = false;
  bool _movementsCanLoadMore = true;
  String? _movementsError;
  int _movementsTotalPages = 1;

  List<InventoryMovement> get inventoryMovements => _inventoryMovements;
  bool get isLoadingMovements => _movementsIsLoading;
  bool get isLoadingMoreMovements => _movementsIsLoadingMore;
  bool get canLoadMoreMovements => _movementsCanLoadMore;
  String? get movementsError => _movementsError;

  // (El resto de las propiedades sin cambios)
  List<app_product.Product> _inventoryProducts = [];
  List<app_product.Product> get inventoryProducts => _inventoryProducts;
  bool _isLoadingProducts = false;
  bool get isLoadingProducts => _isLoadingProducts;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  Timer? _errorTimer;
  bool _isDisposed = false;
  final Box<InventoryAdjustmentCache> _cacheBox = Hive.box<InventoryAdjustmentCache>(hiveInventoryAdjustmentCacheBoxName);
  String? _backgroundTaskMessage;
  String? get backgroundTaskMessage => _backgroundTaskMessage;
  bool _isBackgroundTaskRunning = false;
  bool get isBackgroundTaskRunning => _isBackgroundTaskRunning;
  final Set<String> _selectedProductIds = <String>{};
  Set<String> get selectedProductIds => _selectedProductIds;
  List<ProductCategoryGroup> _categorizedProductGroups = [];
  List<ProductCategoryGroup> get categorizedProductGroups => _categorizedProductGroups;
  List<Map<String, dynamic>> _allCategories = [];
  List<Map<String, dynamic>> get allCategories => _allCategories;
  final Set<int> _expandedCategoryIds = {};
  Set<int> get expandedCategoryIds => _expandedCategoryIds;
  final Set<String> _expandedVariableProductIds = {};
  Set<String> get expandedVariableProductIds => _expandedVariableProductIds;

  InventoryProvider({required this.sharedPreferences}) {
    debugPrint("[InventoryProvider] Constructor called.");
    _initInventoryProvider();
  }

  Future<void> _initInventoryProvider() async {
    debugPrint("[InventoryProvider] _initInventoryProvider START");
    await loadInventoryMovements(refresh: true);
  }

  // --- MÉTODOS DE UI Y ESTADO (SIN CAMBIOS) ---
  void _setLoadingProducts(bool loading) {
    if (_isDisposed || _isLoadingProducts == loading) return;
    _isLoadingProducts = loading;
    if (!loading && _errorMessage == null) _clearError(); else if (loading) _clearError();
    if (!_isDisposed) notifyListeners();
  }
  void _setError(String? message, {int durationSeconds = 7}) {
    if (_isDisposed) return;
    _errorTimer?.cancel();
    if (_errorMessage != message) {
      _errorMessage = message;
      if (!_isDisposed) notifyListeners();
    }
    if (message != null) {
      _errorTimer = Timer(Duration(seconds: durationSeconds), () {
        if (!_isDisposed && _errorMessage == message) {
          _errorMessage = null;
          try { if (!_isDisposed) notifyListeners(); } catch (_) {}
        }
      });
    }
  }
  void _clearError() {
    if (_isDisposed) return;
    _errorTimer?.cancel();
    if (_errorMessage != null) {
      _errorMessage = null;
      if (!_isDisposed) notifyListeners();
    }
  }
  void _setBackgroundTaskMessage(String? message) {
    if (_isDisposed) return;
    _backgroundTaskMessage = message;
    _isBackgroundTaskRunning = message != null;
    notifyListeners();
  }
  Future<void> cacheAdjustment(String description, List<InventoryMovementLine> items) async {
    if (items.isEmpty) {
      await clearCachedAdjustment();
      return;
    }
    final cacheData = InventoryAdjustmentCache(
      description: description,
      items: items,
      lastModified: DateTime.now(),
    );
    await _cacheBox.put('current_adjustment', cacheData);
    debugPrint("[InventoryProvider] Adjustment cached with ${items.length} items.");
  }
  Future<InventoryAdjustmentCache?> loadCachedAdjustment() async {
    return _cacheBox.get('current_adjustment');
  }
  Future<void> clearCachedAdjustment() async {
    if (_cacheBox.containsKey('current_adjustment')) {
      await _cacheBox.delete('current_adjustment');
      debugPrint("[InventoryProvider] Cached adjustment cleared.");
    }
  }

  // --- CARGA DE HISTORIAL DE INVENTARIO CON PAGINACIÓN ---
  Future<void> loadInventoryMovements({String? searchTerm, bool refresh = false}) async {
    if ((_movementsIsLoading || _movementsIsLoadingMore) && !refresh) return;

    if (refresh) {
      _movementsCurrentPage = 1;
      _inventoryMovements = [];
      _movementsCanLoadMore = true;
    }

    if (!_isDisposed) {
      if (_movementsCurrentPage == 1) _movementsIsLoading = true; else _movementsIsLoadingMore = true;
      _movementsError = null;
      notifyListeners();
    }

    try {
      final response = await _inventoryRepository.getInventoryMovements(
        page: _movementsCurrentPage, perPage: 25, searchTerm: searchTerm,
      );

      final List<InventoryMovement> newMovements = response['movements'];
      _movementsTotalPages = response['total_pages'];

      if (!_isDisposed) {
        if (refresh) _inventoryMovements = [];
        _inventoryMovements.addAll(newMovements);
        _movementsCanLoadMore = _movementsCurrentPage < _movementsTotalPages;
        if (_movementsCanLoadMore) _movementsCurrentPage++;
      }
    } catch (e) {
      if (!_isDisposed) _movementsError = e.toString();
    } finally {
      if (!_isDisposed) {
        _movementsIsLoading = false;
        _movementsIsLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<bool> performMassInventoryAdjustment({
    required InventoryMovementType type,
    required String description,
    required List<InventoryMovementLine> itemsToAdjust,
  }) async {
    if (itemsToAdjust.isEmpty) {
      _setError("No hay productos en el lote para ajustar.");
      return false;
    }

    final newMovement = InventoryMovement(
      id: const Uuid().v4(),
      date: DateTime.now(),
      type: type,
      description: description.isEmpty ? type.displayName : description,
      items: itemsToAdjust,
      isSynced: false,
    );

    _setLoadingProducts(true);
    debugPrint("[InventoryProvider] Performing mass adjustment: ${newMovement.description}, Items: ${itemsToAdjust.length}");

    try {
      await _inventoryRepository.submitInventoryAdjustment(newMovement);
      await loadInventoryMovements(refresh: true);
      _setError("Ajuste de inventario guardado exitosamente.", durationSeconds: 5);
      return true;
    } on NetworkException catch (e) {
      _setError("Error de red. El ajuste fue encolado para sincronización.", durationSeconds: 8);
      await _syncManager.addOperation(
          SyncOperationType.inventoryAdjustment,
          {'movement': newMovement.toJson()}
      );
      _inventoryMovements.insert(0, newMovement);
      if (!_isDisposed) notifyListeners();
      return false;
    } on ApiException catch (e) {
      _setError("Error de API: ${e.message}", durationSeconds: 8);
      return false;
    } catch (e) {
      _setError("Error inesperado: ${e.toString()}", durationSeconds: 8);
      return false;
    } finally {
      if (!_isDisposed) _setLoadingProducts(false);
    }
  }

  Future<void> loadInventoryProducts({String? searchTerm, bool forceApi = false}) async {
    if (_isLoadingProducts && !forceApi) return;
    _setLoadingProducts(true);
    _clearSelection();
    debugPrint("[InventoryProvider] Loading inventory products. Search: '$searchTerm', ForceAPI: $forceApi");

    try {
      List<Map<String, dynamic>> categories = [];
      try {
        categories = await _inventoryRepository.getProductCategories();
      } catch (e) {
        debugPrint("[InventoryProvider] Could not fetch categories, likely due to plugin mode limitations. Proceeding without categories. Error: $e");
        categories = [];
      }

      _inventoryProducts = await _inventoryRepository.getInventoryProducts(searchTerm: searchTerm, forceApi: forceApi);
      _allCategories = categories;

      _organizeProductsIntoCategories();

      debugPrint("... Loaded ${_inventoryProducts.length} products and ${_allCategories.length} categories for inventory view.");
      if (searchTerm == null || searchTerm.isEmpty) _clearError();
    } catch (e) {
      debugPrint("Error loading inventory products via provider: $e");
      _setError("Error cargando productos: ${e.toString()}");
      _inventoryProducts = [];
      _categorizedProductGroups = [];
    } finally {
      if (!_isDisposed) _setLoadingProducts(false);
    }
  }

  void _organizeProductsIntoCategories() {
    final variationsGroupedByParent = groupBy(
      _inventoryProducts.where((p) => p.isVariation),
          (p) => p.parentId.toString(),
    );

    final parentProducts = _inventoryProducts.where((p) => !p.isVariation).toList();
    final groupMap = <int, ProductCategoryGroup>{};
    final uncategorizedParents = <app_product.Product>[];

    if (_allCategories.isEmpty) {
      uncategorizedParents.addAll(parentProducts);
    } else {
      for (final product in parentProducts) {
        bool categorized = false;
        if (product.categoryNames != null && product.categoryNames!.isNotEmpty) {
          for (final catName in product.categoryNames!) {
            final category = _allCategories.firstWhereOrNull((c) => c['name'] == catName);
            if (category != null) {
              final catId = category['id'] as int;
              groupMap.putIfAbsent(catId, () => ProductCategoryGroup(
                id: catId, name: catName, parentProducts: [], variationsByParentId: {},
              ));
              groupMap[catId]!.parentProducts.add(product);
              categorized = true;
            }
          }
        }
        if (!categorized) {
          uncategorizedParents.add(product);
        }
      }
    }

    groupMap.forEach((catId, group) {
      group.parentProducts.sort((a, b) => a.name.compareTo(b.name));
      for (final parent in group.parentProducts) {
        if (variationsGroupedByParent.containsKey(parent.id)) {
          group.variationsByParentId[parent.id] = variationsGroupedByParent[parent.id]!..sort((a,b) => a.name.compareTo(b.name));
        }
      }
    });

    final sortedGroups = groupMap.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (uncategorizedParents.isNotEmpty) {
      final uncategorizedVariations = <String, List<app_product.Product>>{};
      uncategorizedParents.sort((a,b) => a.name.compareTo(b.name));
      for (final parent in uncategorizedParents) {
        if (variationsGroupedByParent.containsKey(parent.id)) {
          uncategorizedVariations[parent.id] = variationsGroupedByParent[parent.id]!..sort((a,b) => a.name.compareTo(b.name));
        }
      }
      sortedGroups.add(ProductCategoryGroup(
        id: 0,
        name: "Sin Categoría",
        parentProducts: uncategorizedParents,
        variationsByParentId: uncategorizedVariations,
      ));
    }
    _categorizedProductGroups = sortedGroups;
  }

  void toggleCategoryExpansion(int categoryId) {
    if (_expandedCategoryIds.contains(categoryId)) {
      _expandedCategoryIds.remove(categoryId);
    } else {
      _expandedCategoryIds.add(categoryId);
    }
    notifyListeners();
  }

  void toggleVariableProductExpansion(String productId) {
    if (_expandedVariableProductIds.contains(productId)) {
      _expandedVariableProductIds.remove(productId);
    } else {
      _expandedVariableProductIds.add(productId);
    }
    notifyListeners();
  }

  void toggleProductSelection(String productId, {List<app_product.Product> children = const []}) {
    final isSelected = _selectedProductIds.contains(productId);
    if (isSelected) {
      _selectedProductIds.remove(productId);
      for (final child in children) {
        _selectedProductIds.remove(child.id);
      }
    } else {
      _selectedProductIds.add(productId);
      for (final child in children) {
        _selectedProductIds.add(child.id);
      }
    }
    notifyListeners();
  }

  void selectAllInCategory(ProductCategoryGroup group) {
    for (final parent in group.parentProducts) {
      _selectedProductIds.add(parent.id);
      if (group.variationsByParentId.containsKey(parent.id)) {
        for (final variation in group.variationsByParentId[parent.id]!) {
          _selectedProductIds.add(variation.id);
        }
      }
    }
    notifyListeners();
  }

  void deselectAllInCategory(ProductCategoryGroup group) {
    for (final parent in group.parentProducts) {
      _selectedProductIds.remove(parent.id);
      if (group.variationsByParentId.containsKey(parent.id)) {
        for (final variation in group.variationsByParentId[parent.id]!) {
          _selectedProductIds.remove(variation.id);
        }
      }
    }
    notifyListeners();
  }


  void _clearSelection() {
    _selectedProductIds.clear();
    notifyListeners();
  }

  int addSelectedToPrintQueue(LabelProvider labelProvider) {
    if (_selectedProductIds.isEmpty) return 0;

    final productsToAdd = _inventoryProducts.where((p) => _selectedProductIds.contains(p.id)).toList();
    if (productsToAdd.isEmpty) return 0;

    final parentProductMap = {
      for (var p in _inventoryProducts.where((p) => !p.isVariation)) p.id: p
    };

    final List<LabelPrintItem> items = [];
    for (final product in productsToAdd) {
      if (product.isVariable) continue;

      final qty = (product.stockQuantity != null && product.stockQuantity! > 0) ? product.stockQuantity! : 1;
      app_product.Product? parent;
      if (product.isVariation) {
        parent = parentProductMap[product.parentId.toString()];
      }

      items.add(
        LabelPrintItem(
          productId: product.isVariation ? product.parentId.toString() : product.id,
          resolvedVariantId: product.isVariation ? product.id : null,
          quantity: qty,
          selectedVariants: product.isVariation ? product.attributes?.fold<Map<String, String>>({}, (prev, attr) {
            prev[attr['name'] ?? ''] = attr['option'] ?? '';
            return prev;
          }) ?? {} : {},
          barcode: product.barcode ?? product.sku,
          product: parent ?? product,
          resolvedVariant: product.isVariation ? product : null,
        ),
      );
    }

    labelProvider.addMultipleItems(items);
    final count = items.length;
    _clearSelection();
    return count;
  }

  // Métodos que faltaban
  Future<void> resetAllStockToZero() async {
    // Implementar la lógica para llamar al servicio que resetea el stock
    _setBackgroundTaskMessage("Reseteando stock de todos los productos...");
    await _inventoryRepository.resetAllStockToZero();
    _setBackgroundTaskMessage(null);
  }

  Future<void> activateManageStockForAllVariables() async {
    _setBackgroundTaskMessage("Activando gestión de stock...");
    await _inventoryRepository.activateManageStockForAllVariables();
    _setBackgroundTaskMessage(null);
  }

  @override
  void dispose() {
    debugPrint("[InventoryProvider] dispose() called.");
    _isDisposed = true;
    _errorTimer?.cancel();
    super.dispose();
  }
}