// lib/repositories/product_repository.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:my_pos_mobile_barcode/main.dart';

import '../models/product.dart';
import '../services/woocommerce_service.dart';
import '../services/storage_service.dart';
import '../locator.dart';

class ProductRepository {
  final WooCommerceService _wooCommerceService = getIt<WooCommerceService>();
  final StorageService _storageService = getIt<StorageService>();

  final StreamController<Product> _productUpdateController = StreamController<Product>.broadcast();
  Stream<Product> get onProductUpdatedFromApi => _productUpdateController.stream;

  final Map<String, Map<String, dynamic>> _inMemorySearchCache = {};
  final Map<String, DateTime> _inMemorySearchCacheTimestamp = {};
  static const Duration _inMemoryCacheTTL = Duration(minutes: 5);

  static const Duration productDetailCacheTTL = Duration(minutes: 15);
  static const Duration barcodeSkuProductCacheTTL = Duration(minutes: 15);

  ProductRepository() {
    debugPrint("[ProductRepository] Initialized (SWR Cache Mode).");
  }

  Future<Product?> getProductById(String productId, { bool forceApi = false, Duration ttlDuration = productDetailCacheTTL}) async {
    debugPrint("[ProductRepository.getProductById] Requesting ID: $productId (forceApi: $forceApi)");
    Product? cachedProduct;
    DateTime? cacheTimestamp;

    if (!forceApi) {
      try {
        cachedProduct = _storageService.getProductById(productId, rehydrateAttributes: true);
        if (cachedProduct != null) {
          cacheTimestamp = _storageService.getProductCacheTimestamp(productId);
        } else {
          debugPrint("... Cache MISS for Product $productId.");
        }
      } catch (e) {
        debugPrint("... Cache read error for Product $productId: ${e.toString()}");
      }

      if (cachedProduct != null && cacheTimestamp != null && DateTime.now().isBefore(cacheTimestamp.add(ttlDuration))) {
        debugPrint("... [Cache HIT - Valid TTL] Returning cached Product $productId.");
        // Opcional: Refrescar en segundo plano si se quiere aún más frescura
        // _fetchAndUpdateProductInBackground(productId, isVariation: false);
        return cachedProduct;
      } else if (cachedProduct != null) {
        debugPrint("... [Cache HIT - STALE] Returning stale cached Product $productId. Triggering background update.");
        _fetchAndUpdateProductInBackground(productId, isVariation: false);
        return cachedProduct;
      }
    }

    try {
      final apiProductResponse = await _wooCommerceService.getProductById(productId, useCompute: true);
      final Product apiProduct = await compute(parseProductJsonInBackground, apiProductResponse);

      await _storageService.cacheProduct(apiProduct, fullAttributesWithOptions: apiProduct.fullAttributesWithOptions);
      if (!_productUpdateController.isClosed) {
        _productUpdateController.add(apiProduct);
      }
      return apiProduct;
    } on ProductNotFoundException {
      if (cachedProduct != null) return cachedProduct;
      return null;
    } on AuthenticationException { rethrow;
    } on NetworkException {
      if (cachedProduct != null) return cachedProduct;
      rethrow;
    } on ApiException {
      if (cachedProduct != null) return cachedProduct;
      rethrow;
    }
  }

  Future<void> _fetchAndUpdateProductInBackground(String id, {required bool isVariation, String? parentProductId}) async {
    final String type = isVariation ? "Variation" : "Product";
    final String fullId = isVariation ? "$parentProductId/$id" : id;
    debugPrint("... [Background Update] Starting for $type $fullId");
    try {
      Product? apiItem;
      String apiResponse;
      if (isVariation) {
        if (parentProductId == null) return;
        apiResponse = await _wooCommerceService.getProductById(id, useCompute: true);
      } else {
        apiResponse = await _wooCommerceService.getProductById(id, useCompute: true);
      }

      apiItem = await compute(parseProductJsonInBackground, apiResponse);

      if (apiItem != null) {
        await _storageService.cacheProduct(apiItem, fullAttributesWithOptions: apiItem.fullAttributesWithOptions);
        if (!_productUpdateController.isClosed) {
          _productUpdateController.add(apiItem);
        }
        debugPrint("... [Background Update] SUCCESS for $type $fullId.");
      }
    } catch (e) {
      if (e is! AuthenticationException) {
        debugPrint("... [Background Update] FAILED for $type $fullId: ${e.toString()}");
      }
    }
  }

  Future<Product?> getVariationById(String parentProductId, String variationId, { bool forceApi = false }) async {
    return await getProductById(variationId, forceApi: forceApi);
  }

  Future<Product?> searchProductByBarcodeOrSku(String code, {Duration ttlDuration = barcodeSkuProductCacheTTL, bool searchOnlyAvailable = true}) async {
    if (code.trim().isEmpty) return null;
    final String trimmedId = code.trim();

    Product? cachedProduct = _storageService.getCachedProductByBarcode(trimmedId) ?? _storageService.getProductBySku(trimmedId);
    if (cachedProduct != null) {
      final cacheTimestamp = _storageService.getProductCacheTimestamp(cachedProduct.id);
      if (cacheTimestamp != null && DateTime.now().isBefore(cacheTimestamp.add(ttlDuration))) {
        _fetchAndUpdateProductInBackground(cachedProduct.id, isVariation: cachedProduct.isVariation, parentProductId: cachedProduct.parentId?.toString());
        return cachedProduct;
      }
    }

    try {
      final String? apiProductResponse = await _wooCommerceService.searchProductByBarcodeOrSku(trimmedId, useCompute: true, searchOnlyAvailable: searchOnlyAvailable);
      if (apiProductResponse != null) {
        final Product apiProduct = await compute(parseProductJsonInBackground, apiProductResponse);
        await _storageService.cacheProduct(apiProduct, fullAttributesWithOptions: apiProduct.fullAttributesWithOptions);
        if (!_productUpdateController.isClosed) { _productUpdateController.add(apiProduct); }
        return apiProduct;
      }
      if (cachedProduct != null) return cachedProduct;
      return null;
    } on ProductNotFoundException {
      if (cachedProduct != null) return cachedProduct;
      return null;
    } on NetworkException {
      if (cachedProduct != null) return cachedProduct;
      rethrow;
    } on ApiException {
      if (cachedProduct != null) return cachedProduct;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> searchProductsByTerm(String term, { Function(List<Product> cachedResults)? onCachedResults, bool forceApi = false, int limit = 20, int page = 1, bool searchOnlyAvailable = true }) async {
    final String searchTerm = term.trim();
    if (searchTerm.length < 2) {
      return {'products': [], 'total_products': 0, 'total_pages': 0, 'query': term};
    }

    final cacheKey = '$searchTerm:$limit:$page:$searchOnlyAvailable';
    if (!forceApi && page == 1) {
      final cachedData = _inMemorySearchCache[cacheKey];
      final cacheTimestamp = _inMemorySearchCacheTimestamp[cacheKey];
      if (cachedData != null && cacheTimestamp != null && DateTime.now().isBefore(cacheTimestamp.add(_inMemoryCacheTTL))) {
        return Map<String, dynamic>.from(cachedData)..['query'] = searchTerm;
      }
    }

    if (!forceApi && onCachedResults != null && page == 1) {
      try {
        final localResults = await _storageService.searchLocalProductsByNameOrSku(searchTerm);
        if (localResults.isNotEmpty) {
          var results = localResults.where((p) => p.type != 'variation' && (searchOnlyAvailable ? p.isAvailable : true));
          Future.microtask(() => onCachedResults(results.take(limit).toList()));
        }
      } catch(e) { /* Ignorar errores de caché */ }
    }

    try {
      final apiResponse = await _wooCommerceService.searchProducts(searchTerm, limit: limit, page: page, searchOnlyAvailable: searchOnlyAvailable);

      final Map<String, dynamic> result = {
        'products': apiResponse['products'],
        'total_products': apiResponse['total_products'] ?? 0,
        'total_pages': apiResponse['total_pages'] ?? 1,
      };

      if (page == 1 && (result['products'] as List).isNotEmpty) {
        _inMemorySearchCache[cacheKey] = result;
        _inMemorySearchCacheTimestamp[cacheKey] = DateTime.now();
      }

      for (final p in (result['products'] as List<Product>)) {
        _storageService.cacheProduct(p).catchError((e) => debugPrint("... Background cacheProduct failed for ${p.id}: $e"));
      }

      return { ...result, 'query': searchTerm };
    } catch (e) {
      debugPrint("[ProductRepository.searchProductsByTerm] Error: $e");
      rethrow;
    }
  }

  Future<List<Product>> getAllVariations(String productId, {bool onlyInStock = false}) async {
    if (productId.isEmpty) return [];

    // Obtener el producto padre para el nombre y para saber si necesitamos forzar la carga de la API
    final parentProduct = await getProductById(productId, forceApi: false);
    final variationIds = parentProduct?.variations?.map((id) => id.toString()).toList();

    // Si no tenemos IDs de variaciones o el producto padre no tiene opciones configurables, forzamos la API
    if (variationIds == null || variationIds.isEmpty || (parentProduct?.fullAttributesWithOptions?.isEmpty ?? true)) {
      debugPrint("[getAllVariations] No variation IDs found locally for $productId or attributes missing. Fetching from API.");
      final variationsData = await _wooCommerceService.getAllVariationsForProduct(productId, onlyInStock: onlyInStock);
      final List<Product> variationProducts = [];
      for (final variationJson in variationsData) {
        final variationProduct = Product.fromJson(variationJson, parentNameForVariation: parentProduct?.name);
        await _storageService.cacheProduct(variationProduct);
        variationProducts.add(variationProduct);
      }
      return variationProducts;
    }

    List<Product> cachedVariations = [];
    List<String> missingIds = [];

    for (final id in variationIds) {
      final cached = _storageService.getProductById(id, rehydrateAttributes: false);
      if (cached != null) { cachedVariations.add(cached); } else { missingIds.add(id); }
    }

    if (missingIds.isNotEmpty) {
      debugPrint("[getAllVariations] Found ${cachedVariations.length} variations in cache for $productId. Fetching ${missingIds.length} missing ones.");
      try {
        final batchData = await _wooCommerceService.getProductsBatch(missingIds.map(int.parse).toList());
        for (final entry in batchData.entries) {
          final variationJson = entry.value as Map<String, dynamic>;
          final variationProduct = Product.fromJson(variationJson, parentNameForVariation: parentProduct?.name);
          await _storageService.cacheProduct(variationProduct);
          cachedVariations.add(variationProduct);
        }
      } catch (e) {
        debugPrint("[ProductRepository.getAllVariations] Error fetching missing variations: $e");
      }
    } else {
      debugPrint("[getAllVariations] All ${cachedVariations.length} variations for $productId were found in cache.");
    }

    return onlyInStock ? cachedVariations.where((v) => v.isAvailable).toList() : cachedVariations;
  }

  void dispose() {
    if (!_productUpdateController.isClosed) {
      _productUpdateController.close();
    }
    debugPrint("[ProductRepository] Disposed.");
  }
}