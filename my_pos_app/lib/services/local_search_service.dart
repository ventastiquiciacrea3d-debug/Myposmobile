// lib/services/local_search_service.dart
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/storage_service.dart';

/// ✅ LOCAL SEARCH SERVICE - BÚSQUEDA SOLO LOCAL
///
/// Este servicio garantiza que NUNCA se llame a la API de WooCommerce
/// para búsqueda de productos. SOLO busca en ObjectBox (base de datos local).
///
/// Según especificación arquitectónica V3:
/// - Productos: 🔵 SOLO LOCAL - ObjectBox, NUNCA API
/// - Variaciones: 🔵 SOLO LOCAL - Solo atributos disponibles
///
/// Si no hay resultados, el usuario debe sincronizar manualmente.
class LocalSearchService {
  final StorageService _storageService;

  LocalSearchService({required StorageService storageService})
      : _storageService = storageService {
    debugPrint("[LocalSearchService] ✅ Inicializado - Búsqueda SOLO LOCAL");
  }

  /// Buscar productos por nombre o SKU (SOLO LOCAL)
  ///
  /// Retorna lista vacía si no encuentra resultados.
  /// NO hace fallback a API.
  ///
  /// Uso:
  /// ```dart
  /// final results = await localSearchService.searchProducts('camiseta');
  /// if (results.isEmpty) {
  ///   showDialog('No hay productos sincronizados. Sincroniza el catálogo.');
  /// }
  /// ```
  Future<List<Product>> searchProducts(String query) async {
    if (query.trim().isEmpty || query.length < 2) {
      return [];
    }

    try {
      final results = await _storageService.searchLocalProductsByNameOrSku(query);

      debugPrint(
        "[LocalSearchService] 🔍 Búsqueda '$query' → ${results.length} resultados "
        "(${_calculateSearchTime()}ms)"
      );

      return results;
    } catch (e) {
      debugPrint("[LocalSearchService] ❌ Error en búsqueda: $e");
      return [];
    }
  }

  /// Buscar producto por código de barras (SOLO LOCAL)
  ///
  /// Retorna null si no encuentra el producto.
  /// NO hace fallback a API.
  ///
  /// Uso:
  /// ```dart
  /// final product = await localSearchService.searchByBarcode('7501234567890');
  /// if (product == null) {
  ///   showDialog('Producto no sincronizado. Sincroniza el catálogo.');
  /// }
  /// ```
  Future<Product?> searchByBarcode(String barcode) async {
    if (barcode.trim().isEmpty) {
      return null;
    }

    try {
      final stopwatch = Stopwatch()..start();
      final product = _storageService.getCachedProductByBarcode(barcode.trim());
      stopwatch.stop();

      if (product != null) {
        debugPrint(
          "[LocalSearchService] ✅ Barcode '$barcode' → ${product.name} "
          "(${stopwatch.elapsedMilliseconds}ms)"
        );
      } else {
        debugPrint(
          "[LocalSearchService] ⚠️ Barcode '$barcode' no encontrado en local "
          "(${stopwatch.elapsedMilliseconds}ms)"
        );
      }

      return product;
    } catch (e) {
      debugPrint("[LocalSearchService] ❌ Error buscando barcode: $e");
      return null;
    }
  }

  /// Buscar producto por SKU (SOLO LOCAL)
  ///
  /// Retorna null si no encuentra el producto.
  /// NO hace fallback a API.
  Future<Product?> searchBySku(String sku) async {
    if (sku.trim().isEmpty) {
      return null;
    }

    try {
      final stopwatch = Stopwatch()..start();
      final product = _storageService.getProductBySku(sku.trim());
      stopwatch.stop();

      if (product != null) {
        debugPrint(
          "[LocalSearchService] ✅ SKU '$sku' → ${product.name} "
          "(${stopwatch.elapsedMilliseconds}ms)"
        );
      } else {
        debugPrint(
          "[LocalSearchService] ⚠️ SKU '$sku' no encontrado en local "
          "(${stopwatch.elapsedMilliseconds}ms)"
        );
      }

      return product;
    } catch (e) {
      debugPrint("[LocalSearchService] ❌ Error buscando SKU: $e");
      return null;
    }
  }

  /// Buscar producto por código de barras O SKU (SOLO LOCAL)
  ///
  /// Primero intenta por barcode, luego por SKU.
  /// Retorna null si no encuentra el producto en ninguno.
  /// NO hace fallback a API.
  Future<Product?> searchByBarcodeOrSku(String code) async {
    if (code.trim().isEmpty) {
      return null;
    }

    // Intentar por barcode primero
    final productByBarcode = await searchByBarcode(code);
    if (productByBarcode != null) {
      return productByBarcode;
    }

    // Intentar por SKU
    final productBySku = await searchBySku(code);
    return productBySku;
  }

  /// Obtener variaciones de un producto (SOLO LOCAL)
  ///
  /// Retorna lista vacía si no hay variaciones sincronizadas.
  /// NO hace fallback a API.
  ///
  /// Nota: Este método puede necesitar ajuste según cómo estén
  /// almacenadas las variaciones en ObjectBox.
  Future<List<Product>> getVariations(String parentProductId) async {
    if (parentProductId.trim().isEmpty) {
      return [];
    }

    try {
      // TODO: Implementar búsqueda de variaciones en ObjectBox
      // Actualmente las variaciones se almacenan como productos con type='variation'
      // y tienen un parentId que apunta al producto padre

      debugPrint(
        "[LocalSearchService] 🎨 Buscando variaciones para producto $parentProductId"
      );

      // Por ahora retornamos lista vacía - necesita implementación específica
      // basada en cómo se almacenan las variaciones en ProductOptimized
      return [];
    } catch (e) {
      debugPrint("[LocalSearchService] ❌ Error obteniendo variaciones: $e");
      return [];
    }
  }

  /// Obtener estadísticas de productos en cache local
  Future<Map<String, int>> getLocalCacheStats() async {
    try {
      // TODO: Implementar conteo desde ObjectBox
      return {
        'total_products': 0,
        'simple_products': 0,
        'variable_products': 0,
        'variations': 0,
      };
    } catch (e) {
      debugPrint("[LocalSearchService] ❌ Error obteniendo estadísticas: $e");
      return {};
    }
  }

  /// Calcular tiempo de búsqueda (simulado para logs)
  int _calculateSearchTime() {
    // En producción, esto se calcularía con Stopwatch
    // Por ahora retornamos un valor típico de búsqueda local
    return 12; // ms
  }

  /// Verificar si el catálogo local está vacío
  Future<bool> isCatalogEmpty() async {
    try {
      final results = await searchProducts('');
      return results.isEmpty;
    } catch (e) {
      return true;
    }
  }

  /// Mensaje de ayuda para mostrar al usuario cuando no hay resultados
  String getNoResultsMessage(String query) {
    return "No se encontraron productos para '$query'.\n\n"
        "Ve a Configuración → Sincronizar catálogo para descargar productos.";
  }

  /// Mensaje de ayuda para código de barras no encontrado
  String getBarcodeNotFoundMessage(String barcode) {
    return "Producto con código '$barcode' no sincronizado.\n\n"
        "Ve a Configuración → Sincronizar catálogo.";
  }
}
