// lib/providers/catalog_state.dart
import 'package:flutter/foundation.dart';
import '../models/product.dart';

/// Enum para ordenamiento de productos
enum ProductSortBy {
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
  stockAsc,
  stockDesc,
  recentlyModified,
}

/// Filtros del catálogo
@immutable
class CatalogFilters {
  final bool showInStock;
  final bool showOutOfStock;
  final bool showOnBackorder;
  final Set<String> selectedCategories;
  final ProductSortBy sortBy;

  const CatalogFilters({
    this.showInStock = true,
    this.showOutOfStock = true,
    this.showOnBackorder = true,
    this.selectedCategories = const {},
    this.sortBy = ProductSortBy.nameAsc,
  });

  CatalogFilters copyWith({
    bool? showInStock,
    bool? showOutOfStock,
    bool? showOnBackorder,
    Set<String>? selectedCategories,
    ProductSortBy? sortBy,
  }) {
    return CatalogFilters(
      showInStock: showInStock ?? this.showInStock,
      showOutOfStock: showOutOfStock ?? this.showOutOfStock,
      showOnBackorder: showOnBackorder ?? this.showOnBackorder,
      selectedCategories: selectedCategories ?? this.selectedCategories,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CatalogFilters &&
        other.showInStock == showInStock &&
        other.showOutOfStock == showOutOfStock &&
        other.showOnBackorder == showOnBackorder &&
        setEquals(other.selectedCategories, selectedCategories) &&
        other.sortBy == sortBy;
  }

  @override
  int get hashCode {
    return showInStock.hashCode ^
        showOutOfStock.hashCode ^
        showOnBackorder.hashCode ^
        selectedCategories.hashCode ^
        sortBy.hashCode;
  }
}

/// Estado del catálogo de productos
@immutable
class CatalogState {
  // Datos
  final List<Product> allProducts;
  final List<Product> filteredProducts;
  final Map<String, List<Product>> variationsByParent;
  final List<String> categories;

  // UI State
  final bool isLoading;
  final bool isLoadingMore;
  final bool canLoadMore;
  final String? errorMessage;
  final Set<String> expandedParentIds;

  // Filtros y búsqueda
  final String searchTerm;
  final CatalogFilters filters;

  // Paginación
  final int currentPage;
  final int itemsPerPage;

  // Sincronización
  final DateTime? lastSyncTimestamp;

  const CatalogState({
    this.allProducts = const [],
    this.filteredProducts = const [],
    this.variationsByParent = const {},
    this.categories = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.canLoadMore = false,
    this.errorMessage,
    this.expandedParentIds = const {},
    this.searchTerm = '',
    this.filters = const CatalogFilters(),
    this.currentPage = 1,
    this.itemsPerPage = 50,
    this.lastSyncTimestamp,
  });

  CatalogState copyWith({
    List<Product>? allProducts,
    List<Product>? filteredProducts,
    Map<String, List<Product>>? variationsByParent,
    List<String>? categories,
    bool? isLoading,
    bool? isLoadingMore,
    bool? canLoadMore,
    String? errorMessage,
    Set<String>? expandedParentIds,
    String? searchTerm,
    CatalogFilters? filters,
    int? currentPage,
    int? itemsPerPage,
    DateTime? lastSyncTimestamp,
  }) {
    return CatalogState(
      allProducts: allProducts ?? this.allProducts,
      filteredProducts: filteredProducts ?? this.filteredProducts,
      variationsByParent: variationsByParent ?? this.variationsByParent,
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      errorMessage: errorMessage,
      expandedParentIds: expandedParentIds ?? this.expandedParentIds,
      searchTerm: searchTerm ?? this.searchTerm,
      filters: filters ?? this.filters,
      currentPage: currentPage ?? this.currentPage,
      itemsPerPage: itemsPerPage ?? this.itemsPerPage,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
    );
  }

  factory CatalogState.initial() => const CatalogState();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CatalogState &&
        listEquals(other.allProducts, allProducts) &&
        listEquals(other.filteredProducts, filteredProducts) &&
        mapEquals(other.variationsByParent, variationsByParent) &&
        listEquals(other.categories, categories) &&
        other.isLoading == isLoading &&
        other.isLoadingMore == isLoadingMore &&
        other.canLoadMore == canLoadMore &&
        other.errorMessage == errorMessage &&
        setEquals(other.expandedParentIds, expandedParentIds) &&
        other.searchTerm == searchTerm &&
        other.filters == filters &&
        other.currentPage == currentPage &&
        other.itemsPerPage == itemsPerPage &&
        other.lastSyncTimestamp == lastSyncTimestamp;
  }

  @override
  int get hashCode {
    return allProducts.hashCode ^
        filteredProducts.hashCode ^
        variationsByParent.hashCode ^
        categories.hashCode ^
        isLoading.hashCode ^
        isLoadingMore.hashCode ^
        canLoadMore.hashCode ^
        errorMessage.hashCode ^
        expandedParentIds.hashCode ^
        searchTerm.hashCode ^
        filters.hashCode ^
        currentPage.hashCode ^
        itemsPerPage.hashCode ^
        lastSyncTimestamp.hashCode;
  }
}
