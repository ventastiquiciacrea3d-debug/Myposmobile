// lib/providers/inventory_notifier.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
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
import '../services/storage_service.dart';
import '../repositories/inventory_repository.dart';
import 'inventory_state.dart';
import 'shared_providers.dart';

part 'inventory_notifier.g.dart';

/// ✓ FASE 2 RIVERPOD: Inventory Notifier
@riverpod
class Inventory extends _$Inventory {
  late InventoryRepository _inventoryRepository;
  late SyncManager _syncManager;
  late SharedPreferences _prefs;
  late WooCommerceService _wooService;
  late StorageService _storageService;

  Timer? _errorTimer;

  @override
  InventoryState build() {
    debugPrint("[Inventory] build() called - Initializing");

    _inventoryRepository = ref.read(inventoryRepositoryProvider);
    _syncManager = ref.read(syncManagerProvider);
    _prefs = ref.read(sharedPreferencesProvider);
    _wooService = ref.read(wooCommerceServiceProvider);
    _storageService = ref.read(storageServiceProvider);

    ref.onDispose(() {
      debugPrint("[Inventory] Disposing");
      _errorTimer?.cancel();
    });

    // ✓ CORRECCIÓN RACE CONDITION: Usar Future.microtask para diferir la carga
    // hasta DESPUÉS de que build() haya retornado el estado inicial.
    // IMPORTANTE: Acceder a 'state' directamente en lugar de ref.read(inventoryProvider)
    // para evitar intentar leer el provider que aún se está construyendo
    Future.microtask(() {
      // Usar el estado inicial retornado por build() en lugar de leer el provider
      _initInventoryProvider();
    });

    return InventoryState.initial();
  }

  Future<void> _initInventoryProvider() async {
    debugPrint("[Inventory] _initInventoryProvider START");
    await loadInventoryMovements(refresh: true);
  }

  // ========== ERROR HANDLING ==========

  void _setError(String? message, {int durationSeconds = 7}) {
    _errorTimer?.cancel();

    if (state.errorMessage != message) {
      state = state.copyWith(errorMessage: message);
    }

    if (message != null) {
      _errorTimer = Timer(Duration(seconds: durationSeconds), () {
        if (state.errorMessage == message) {
          state = state.copyWith(errorMessage: null);
        }
      });
    }
  }

  void _clearError() {
    _errorTimer?.cancel();
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  void _setBackgroundTaskMessage(String? message) {
    state = state.copyWith(
      backgroundTaskMessage: message,
      isBackgroundTaskRunning: message != null,
    );
  }

  // ========== ADJUSTMENT CACHE METHODS ==========

  Future<void> cacheAdjustment(
      String description, List<InventoryMovementLine> items) async {
    if (items.isEmpty) {
      await clearCachedAdjustment();
      return;
    }

    final cacheData = InventoryAdjustmentCache(
      description: description,
      items: items,
      lastModified: DateTime.now(),
    );

    // ✅ SHAREDPREFERENCES: Save as JSON
    try {
      final jsonString = jsonEncode(cacheData.toJson());
      await _prefs.setString('current_adjustment', jsonString);
      debugPrint("[Inventory] Adjustment cached with ${items.length} items.");
    } catch (e) {
      debugPrint("[Inventory] ❌ Error caching adjustment: $e");
    }
  }

  /// ✅ SHAREDPREFERENCES: Load from JSON
  Future<InventoryAdjustmentCache?> loadCachedAdjustment() async {
    try {
      final jsonString = _prefs.getString('current_adjustment');
      if (jsonString == null) return null;

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return InventoryAdjustmentCache.fromJson(json);
    } catch (e) {
      debugPrint("[Inventory] ❌ Error loading cached adjustment: $e");
      return null;
    }
  }

  /// ✅ SHAREDPREFERENCES: Clear cache
  Future<void> clearCachedAdjustment() async {
    try {
      if (_prefs.containsKey('current_adjustment')) {
        await _prefs.remove('current_adjustment');
        debugPrint("[Inventory] Cached adjustment cleared.");
      }
    } catch (e) {
      debugPrint("[Inventory] ❌ Error clearing cached adjustment: $e");
    }
  }

  // ========== INVENTORY MOVEMENTS (HISTORY) ==========

  Future<void> loadInventoryMovements({
    String? searchTerm,
    bool refresh = false,
  }) async {
    if ((state.movementsIsLoading || state.movementsIsLoadingMore) && !refresh) {
      return;
    }

    int currentPage = state.movementsCurrentPage;
    List<InventoryMovement> currentMovements = state.inventoryMovements;

    if (refresh) {
      currentPage = 1;
      currentMovements = [];
    }

    state = state.copyWith(
      movementsIsLoading: currentPage == 1,
      movementsIsLoadingMore: currentPage > 1,
      movementsError: null,
    );

    try {
      final response = await _inventoryRepository.getInventoryMovements(
        page: currentPage,
        perPage: 25,
        searchTerm: searchTerm,
      );

      final List<InventoryMovement> newMovements = response['movements'];
      final int totalPages = response['total_pages'];

      if (refresh) {
        currentMovements = newMovements;
      } else {
        currentMovements = [...currentMovements, ...newMovements];
      }

      final bool canLoadMore = currentPage < totalPages;

      state = state.copyWith(
        inventoryMovements: currentMovements,
        movementsCurrentPage: canLoadMore ? currentPage + 1 : currentPage,
        movementsTotalPages: totalPages,
        movementsCanLoadMore: canLoadMore,
      );

      debugPrint(
          "[Inventory] Loaded ${newMovements.length} movements (page $currentPage/$totalPages)");
    } catch (e) {
      state = state.copyWith(movementsError: e.toString());
      debugPrint("[Inventory] Error loading movements: $e");
    } finally {
      state = state.copyWith(
        movementsIsLoading: false,
        movementsIsLoadingMore: false,
      );
    }
  }

  // ========== MASS INVENTORY ADJUSTMENT ==========

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

    state = state.copyWith(isLoadingProducts: true);
    debugPrint(
        "[Inventory] Performing mass adjustment: ${newMovement.description}, Items: ${itemsToAdjust.length}");

    try {
      // ✓ V3.1.0: Preparar batch de actualizaciones (80% más rápido)
      final batchItems = itemsToAdjust.map((item) {
        return {
          'id': item.productId,
          'stock': item.quantityChanged.abs(),
          'operation': item.quantityChanged > 0 ? 'add' : 'subtract',
        };
      }).toList();

      debugPrint("[Inventory] Sending batch update with ${batchItems.length} items");

      // ✓ V3.1.0: Enviar en batch (1 request en lugar de N requests)
      final response = await _wooService.batchUpdateStock(batchItems);

      if (response['success'] == true) {
        final updated = response['updated'] as int? ?? 0;

        debugPrint('[Inventory] ✅ Batch adjustment completed: $updated products');

        // ✅ FIX: Actualizar stock local inmediatamente
        final productRepo = ref.read(productRepositoryProvider);
        for (final item in itemsToAdjust) {
          try {
            final product = await productRepo.getProductById(item.productId, forceApi: false);
            if (product != null) {
              final stockBefore = product.stockQuantity ?? 0;
              final stockAfter = stockBefore + item.quantityChanged;

              debugPrint('[Inventory] 📦 Actualizando stock local: ${product.name} - Antes: $stockBefore, Después: $stockAfter');

              // Crear nueva instancia con stock actualizado
              final updatedProduct = product.copyWith(
                stockQuantity: () => stockAfter,
                stockStatus: () => stockAfter > 0 ? 'instock' : 'outofstock',
              );

              // Guardar en ObjectBox
              await _storageService.cacheProduct(updatedProduct);
            }
          } catch (e) {
            debugPrint('[Inventory] ⚠️ Error actualizando stock local para ${item.productId}: $e');
          }
        }

        await loadInventoryMovements(refresh: true);
        _setError('Ajuste aplicado: $updated productos actualizados', durationSeconds: 5);

        return true;
      } else {
        _setError('Error al aplicar ajuste de inventario');
        return false;
      }
    } on NetworkException {
      _setError(
          "Error de red. El ajuste fue encolado para sincronización.",
          durationSeconds: 8);

      // ✓ PROPUESTA 2: Prioridad alta (por defecto) e idempotency key auto-generado
      await _syncManager.addOperation(
        SyncOperationType.inventoryAdjustment,
        {'movement': newMovement.toJson()},
      );

      // Add to local list
      final updatedMovements = [newMovement, ...state.inventoryMovements];
      state = state.copyWith(inventoryMovements: updatedMovements);

      return false;
    } on ApiException catch (e) {
      _setError("Error de API: ${e.message}", durationSeconds: 8);
      return false;
    } catch (e) {
      _setError("Error inesperado: ${e.toString()}", durationSeconds: 8);
      return false;
    } finally {
      state = state.copyWith(isLoadingProducts: false);
    }
  }

  // ========== INVENTORY PRODUCTS LOADING ==========

  Future<void> loadInventoryProducts({
    String? searchTerm,
    bool forceApi = false,
  }) async {
    if (state.isLoadingProducts && !forceApi) return;

    state = state.copyWith(isLoadingProducts: true);
    _clearSelection();
    _clearError();

    debugPrint(
        "[Inventory] Loading inventory products. Search: '$searchTerm', ForceAPI: $forceApi");

    try {
      // Load categories
      List<Map<String, dynamic>> categories = [];
      try {
        categories = await _inventoryRepository.getProductCategories();
      } catch (e) {
        debugPrint(
            "[Inventory] Could not fetch categories, likely due to plugin mode limitations. Proceeding without categories. Error: $e");
        categories = [];
      }

      // Load products
      final products = await _inventoryRepository.getInventoryProducts(
        searchTerm: searchTerm,
        forceApi: forceApi,
      );

      state = state.copyWith(
        inventoryProducts: products,
        allCategories: categories,
      );

      _organizeProductsIntoCategories();

      debugPrint(
          "... Loaded ${products.length} products and ${categories.length} categories for inventory view.");

      if (searchTerm == null || searchTerm.isEmpty) {
        _clearError();
      }
    } catch (e) {
      debugPrint("[Inventory] Error loading inventory products: $e");
      _setError("Error cargando productos: ${e.toString()}");

      state = state.copyWith(
        inventoryProducts: [],
        categorizedProductGroups: [],
      );
    } finally {
      state = state.copyWith(isLoadingProducts: false);
    }
  }

  // ========== CATEGORY ORGANIZATION ==========

  void _organizeProductsIntoCategories() {
    final variationsGroupedByParent = groupBy(
      state.inventoryProducts.where((p) => p.isVariation),
      (p) => p.parentId.toString(),
    );

    final parentProducts =
        state.inventoryProducts.where((p) => !p.isVariation).toList();
    final groupMap = <int, ProductCategoryGroup>{};
    final uncategorizedParents = <app_product.Product>[];

    if (state.allCategories.isEmpty) {
      uncategorizedParents.addAll(parentProducts);
    } else {
      for (final product in parentProducts) {
        bool categorized = false;

        if (product.categoryNames != null && product.categoryNames!.isNotEmpty) {
          for (final catName in product.categoryNames!) {
            final category = state.allCategories
                .firstWhereOrNull((c) => c['name'] == catName);

            if (category != null) {
              final catId = category['id'] as int;

              groupMap.putIfAbsent(
                catId,
                () => ProductCategoryGroup(
                  id: catId,
                  name: catName,
                  parentProducts: [],
                  variationsByParentId: {},
                ),
              );

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

    // Sort products within each category and add variations
    groupMap.forEach((catId, group) {
      group.parentProducts.sort((a, b) => a.name.compareTo(b.name));

      for (final parent in group.parentProducts) {
        if (variationsGroupedByParent.containsKey(parent.id)) {
          group.variationsByParentId[parent.id] =
              variationsGroupedByParent[parent.id]!
                ..sort((a, b) => a.name.compareTo(b.name));
        }
      }
    });

    final sortedGroups = groupMap.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Add uncategorized products
    if (uncategorizedParents.isNotEmpty) {
      final uncategorizedVariations = <String, List<app_product.Product>>{};
      uncategorizedParents.sort((a, b) => a.name.compareTo(b.name));

      for (final parent in uncategorizedParents) {
        if (variationsGroupedByParent.containsKey(parent.id)) {
          uncategorizedVariations[parent.id] = variationsGroupedByParent[parent.id]!
            ..sort((a, b) => a.name.compareTo(b.name));
        }
      }

      sortedGroups.add(
        ProductCategoryGroup(
          id: 0,
          name: "Sin Categoría",
          parentProducts: uncategorizedParents,
          variationsByParentId: uncategorizedVariations,
        ),
      );
    }

    state = state.copyWith(categorizedProductGroups: sortedGroups);
  }

  // ========== UI INTERACTION METHODS ==========

  void toggleCategoryExpansion(int categoryId) {
    final updatedExpanded = Set<int>.from(state.expandedCategoryIds);

    if (updatedExpanded.contains(categoryId)) {
      updatedExpanded.remove(categoryId);
    } else {
      updatedExpanded.add(categoryId);
    }

    state = state.copyWith(expandedCategoryIds: updatedExpanded);
  }

  void toggleVariableProductExpansion(String productId) {
    final updatedExpanded = Set<String>.from(state.expandedVariableProductIds);

    if (updatedExpanded.contains(productId)) {
      updatedExpanded.remove(productId);
    } else {
      updatedExpanded.add(productId);
    }

    state = state.copyWith(expandedVariableProductIds: updatedExpanded);
  }

  void toggleProductSelection(
    String productId, {
    List<app_product.Product> children = const [],
  }) {
    final updatedSelection = Set<String>.from(state.selectedProductIds);
    final isSelected = updatedSelection.contains(productId);

    if (isSelected) {
      updatedSelection.remove(productId);
      for (final child in children) {
        updatedSelection.remove(child.id);
      }
    } else {
      updatedSelection.add(productId);
      for (final child in children) {
        updatedSelection.add(child.id);
      }
    }

    state = state.copyWith(selectedProductIds: updatedSelection);
  }

  void selectAllInCategory(ProductCategoryGroup group) {
    final updatedSelection = Set<String>.from(state.selectedProductIds);

    for (final parent in group.parentProducts) {
      updatedSelection.add(parent.id);

      if (group.variationsByParentId.containsKey(parent.id)) {
        for (final variation in group.variationsByParentId[parent.id]!) {
          updatedSelection.add(variation.id);
        }
      }
    }

    state = state.copyWith(selectedProductIds: updatedSelection);
  }

  void deselectAllInCategory(ProductCategoryGroup group) {
    final updatedSelection = Set<String>.from(state.selectedProductIds);

    for (final parent in group.parentProducts) {
      updatedSelection.remove(parent.id);

      if (group.variationsByParentId.containsKey(parent.id)) {
        for (final variation in group.variationsByParentId[parent.id]!) {
          updatedSelection.remove(variation.id);
        }
      }
    }

    state = state.copyWith(selectedProductIds: updatedSelection);
  }

  void _clearSelection() {
    if (state.selectedProductIds.isNotEmpty) {
      state = state.copyWith(selectedProductIds: {});
    }
  }

  // ========== LABEL PRINTING INTEGRATION ==========

  List<LabelPrintItem> getSelectedProductsAsLabelItems() {
    if (state.selectedProductIds.isEmpty) return [];

    final productsToAdd = state.inventoryProducts
        .where((p) => state.selectedProductIds.contains(p.id))
        .toList();

    if (productsToAdd.isEmpty) return [];

    final parentProductMap = {
      for (var p in state.inventoryProducts.where((p) => !p.isVariation))
        p.id: p
    };

    final List<LabelPrintItem> items = [];

    for (final product in productsToAdd) {
      if (product.isVariable) continue;

      final qty = (product.stockQuantity != null && product.stockQuantity! > 0)
          ? product.stockQuantity!
          : 1;

      app_product.Product? parent;
      if (product.isVariation) {
        parent = parentProductMap[product.parentId.toString()];
      }

      items.add(
        LabelPrintItem(
          productId: product.isVariation ? product.parentId.toString() : product.id,
          resolvedVariantId: product.isVariation ? product.id : null,
          quantity: qty,
          selectedVariants: product.isVariation
              ? product.attributes?.fold<Map<String, String>>({}, (prev, attr) {
                    prev[attr['name'] ?? ''] = attr['option'] ?? '';
                    return prev;
                  }) ??
                  {}
              : {},
          barcode: product.barcode ?? product.sku,
          product: parent ?? product,
          resolvedVariant: product.isVariation ? product : null,
        ),
      );
    }

    return items;
  }

  void clearSelection() {
    _clearSelection();
  }

  // ========== BACKGROUND OPERATIONS ==========

  Future<void> resetAllStockToZero() async {
    _setBackgroundTaskMessage("Reseteando stock de todos los productos...");

    try {
      await _inventoryRepository.resetAllStockToZero();
      debugPrint("[Inventory] Reset all stock to zero completed");
    } catch (e) {
      debugPrint("[Inventory] Error resetting stock: $e");
      _setError("Error al resetear stock: ${e.toString()}");
    } finally {
      _setBackgroundTaskMessage(null);
    }
  }

  Future<void> activateManageStockForAllVariables() async {
    _setBackgroundTaskMessage("Activando gestión de stock...");

    try {
      await _inventoryRepository.activateManageStockForAllVariables();
      debugPrint("[Inventory] Activate manage stock completed");
    } catch (e) {
      debugPrint("[Inventory] Error activating manage stock: $e");
      _setError("Error al activar gestión de stock: ${e.toString()}");
    } finally {
      _setBackgroundTaskMessage(null);
    }
  }
}
