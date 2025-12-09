// lib/services/product_sync_service.dart
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/product_optimized.dart';
import '../repositories/product_repository.dart';
import 'woocommerce_service.dart';
import 'storage_service.dart';
import 'database_service.dart';
import 'product_converter_service.dart';
import '../locator.dart';

/// Servicio para sincronizar todos los productos de WooCommerce a la base de datos local
class ProductSyncService {
  final WooCommerceService _wooService;
  final ProductRepository _productRepo;
  final StorageService _storageService;

  ProductSyncService({
    required WooCommerceService wooService,
    required ProductRepository productRepo,
    required StorageService storageService,
  })  : _wooService = wooService,
        _productRepo = productRepo,
        _storageService = storageService;

  /// Sincroniza TODOS los productos de WooCommerce a ObjectBox
  ///
  /// - Descarga productos en lotes de 100
  /// - Para productos variables, descarga todas las variaciones
  /// - Guarda todo en ObjectBox
  /// - Reporta progreso mediante callback
  ///
  /// Returns: Número total de productos descargados
  Future<int> syncAllProducts({
    required void Function(int current, int total, String status) onProgress,
  }) async {
    debugPrint('[ProductSync] 🚀🚀🚀 Starting full product sync');
    debugPrint('[ProductSync] WooService: $_wooService');
    debugPrint('[ProductSync] ProductRepo: $_productRepo');
    debugPrint('[ProductSync] StorageService: $_storageService');

    int totalDownloaded = 0;
    int page = 1;
    const perPage = 100;
    bool hasMorePages = true;

    try {
      // Paso 1: Obtener total de productos
      onProgress(0, 0, 'Consultando catálogo...');

      final firstBatchResponse = await _wooService.searchProducts(
        '',  // query vacío para obtener todos
        page: 1,
        limit: perPage,
        searchOnlyAvailable: false,
      );

      final firstBatch = (firstBatchResponse['products'] as List<dynamic>?) ?? [];

      if (firstBatch.isEmpty) {
        debugPrint('[ProductSync] ⚠️ No products found');
        onProgress(0, 0, 'No se encontraron productos');
        return 0;
      }

      // Estimar total (WooCommerce no siempre retorna el header X-WP-Total)
      // Continuamos hasta que no haya más productos
      int estimatedTotal = perPage; // Mínimo estimado

      // Procesar primera página
      totalDownloaded += await _processBatch(
        firstBatch,
        totalDownloaded,
        estimatedTotal,
        onProgress,
      );

      // Descargar páginas restantes
      page = 2;
      while (hasMorePages) {
        debugPrint('[ProductSync] 📄 Fetching page $page');

        final batchResponse = await _wooService.searchProducts(
          '',  // query vacío
          page: page,
          limit: perPage,
          searchOnlyAvailable: false,
        );

        final batch = (batchResponse['products'] as List<dynamic>?) ?? [];

        if (batch.isEmpty) {
          hasMorePages = false;
          break;
        }

        // Actualizar estimado
        estimatedTotal = (page * perPage) + (batch.length < perPage ? batch.length : perPage).toInt();

        totalDownloaded += await _processBatch(
          batch,
          totalDownloaded,
          estimatedTotal,
          onProgress,
        );

        // Si la página retorna menos de perPage, es la última
        if (batch.length < perPage) {
          hasMorePages = false;
        }

        page++;

        // Pequeña pausa para no saturar el servidor
        await Future.delayed(Duration(milliseconds: 200));
      }

      debugPrint('[ProductSync] ✅ Sync completed: $totalDownloaded products downloaded');
      onProgress(totalDownloaded, totalDownloaded, 'Sincronización completa');

      return totalDownloaded;

    } catch (e) {
      debugPrint('[ProductSync] ❌ Error during sync: $e');
      rethrow;
    }
  }

  /// Procesa un lote de productos
  Future<int> _processBatch(
    List<dynamic> batch,
    int currentCount,
    int estimatedTotal,
    void Function(int current, int total, String status) onProgress,
  ) async {
    int processed = 0;

    for (final productData in batch) {
      try {
        // El producto ya viene como Product desde searchProducts(), no necesita conversión
        final product = productData as Product;

        // Guardar producto usando StorageService (patrón correcto)
        await _storageService.cacheProduct(product);
        processed++;

        // Actualizar progreso
        final current = currentCount + processed;
        onProgress(
          current,
          estimatedTotal,
          'Descargando: ${product.name} ($current/$estimatedTotal)',
        );

        // Si es producto variable, descargar variaciones
        if (product.isVariable &&
            product.variations != null &&
            product.variations!.isNotEmpty) {

          await _downloadVariations(
            product,
            current,
            estimatedTotal,
            onProgress,
          );
        }

        // Pequeña pausa cada 10 productos
        if (processed % 10 == 0) {
          await Future.delayed(Duration(milliseconds: 50));
        }

      } catch (e) {
        debugPrint('[ProductSync] ⚠️ Error processing product: $e');
        // Continuar con el siguiente producto
      }
    }

    return processed;
  }

  /// Descarga todas las variaciones de un producto variable
  Future<void> _downloadVariations(
    Product product,
    int currentCount,
    int estimatedTotal,
    void Function(int current, int total, String status) onProgress,
  ) async {
    try {
      debugPrint('[ProductSync] 📦 Downloading variations for ${product.name} (${product.variations!.length} variations)');

      onProgress(
        currentCount,
        estimatedTotal,
        'Descargando variaciones de ${product.name}...',
      );

      // Usar ProductRepository que ya tiene la lógica optimizada
      await _productRepo.getAllVariations(product.id);

      debugPrint('[ProductSync] ✅ Variations cached for ${product.name}');

    } catch (e) {
      debugPrint('[ProductSync] ⚠️ Error downloading variations for ${product.name}: $e');
      // No lanzar error, continuar con otros productos
    }
  }

  /// Limpia la caché de productos antes de sincronizar
  Future<void> clearProductCache() async {
    debugPrint('[ProductSync] 🗑️ Clearing product cache');
    try {
      // Acceder a DatabaseService directamente para operaciones admin
      final dbService = getIt<DatabaseService>();
      final box = dbService.store.box<ProductOptimized>();
      final count = box.count();
      box.removeAll();
      debugPrint('[ProductSync] ✅ Product cache cleared ($count products removed)');
    } catch (e) {
      debugPrint('[ProductSync] ❌ Error clearing cache: $e');
    }
  }

  /// Obtiene estadísticas de la base de datos local
  Future<Map<String, int>> getLocalStats() async {
    try {
      // Acceder a DatabaseService directamente para obtener stats
      final dbService = getIt<DatabaseService>();
      final converter = ProductConverterService(dbService);
      final box = dbService.store.box<ProductOptimized>();

      final allProductsOptimized = box.getAll();

      int simpleCount = 0;
      int variableCount = 0;
      int variationCount = 0;

      for (final productOpt in allProductsOptimized) {
        // Convertir a Product para acceder al campo 'type'
        final product = converter.optimizedToProduct(productOpt);

        if (product.type == 'variation') {
          variationCount++;
        } else if (product.type == 'variable') {
          variableCount++;
        } else {
          simpleCount++;
        }
      }

      return {
        'total': allProductsOptimized.length,
        'simple': simpleCount,
        'variable': variableCount,
        'variations': variationCount,
      };
    } catch (e) {
      debugPrint('[ProductSync] ❌ Error getting stats: $e');
      return {
        'total': 0,
        'simple': 0,
        'variable': 0,
        'variations': 0,
      };
    }
  }
}
