import 'package:flutter/foundation.dart';
import '../models/product_compact.dart';
import 'database_service.dart';
import '../objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as obx;

/// Servicio de carga inteligente en 3 niveles
class LazyLoadingService extends ChangeNotifier {
  final DatabaseService _db;

  /// Cache en memoria (L1) - Top 20 productos
  final Map<int, ProductCompact> _hotCache = {};
  DateTime _hotCacheExpiry = DateTime.now();

  LazyLoadingService(this._db);

  // ==================== NIVEL 1: DATOS ESENCIALES ====================

  /// Cargar datos esenciales al iniciar app
  /// Solo: SKU, Barcode, Nombre, Stock
  /// Tiempo: <500ms para 10,000 productos
  Future<void> loadEssentialData() async {
    final stopwatch = Stopwatch()..start();

    debugPrint("[LazyLoading] Loading essential data...");

    // ObjectBox carga solo índices automáticamente (lazy by design)
    final box = _db.store.box<ProductCompact>();
    final count = box.count();

    stopwatch.stop();

    debugPrint("[LazyLoading] ✅ $count products indexed in ${stopwatch.elapsedMilliseconds}ms");
  }

  /// Actualizar hot cache con top productos
  Future<void> refreshHotCache() async {
    if (DateTime.now().isBefore(_hotCacheExpiry)) {
      return; // Cache aún válido
    }

    debugPrint("[LazyLoading] Refreshing hot cache...");

    final box = _db.store.box<ProductCompact>();

    // Top 20 productos con más stock
    final query = box.query()
      .order(ProductCompact_.stockQuantity, flags: obx.Order.descending)
      .build();

    query.limit = 20;
    final topProducts = query.find();
    query.close();

    _hotCache.clear();
    for (final product in topProducts) {
      _hotCache[product.id] = product;
    }

    _hotCacheExpiry = DateTime.now().add(const Duration(minutes: 5));

    debugPrint("[LazyLoading] ✅ Hot cache refreshed (${_hotCache.length} products)");
  }

  /// Buscar producto en hot cache (< 1ms)
  ProductCompact? getFromHotCache(int productId) {
    return _hotCache[productId];
  }

  // ==================== NIVEL 2: DETALLES BAJO DEMANDA ====================

  /// Cargar detalles completos de producto
  /// Tiempo: <50ms por producto
  Future<ProductCompact?> loadProductDetails(int productId) async {
    // Verificar hot cache primero
    var product = getFromHotCache(productId);
    if (product != null) {
      debugPrint("[LazyLoading] Product $productId found in hot cache");
      return product;
    }

    // Buscar en ObjectBox
    final box = _db.store.box<ProductCompact>();
    final query = box.query(ProductCompact_.id.equals(productId)).build();
    product = query.findFirst();
    query.close();

    if (product != null) {
      debugPrint("[LazyLoading] Product ${product.name} loaded from DB");

      // Promover a hot cache
      _hotCache[productId] = product;
    }

    return product;
  }

  // ==================== BÚSQUEDAS OPTIMIZADAS ====================

  /// Búsqueda por SKU (O(log n) - ultra rápida)
  Future<ProductCompact?> searchBySKU(String sku) async {
    final box = _db.store.box<ProductCompact>();
    final query = box.query(ProductCompact_.sku.equals(sku)).build();
    final product = query.findFirst();
    query.close();

    return product;
  }

  /// Búsqueda por Barcode (O(log n))
  Future<ProductCompact?> searchByBarcode(String barcode) async {
    final box = _db.store.box<ProductCompact>();
    final query = box.query(ProductCompact_.barcode.equals(barcode)).build();
    final product = query.findFirst();
    query.close();

    return product;
  }

  /// Búsqueda por nombre (O(log n) con índice full-text)
  Future<List<ProductCompact>> searchByName(String term, {int limit = 20}) async {
    final box = _db.store.box<ProductCompact>();

    final query = box.query(
      ProductCompact_.name.contains(term, caseSensitive: false)
    ).order(ProductCompact_.name).build();

    query.limit = limit;
    final results = query.find();
    query.close();

    return results;
  }

  /// Estadísticas de cache
  Map<String, dynamic> getCacheStats() {
    return {
      'hot_cache_size': _hotCache.length,
      'hot_cache_expiry': _hotCacheExpiry.toString(),
      'total_products': _db.store.box<ProductCompact>().count(),
    };
  }
}
