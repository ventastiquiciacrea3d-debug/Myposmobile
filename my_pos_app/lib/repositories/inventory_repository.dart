// lib/repositories/inventory_repository.dart
import 'dart:async'; // Importar para Future
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_pos_mobile_barcode/services/woocommerce_service.dart';
import 'package:collection/collection.dart';

import '../models/inventory_movement.dart';
import '../models/product.dart' as app_product;
import '../locator.dart';
import '../config/constants.dart';
import '../repositories/product_repository.dart';

class InventoryRepository {
  final WooCommerceService _wooCommerceService = getIt<WooCommerceService>();
  final ProductRepository _productRepository = getIt<ProductRepository>();
  String? errorMessage;

  InventoryRepository() {
    debugPrint("[InventoryRepository] Initialized.");
  }

  Future<Map<String, dynamic>> getInventoryMovements({
    int page = 1,
    int perPage = 25,
    String? searchTerm,
    bool forceApi = false,
  }) async {
    debugPrint("[InventoryRepository] Getting inventory movements (force: $forceApi, page: $page, search: '$searchTerm')...");
    final Box<InventoryMovement> movementBox = await Hive.openBox<InventoryMovement>(hiveInventoryMovementsBoxName);
    List<InventoryMovement> cachedMovements = movementBox.values.toList()..sort((a, b) => b.date.compareTo(a.date));

    List<InventoryMovement> filterMovements(List<InventoryMovement> movements) {
      if (searchTerm == null || searchTerm.trim().isEmpty) return movements;
      final term = searchTerm.toLowerCase().trim();
      return movements.where((m) {
        return m.description.toLowerCase().contains(term) ||
            m.userName?.toLowerCase().contains(term) == true ||
            m.items.any((item) =>
            item.productName.toLowerCase().contains(term) ||
                item.sku.toLowerCase().contains(term));
      }).toList();
    }

    if (forceApi || cachedMovements.isEmpty) {
      debugPrint("... Cache is empty or forceApi is true. Fetching from server...");
      try {
        cachedMovements = await _fetchAndCacheInventoryHistory(movementBox);
      } catch (e) {
        if (cachedMovements.isEmpty) rethrow;
        debugPrint("... API fetch failed, using stale cache as fallback. Error: $e");
      }
    } else {
      _fetchAndCacheInventoryHistory(movementBox).catchError((e) {
        debugPrint("[InventoryRepository] Background history fetch failed: $e");
        return Future.value(<InventoryMovement>[]);
      });
    }

    final filtered = filterMovements(cachedMovements);
    final totalItems = filtered.length;
    final totalPages = (totalItems / perPage).ceil();
    final startIndex = (page - 1) * perPage;
    final paginatedMovements = filtered.skip(startIndex).take(perPage).toList();

    return {
      'movements': paginatedMovements,
      'total_pages': totalPages,
    };
  }

  Future<List<InventoryMovement>> _fetchAndCacheInventoryHistory(Box<InventoryMovement> movementBox) async {
    final serverMovements = await _wooCommerceService.getInventoryHistory();
    await movementBox.clear();
    await movementBox.putAll({for (var m in serverMovements) m.id: m});
    debugPrint("... Fetched and synced ${serverMovements.length} movements from server.");
    return serverMovements..sort((a, b) => b.date.compareTo(a.date));
  }

  // (El resto del archivo permanece sin cambios)

  Future<void> submitInventoryAdjustment(InventoryMovement movement) async {
    errorMessage = null;
    try {
      await _wooCommerceService.submitInventoryAdjustment(movement);
    } on ApiException catch (e) {
      errorMessage = e.message;
      rethrow;
    }
  }

  Future<void> saveInventoryMovement(InventoryMovement movement) async {
    debugPrint("[InventoryRepository] Saving inventory movement ID: ${movement.id}");
    try {
      final Box<InventoryMovement> movementBox = await Hive.openBox<InventoryMovement>(hiveInventoryMovementsBoxName);
      await movementBox.put(movement.id, movement);
      debugPrint("... Movement ID ${movement.id} saved successfully.");
    } catch (e) {
      debugPrint("Error in InventoryRepository saving movement: $e");
      throw Exception("Failed to save inventory movement: $e");
    }
  }

  Future<void> deleteInventoryMovement(String movementId) async {
    debugPrint("[InventoryRepository] Deleting inventory movement ID: $movementId");
    try {
      final Box<InventoryMovement> movementBox = await Hive.openBox<InventoryMovement>(hiveInventoryMovementsBoxName);
      await movementBox.delete(movementId);
      debugPrint("... Movement ID ${movementId} deleted successfully.");
    } catch (e) {
      debugPrint("Error in InventoryRepository deleting movement: $e");
      throw Exception("Failed to delete inventory movement: $e");
    }
  }

  Future<List<app_product.Product>> getAllManagedStockProducts() async {
    try {
      final rawProducts = await _wooCommerceService.getAllProductsWithStockManagement();
      return rawProducts.map((data) => app_product.Product.fromJson(data)).toList();
    } catch (e) {
      debugPrint("Error in InventoryRepository getting all managed stock products: $e");
      rethrow;
    }
  }

  Future<String> activateManageStockForAllVariables() async {
    debugPrint("[InventoryRepository] Activating stock management for all variable products.");
    try {
      final response = await _wooCommerceService.activateManageStockForAllVariables();
      return response['message'] ?? 'Proceso completado sin mensaje.';
    } catch(e) {
      debugPrint("Error in InventoryRepository activating manage stock: $e");
      rethrow;
    }
  }

  Future<String> deactivateManageStockForAllVariables() async {
    debugPrint("[InventoryRepository] Deactivating stock management for all variable products.");
    try {
      final response = await _wooCommerceService.deactivateManageStockForAllVariables();
      return response['message'] ?? 'Proceso completado sin mensaje.';
    } catch(e) {
      debugPrint("Error in InventoryRepository deactivating manage stock: $e");
      rethrow;
    }
  }

  Future<String> activateManageStockForAllParents() async {
    debugPrint("[InventoryRepository] Activating stock management for all parent products.");
    try {
      final response = await _wooCommerceService.activateManageStockForAllParents();
      return response['message'] ?? 'Proceso completado sin mensaje.';
    } catch(e) {
      debugPrint("Error in InventoryRepository activating manage stock for parents: $e");
      rethrow;
    }
  }

  Future<String> deactivateManageStockForAllParents() async {
    debugPrint("[InventoryRepository] Deactivating stock management for all parent products.");
    try {
      final response = await _wooCommerceService.deactivateManageStockForAllParents();
      return response['message'] ?? 'Proceso completado sin mensaje.';
    } catch(e) {
      debugPrint("Error in InventoryRepository deactivating manage stock for parents: $e");
      rethrow;
    }
  }
  Future<List<Map<String, dynamic>>> getProductCategories() async {
    debugPrint("[InventoryRepository] Getting all product categories.");
    try {
      return await _wooCommerceService.getProductCategories();
    } catch(e) {
      debugPrint("Error in InventoryRepository getting categories: $e");
      rethrow;
    }
  }

  Future<List<app_product.Product>> getInventoryProducts({
    String? searchTerm,
    bool forceApi = false,
  }) async {
    debugPrint("[InventoryRepository] Getting inventory products. Search: '$searchTerm', ForceAPI: $forceApi");
    try {
      if (searchTerm != null && searchTerm.trim().isNotEmpty) {
        final apiResponse = await _productRepository.searchProductsByTerm(
            searchTerm.trim(), limit: 100, forceApi: forceApi, searchOnlyAvailable: false
        );
        return apiResponse['products'];
      } else {
        if (_wooCommerceService.connectionMode == 'plugin') {
          final rawProducts = await _wooCommerceService.getAllProductsWithStockManagement();
          return rawProducts.map((data) => app_product.Product.fromJson(data)).toList();
        }

        List<Map<String, dynamic>> rawProducts = [];
        int page = 1;
        while (true) {
          final pageResults = await _wooCommerceService.fetchProductsForCatalogSync(page: page, perPage: 100);
          if (pageResults.isEmpty) break;
          rawProducts.addAll(pageResults);
          page++;
        }

        final List<app_product.Product> products = rawProducts.map((data) => app_product.Product.fromJson(data)).toList();
        final List<app_product.Product> allProducts = [];
        allProducts.addAll(products.where((p) => p.isSimple));

        final variableProducts = products.where((p) => p.isVariable).toList();
        for (final parent in variableProducts) {
          allProducts.add(parent);
          final variationsData = await _wooCommerceService.getAllVariationsForProduct(parent.id);
          for (final variationJson in variationsData) {
            allProducts.add(app_product.Product.fromJson(variationJson, parentNameForVariation: parent.name));
          }
        }
        return allProducts;
      }
    } catch (e) {
      debugPrint("Error in InventoryRepository getting products: $e");
      if (e is ApiException || e is NetworkException || e is InvalidDataException) rethrow;
      throw Exception("Failed to load inventory products: ${e.toString()}");
    }
  }


  Future<app_product.Product?> getInventoryProductById(String productId, {bool forceApi = false}) async {
    return await _productRepository.getProductById(productId, forceApi: forceApi);
  }

  Future<app_product.Product?> getInventoryVariationById(String parentProductId, String variationId, {bool forceApi = false}) async {
    return await _productRepository.getVariationById(parentProductId, variationId, forceApi: forceApi);
  }

  Future<void> updateMultipleProductsStock(List<Map<String, dynamic>> updates) async {
    debugPrint("[InventoryRepository] Updating stock for ${updates.length} products in batch.");
    try {
      await _wooCommerceService.updateMultipleProductsStock(updates);
      debugPrint("... Batch stock update sent successfully.");
      for (final update in updates) {
        final productId = update['product_id']?.toString();
        final variationId = update['variation_id']?.toString();
        if (variationId != null && variationId != '0' && productId != null) {
          await _productRepository.getVariationById(productId, variationId, forceApi: true);
        } else if (productId != null) {
          await _productRepository.getProductById(productId, forceApi: true);
        }
      }
    } catch (e) {
      debugPrint("Error in InventoryRepository updating multiple stocks: $e");
      rethrow;
    }
  }

  Future<void> resetAllStockToZero() async {
    debugPrint("[InventoryRepository] resetAllStockToZero() llamado. Esta función requiere implementación en el backend.");
    throw UnimplementedError("La funcionalidad de resetear todo el stock a cero no está implementada en el servicio API.");
  }


  void dispose() {
    debugPrint("[InventoryRepository] Disposed.");
  }
}