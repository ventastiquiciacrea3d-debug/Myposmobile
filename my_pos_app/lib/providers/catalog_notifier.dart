// lib/providers/catalog_notifier.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/product.dart';
import '../services/storage_service.dart';
import '../services/product_sync_service.dart';
import '../locator.dart';
import 'catalog_state.dart';
import 'shared_providers.dart';

part 'catalog_notifier.g.dart';

@riverpod
class Catalog extends _$Catalog {
  late StorageService _storageService;
  Timer? _searchDebounce;

  @override
  CatalogState build() {
    _storageService = ref.read(storageServiceProvider);

    ref.onDispose(() {
      _searchDebounce?.cancel();
    });

    // Cargar catálogo inicial
    Future.microtask(() => loadCatalog(refresh: true));

    return CatalogState.initial();
  }

  // ========== CARGA DE DATOS ==========

  Future<void> loadCatalog({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
    );

    try {
      debugPrint('[Catalog] Loading catalog from local database...');

      // 1. Cargar TODOS los productos desde ObjectBox
      final allProductsFromDB = await _storageService.getAllProducts(includeVariations: true);

      if (allProductsFromDB.isEmpty) {
        debugPrint('[Catalog] No products found in database');
        state = state.copyWith(
          isLoading: false,
          allProducts: [],
          filteredProducts: [],
          variationsByParent: {},
          categories: [],
        );
        return;
      }

      // 2. Separar productos padre y variaciones
      final parentProducts = allProductsFromDB
          .where((p) => !p.isVariation)
          .toList();

      final variations = allProductsFromDB
          .where((p) => p.isVariation)
          .toList();

      debugPrint('[Catalog] Found ${parentProducts.length} parent products and ${variations.length} variations');

      // 3. Agrupar variaciones por padre
      final variationsByParent = _groupVariationsByParent(variations);

      // 4. Extraer categorías únicas
      final categories = _extractCategories(parentProducts);

      // 5. Aplicar filtros actuales
      final filtered = _applyFilters(parentProducts);

      // 6. Aplicar ordenamiento
      final sorted = _applySorting(filtered);

      // 7. Obtener timestamp de última sync
      final lastSync = _getLastSyncTimestamp(allProductsFromDB);

      state = state.copyWith(
        allProducts: parentProducts,
        filteredProducts: sorted,
        variationsByParent: variationsByParent,
        categories: categories,
        isLoading: false,
        lastSyncTimestamp: lastSync,
      );

      debugPrint('[Catalog] ✅ Catalog loaded: ${parentProducts.length} parent products, ${variationsByParent.length} have variations');
    } catch (e, stackTrace) {
      debugPrint('[Catalog] ❌ Error loading: $e\n$stackTrace');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error cargando catálogo: ${e.toString()}',
      );
    }
  }

  Map<String, List<Product>> _groupVariationsByParent(List<Product> variations) {
    final grouped = <String, List<Product>>{};

    for (final variation in variations) {
      if (variation.parentId == null) continue;

      final parentId = variation.parentId.toString();
      grouped.putIfAbsent(parentId, () => []).add(variation);
    }

    // Ordenar variaciones por nombre
    grouped.forEach((key, list) {
      list.sort((a, b) => a.name.compareTo(b.name));
    });

    return grouped;
  }

  List<String> _extractCategories(List<Product> products) {
    final categories = <String>{};

    int productsWithCategories = 0;
    for (final product in products) {
      if (product.categoryNames != null && product.categoryNames!.isNotEmpty) {
        categories.addAll(product.categoryNames!);
        productsWithCategories++;
        debugPrint('[Catalog] Product "${product.name}" has categories: ${product.categoryNames}');
      }
    }

    debugPrint('[Catalog] 📂 Extracted ${categories.length} unique categories from $productsWithCategories products');
    debugPrint('[Catalog] 📂 Categories: ${categories.toList()..sort()}');

    return categories.toList()..sort();
  }

  DateTime? _getLastSyncTimestamp(List<Product> products) {
    // Obtener el producto con dateModified más reciente
    final newestProduct = products
        .where((p) => p.dateModified != null)
        .fold<Product?>(null, (newest, p) {
      if (newest == null) return p;
      return p.dateModified!.isAfter(newest.dateModified!)
          ? p
          : newest;
    });

    return newestProduct?.dateModified;
  }

  // ========== BÚSQUEDA ==========

  void setSearchTerm(String term) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final trimmedTerm = term.trim();

      if (trimmedTerm.isEmpty) {
        state = state.copyWith(
          searchTerm: '',
          filteredProducts: _applySorting(_applyFilters(state.allProducts)),
        );
        debugPrint('[Catalog] Search cleared, showing all ${state.filteredProducts.length} products');
      } else {
        final results = _searchProducts(trimmedTerm);
        final filtered = _applyFilters(results);
        final sorted = _applySorting(filtered);

        state = state.copyWith(
          searchTerm: trimmedTerm,
          filteredProducts: sorted,
        );

        debugPrint('[Catalog] Search "$trimmedTerm": ${sorted.length} results');
      }
    });
  }

  List<Product> _searchProducts(String term) {
    final lowerTerm = term.toLowerCase();

    return state.allProducts.where((p) =>
      p.name.toLowerCase().contains(lowerTerm) ||
      p.sku.toLowerCase().contains(lowerTerm) ||
      (p.barcode?.toLowerCase().contains(lowerTerm) ?? false)
    ).toList();
  }

  // ========== FILTROS ==========

  void updateFilters(CatalogFilters newFilters) {
    state = state.copyWith(filters: newFilters);

    final baseProducts = state.searchTerm.isEmpty
        ? state.allProducts
        : _searchProducts(state.searchTerm);

    final filtered = _applyFilters(baseProducts);
    final sorted = _applySorting(filtered);

    state = state.copyWith(filteredProducts: sorted);

    debugPrint('[Catalog] Filters updated, showing ${sorted.length} products');
  }

  List<Product> _applyFilters(List<Product> products) {
    var filtered = products;
    final filters = state.filters;

    // Filtro por estado de stock
    filtered = filtered.where((p) {
      final status = p.stockStatus ?? 'instock';

      if (status == 'instock' && filters.showInStock) return true;
      if (status == 'outofstock' && filters.showOutOfStock) return true;
      if (status == 'onbackorder' && filters.showOnBackorder) return true;

      return false;
    }).toList();

    // Filtro por categorías
    if (filters.selectedCategories.isNotEmpty) {
      filtered = filtered.where((p) {
        if (p.categoryNames == null) return false;
        return p.categoryNames!.any((cat) =>
          filters.selectedCategories.contains(cat));
      }).toList();
    }

    return filtered;
  }

  void toggleStockFilter(String filterType) {
    final currentFilters = state.filters;

    switch (filterType) {
      case 'instock':
        updateFilters(currentFilters.copyWith(
          showInStock: !currentFilters.showInStock,
        ));
        break;
      case 'outofstock':
        updateFilters(currentFilters.copyWith(
          showOutOfStock: !currentFilters.showOutOfStock,
        ));
        break;
      case 'onbackorder':
        updateFilters(currentFilters.copyWith(
          showOnBackorder: !currentFilters.showOnBackorder,
        ));
        break;
    }
  }

  void toggleCategoryFilter(String category) {
    final current = Set<String>.from(state.filters.selectedCategories);

    if (current.contains(category)) {
      current.remove(category);
    } else {
      current.add(category);
    }

    updateFilters(state.filters.copyWith(selectedCategories: current));
  }

  void clearAllFilters() {
    updateFilters(const CatalogFilters());
  }

  // ========== ORDENAMIENTO ==========

  void applySorting(ProductSortBy sortBy) {
    updateFilters(state.filters.copyWith(sortBy: sortBy));
  }

  List<Product> _applySorting(List<Product> products) {
    final sorted = List<Product>.from(products);

    switch (state.filters.sortBy) {
      case ProductSortBy.nameAsc:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case ProductSortBy.nameDesc:
        sorted.sort((a, b) => b.name.compareTo(a.name));
        break;
      case ProductSortBy.priceAsc:
        sorted.sort((a, b) => a.price.compareTo(b.price));
        break;
      case ProductSortBy.priceDesc:
        sorted.sort((a, b) => b.price.compareTo(a.price));
        break;
      case ProductSortBy.stockAsc:
        sorted.sort((a, b) =>
          (a.stockQuantity ?? 0).compareTo(b.stockQuantity ?? 0));
        break;
      case ProductSortBy.stockDesc:
        sorted.sort((a, b) =>
          (b.stockQuantity ?? 0).compareTo(a.stockQuantity ?? 0));
        break;
      case ProductSortBy.recentlyModified:
        sorted.sort((a, b) {
          if (a.dateModified == null && b.dateModified == null) return 0;
          if (a.dateModified == null) return 1;
          if (b.dateModified == null) return -1;
          return b.dateModified!.compareTo(a.dateModified!);
        });
        break;
    }

    return sorted;
  }

  // ========== UI INTERACTIONS ==========

  void toggleParentExpansion(String parentId) {
    final expanded = Set<String>.from(state.expandedParentIds);

    if (expanded.contains(parentId)) {
      expanded.remove(parentId);
    } else {
      expanded.add(parentId);
    }

    state = state.copyWith(expandedParentIds: expanded);
  }

  void expandAll() {
    // Expandir todos los productos variables que tengan variaciones
    final allParentIds = state.allProducts
        .where((p) => p.isVariable && (state.variationsByParent[p.id]?.isNotEmpty ?? false))
        .map((p) => p.id)
        .toSet();

    state = state.copyWith(expandedParentIds: allParentIds);
  }

  void collapseAll() {
    state = state.copyWith(expandedParentIds: {});
  }

  // ========== SINCRONIZACIÓN ==========

  Future<void> syncFromWooCommerce() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      debugPrint('[Catalog] Starting sync from WooCommerce...');

      // Sincronización REAL desde WooCommerce
      final productSyncService = getIt<ProductSyncService>();

      int totalSynced = 0;
      await productSyncService.syncAllProducts(
        onProgress: (current, total, status) {
          debugPrint('[Catalog] Sync progress: $current/$total - $status');
          totalSynced = current;
        },
      );

      debugPrint('[Catalog] ✅ Synced $totalSynced products from WooCommerce');

      // Recargar catálogo después de sync
      await loadCatalog(refresh: true);

      debugPrint('[Catalog] ✅ Sync completed successfully');
    } catch (e, stackTrace) {
      debugPrint('[Catalog] ❌ Sync error: $e\n$stackTrace');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error sincronizando: ${e.toString()}',
      );
    }
  }
}
