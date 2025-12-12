// lib/repositories/product_repository.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
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
        return cachedProduct;
      } else if (cachedProduct != null) {
        debugPrint("... [Cache HIT - STALE] Returning stale cached Product $productId. Delta Sync will update when needed.");
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

  Future<Product?> getVariationById(String parentProductId, String variationId, { bool forceApi = false }) async {
    return await getProductById(variationId, forceApi: forceApi);
  }

  /// ✅ SOLO LOCAL: Buscar producto por código de barras o SKU
  ///
  /// Según especificación V3: Productos 🔵 SOLO LOCAL - ObjectBox, NUNCA API
  ///
  /// NO hace fallback a API. Si no encuentra el producto, retorna null.
  /// El usuario debe sincronizar el catálogo manualmente.
  Future<Product?> searchProductByBarcodeOrSku(String code, {Duration ttlDuration = barcodeSkuProductCacheTTL, bool searchOnlyAvailable = true}) async {
    if (code.trim().isEmpty) return null;
    final String trimmedId = code.trim();

    // ✅ Buscar SOLO en ObjectBox (local)
    final Product? cachedProduct = _storageService.getCachedProductByBarcode(trimmedId)
        ?? _storageService.getProductBySku(trimmedId);

    if (cachedProduct != null) {
      debugPrint("[ProductRepository] ✅ Barcode/SKU '$trimmedId' → ${cachedProduct.name} (LOCAL)");
      return cachedProduct;
    }

    // ✅ NO hacer fallback a API - retornar null
    debugPrint("[ProductRepository] ⚠️ Barcode/SKU '$trimmedId' no encontrado en local");
    return null;
  }

  Future<Map<String, dynamic>> searchProductsByTerm(String term, { Function(List<Product> cachedResults)? onCachedResults, bool forceApi = false, bool localOnly = false, int limit = 20, int page = 1, bool searchOnlyAvailable = true }) async {
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

    // ✅ FIX: Buscar primero en BD local
    try {
      final localResults = await _storageService.searchLocalProductsByNameOrSku(searchTerm);
      if (localResults.isNotEmpty) {
        var filteredResults = localResults.where((p) => p.type != 'variation' && (searchOnlyAvailable ? p.isAvailable : true)).toList();

        // Si hay resultados locales y solo queremos búsqueda local, retornar inmediatamente
        if (localOnly || (!forceApi && page == 1 && filteredResults.length >= limit)) {
          final paginatedResults = filteredResults.skip((page - 1) * limit).take(limit).toList();
          debugPrint("[ProductRepository.searchProductsByTerm] ✅ Using LOCAL results only: ${paginatedResults.length} products found");

          return {
            'products': paginatedResults,
            'total_products': filteredResults.length,
            'total_pages': (filteredResults.length / limit).ceil(),
            'query': searchTerm,
          };
        }

        // Mostrar resultados locales via callback mientras se hace API call en segundo plano
        if (!forceApi && onCachedResults != null && page == 1) {
          Future.microtask(() => onCachedResults(filteredResults.take(limit).toList()));
        }
      } else if (localOnly) {
        // Si solo queremos búsqueda local y no hay resultados, retornar vacío
        debugPrint("[ProductRepository.searchProductsByTerm] ⚠️ No local results found for: $searchTerm");
        return {'products': [], 'total_products': 0, 'total_pages': 0, 'query': searchTerm};
      }
    } catch(e) {
      debugPrint("[ProductRepository.searchProductsByTerm] ⚠️ Error searching locally: $e");
      if (localOnly) rethrow;
    }

    // ✅ Solo llamar API si NO es localOnly
    if (localOnly) {
      return {'products': [], 'total_products': 0, 'total_pages': 0, 'query': searchTerm};
    }

    try {
      debugPrint("[ProductRepository.searchProductsByTerm] 📡 Fetching from API: $searchTerm");
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

  /// ✓ FASE 2 BATCH API: Obtiene múltiples productos en una sola petición
  /// Resuelve el problema N+1 al cargar pedidos con múltiples items
  Future<Map<String, Product>> getProductsByIds(List<String> productIds, {bool forceApi = false, bool lightweight = false}) async {
    if (productIds.isEmpty) return {};

    final Map<String, Product> result = {};
    final List<int> idsToFetch = [];

    // Si no forzamos API, intentar obtener del cache primero
    if (!forceApi) {
      for (final id in productIds) {
        final cached = _storageService.getProductById(id, rehydrateAttributes: !lightweight);
        if (cached != null) {
          result[id] = cached;
        } else {
          idsToFetch.add(int.parse(id));
        }
      }
    } else {
      idsToFetch.addAll(productIds.map(int.parse));
    }

    // Si no hay nada que fetchear, retornar cache
    if (idsToFetch.isEmpty) {
      debugPrint("[ProductRepository.getProductsByIds] All ${productIds.length} products found in cache");
      return result;
    }

    // Fetchear productos faltantes en batch
    try {
      debugPrint("[ProductRepository.getProductsByIds] Fetching ${idsToFetch.length} products via batch API");
      final batchData = await _wooCommerceService.getProductsBatch(idsToFetch, lightweight: lightweight);

      final List<Product> productsToCache = [];
      final Map<String, List<Map<String, dynamic>>> attributesMap = {};

      for (final entry in batchData.entries) {
        final productId = entry.key;
        final productJson = entry.value as Map<String, dynamic>;
        final product = Product.fromJson(productJson);

        productsToCache.add(product);
        if (product.fullAttributesWithOptions != null && product.fullAttributesWithOptions!.isNotEmpty) {
          attributesMap[productId] = product.fullAttributesWithOptions!;
        }

        // Emitir evento de actualización
        if (!_productUpdateController.isClosed) {
          _productUpdateController.add(product);
        }

        result[productId] = product;
      }

      // ✓ FASE 2 BATCH API: Cachear TODOS los productos en una sola operación Hive
      if (productsToCache.isNotEmpty) {
        await _storageService.cacheProductsBatch(productsToCache, fullAttributesMap: attributesMap);
      }

      debugPrint("[ProductRepository.getProductsByIds] Batch fetch complete: ${result.length}/${productIds.length} products loaded");
      return result;
    } catch (e) {
      debugPrint("[ProductRepository.getProductsByIds] Error fetching batch: $e");
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