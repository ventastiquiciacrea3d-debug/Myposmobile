// lib/providers/inventory_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../models/inventory_movement.dart';

part 'inventory_state.freezed.dart';

/// Product category grouping for inventory view
class ProductCategoryGroup {
  final int id;
  final String name;
  final List<Product> parentProducts;
  final Map<String, List<Product>> variationsByParentId;

  ProductCategoryGroup({
    required this.id,
    required this.name,
    required this.parentProducts,
    required this.variationsByParentId,
  });

  ProductCategoryGroup copyWith({
    int? id,
    String? name,
    List<Product>? parentProducts,
    Map<String, List<Product>>? variationsByParentId,
  }) {
    return ProductCategoryGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      parentProducts: parentProducts ?? this.parentProducts,
      variationsByParentId: variationsByParentId ?? this.variationsByParentId,
    );
  }
}

/// ✓ FASE 2 RIVERPOD: Estado inmutable para Inventory management
@freezed
class InventoryState with _$InventoryState {
  const factory InventoryState({
    // Inventory movements (history) with pagination
    @Default([]) List<InventoryMovement> inventoryMovements,
    @Default(1) int movementsCurrentPage,
    @Default(false) bool movementsIsLoading,
    @Default(false) bool movementsIsLoadingMore,
    @Default(true) bool movementsCanLoadMore,
    String? movementsError,
    @Default(1) int movementsTotalPages,

    // Inventory products management
    @Default([]) List<Product> inventoryProducts,
    @Default(false) bool isLoadingProducts,
    String? errorMessage,

    // Background task status
    String? backgroundTaskMessage,
    @Default(false) bool isBackgroundTaskRunning,

    // Product selection for batch operations
    @Default({}) Set<String> selectedProductIds,

    // Categorized view
    @Default([]) List<ProductCategoryGroup> categorizedProductGroups,
    @Default([]) List<Map<String, dynamic>> allCategories,
    @Default({}) Set<int> expandedCategoryIds,
    @Default({}) Set<String> expandedVariableProductIds,
  }) = _InventoryState;

  const InventoryState._();

  factory InventoryState.initial() => const InventoryState();

  bool get hasError => errorMessage != null;
  bool get hasMovementsError => movementsError != null;
  bool get hasSelectedProducts => selectedProductIds.isNotEmpty;
  int get selectedProductCount => selectedProductIds.length;
}
