// lib/services/delta_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

import 'woocommerce_service.dart';
import 'storage_service.dart';
import '../models/product.dart';
import '../models/order.dart' as model; // ✅ Para sincronización WC → APP

/// Delta Sync Service - Sincronización Incremental
///
/// Características:
/// - Solo descarga productos que cambiaron (95% reducción de datos)
/// - Usa hashes MD5 para detectar cambios
/// - Cache de última sincronización
/// - Batch fetching para productos específicos
class DeltaSyncService extends ChangeNotifier {
  final WooCommerceService _wooService;
  final StorageService _storageService;

  bool _isSyncing = false;
  DateTime? _lastSync;
  int _productsUpdated = 0;
  int _productsDeleted = 0;

  // Getters
  bool get isSyncing => _isSyncing;
  DateTime? get lastSync => _lastSync;
  int get productsUpdated => _productsUpdated;
  int get productsDeleted => _productsDeleted;

  DeltaSyncService({
    required WooCommerceService wooService,
    required StorageService storageService,
  })  : _wooService = wooService,
        _storageService = storageService;

  /// Inicializar servicio
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncMs = prefs.getInt('delta_last_sync_timestamp');

    if (lastSyncMs != null) {
      _lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncMs * 1000);
    }

    debugPrint('[DeltaSync] Initialized. Last sync: $_lastSync');
  }

  /// Realizar sincronización delta
  Future<void> performDeltaSync({
    bool forceFullSync = false,
  }) async {
    if (_isSyncing) {
      debugPrint('[DeltaSync] Already syncing, skipping...');
      return;
    }

    _isSyncing = true;
    _productsUpdated = 0;
    _productsDeleted = 0;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Obtener timestamp de última sincronización
      int lastSyncTimestamp = 0;

      if (!forceFullSync) {
        lastSyncTimestamp = prefs.getInt('delta_last_sync_timestamp') ?? 0;
      }

      debugPrint('[DeltaSync] 🔄 Starting delta sync since: $lastSyncTimestamp');

      // 1. Obtener lista de cambios (modo compacto)
      final deltaResponse = await _wooService.getDeltaChanges(
        since: lastSyncTimestamp,
        type: 'compact',
        limit: 100,
      );

      final changes = deltaResponse['changes'] as List? ?? [];
      final serverTime = deltaResponse['server_time'] as int? ?? 0;
      final hasMore = deltaResponse['has_more'] as bool? ?? false;

      debugPrint('[DeltaSync] Received ${changes.length} changes');

      if (changes.isEmpty) {
        debugPrint('[DeltaSync] ✅ No changes detected');
        await _updateLastSync(serverTime);
        return;
      }

      // 2. Procesar cambios
      final productIdsToFetch = <int>[];
      final productHashCache = await _loadProductHashCache();

      for (final change in changes) {
        final productId = change['i'] as int;
        final changeType = change['t'] as String;
        final hash = change['h'] as String?;

        if (changeType == 'deleted') {
          // Eliminar producto
          await _deleteProduct(productId);
          _productsDeleted++;
        } else {
          // Verificar si necesitamos actualizar (comparar hash)
          final cachedHash = productHashCache[productId];

          // Si el hash cambió o no tenemos hash, necesitamos descargar
          if (cachedHash != hash) {
            productIdsToFetch.add(productId);
          } else {
            debugPrint('[DeltaSync] Product $productId unchanged (hash match)');
          }
        }
      }

      debugPrint('[DeltaSync] Need to fetch: ${productIdsToFetch.length} products');

      // 3. Fetch en batch solo los productos que cambiaron
      if (productIdsToFetch.isNotEmpty) {
        final productsData = await _wooService.getProductsBatchV310(productIdsToFetch);

        debugPrint('[DeltaSync] Fetched ${productsData.length} products');

        // Guardar productos y actualizar cache de hashes
        for (final productMap in productsData) {
          await _saveProduct(productMap);

          // Actualizar hash cache
          final productId = productMap['id'] as int;
          final hash = _calculateProductHash(productMap);
          productHashCache[productId] = hash;

          _productsUpdated++;
        }

        // Guardar cache de hashes
        await _saveProductHashCache(productHashCache);
      }

      // 4. Si hay más cambios, continuar en background
      if (hasMore) {
        debugPrint('[DeltaSync] ⚠️ More changes available, scheduling next batch...');
        // Programar siguiente batch después de 5 segundos
        Future.delayed(const Duration(seconds: 5), () {
          if (!_isSyncing) {
            performDeltaSync();
          }
        });
      }

      // 5. Actualizar timestamp de última sincronización
      await _updateLastSync(serverTime);

      debugPrint('[DeltaSync] ✅ Delta sync completed');
      debugPrint('[DeltaSync] Updated: $_productsUpdated, Deleted: $_productsDeleted');

    } catch (e) {
      debugPrint('[DeltaSync] ❌ Error: $e');
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Cargar cache de hashes de productos
  Future<Map<int, String>> _loadProductHashCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheJson = prefs.getString('product_hash_cache');

    if (cacheJson == null) return {};

    try {
      final Map<String, dynamic> decoded = jsonDecode(cacheJson);
      return decoded.map((key, value) => MapEntry(int.parse(key), value.toString()));
    } catch (e) {
      debugPrint('[DeltaSync] Error loading hash cache: $e');
      return {};
    }
  }

  /// Guardar cache de hashes de productos
  Future<void> _saveProductHashCache(Map<int, String> cache) async {
    final prefs = await SharedPreferences.getInstance();

    // Limitar tamaño del cache (últimos 1000 productos)
    if (cache.length > 1000) {
      final sortedKeys = cache.keys.toList()..sort((a, b) => b.compareTo(a));
      final limitedCache = Map<int, String>.fromEntries(
        sortedKeys.take(1000).map((key) => MapEntry(key, cache[key]!)),
      );

      final encoded = jsonEncode(limitedCache.map((key, value) => MapEntry(key.toString(), value)));
      await prefs.setString('product_hash_cache', encoded);
    } else {
      final encoded = jsonEncode(cache.map((key, value) => MapEntry(key.toString(), value)));
      await prefs.setString('product_hash_cache', encoded);
    }
  }

  /// Calcular hash MD5 de un producto
  String _calculateProductHash(Map<String, dynamic> productData) {
    // Usar solo campos relevantes para el hash
    final relevantData = {
      'name': productData['name'],
      'sku': productData['sku'],
      'price': productData['price'],
      'stock': productData['stock_quantity'],
      'date_modified': productData['date_modified'], // Importante para detectar cambios
    };

    final dataString = jsonEncode(relevantData);
    final bytes = utf8.encode(dataString);
    final digest = md5.convert(bytes);

    return digest.toString();
  }

  /// Guardar producto en base de datos local
  Future<void> _saveProduct(Map<String, dynamic> productData) async {
    try {
      // ✅ CORREGIDO: Convertir Map JSON a Objeto Product y guardar en ObjectBox
      final product = Product.fromJson(productData);

      await _storageService.cacheProduct(product,
          fullAttributesWithOptions: product.fullAttributesWithOptions
      );

      debugPrint('[DeltaSync] Saved product: ${product.name} (ID: ${product.id})');
    } catch (e) {
      debugPrint('[DeltaSync] ❌ Error saving product ID ${productData['id']}: $e');
    }
  }

  /// Eliminar producto de base de datos local
  Future<void> _deleteProduct(int productId) async {
    try {
      // ✅ CORREGIDO: Llamar a deleteProduct en StorageService
      await _storageService.deleteProduct(productId.toString());

      debugPrint('[DeltaSync] Deleted product: $productId');
    } catch (e) {
      debugPrint('[DeltaSync] ❌ Error deleting product $productId: $e');
    }
  }

  /// Actualizar timestamp de última sincronización
  Future<void> _updateLastSync(int serverTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('delta_last_sync_timestamp', serverTime);

    _lastSync = DateTime.fromMillisecondsSinceEpoch(serverTime * 1000);
    notifyListeners();
  }

  /// Obtener estadísticas de delta sync
  Future<Map<String, dynamic>> getStats() async {
    try {
      return await _wooService.getDeltaStats();
    } catch (e) {
      debugPrint('[DeltaSync] Error getting stats: $e');
      return {};
    }
  }

  /// Resetear cache y forzar full sync
  Future<void> resetAndFullSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('delta_last_sync_timestamp');
    await prefs.remove('product_hash_cache');

    _lastSync = null;
    notifyListeners();

    await performDeltaSync(forceFullSync: true);
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ CSV LÍNEA 34: Sincronización bidireccional WC → APP
  // ═══════════════════════════════════════════════════════════════

  int _ordersUpdated = 0;
  int _inventoryMovementsUpdated = 0;

  int get ordersUpdated => _ordersUpdated;
  int get inventoryMovementsUpdated => _inventoryMovementsUpdated;

  /// Sincronizar pedidos desde WooCommerce hacia la App
  ///
  /// Según CSV línea 34: "cuando se hace desde wordpress deberá enviar
  /// el nuevo pedido a la aplicación para que la aplicación detecte el
  /// nuevo pedido y la aplicación modifique la base de datos como ajuste
  /// en los productos por el nuevo pedido"
  Future<void> syncOrdersFromWooCommerce() async {
    try {
      debugPrint('[DeltaSync] 🔄 Sincronizando pedidos desde WooCommerce...');

      final prefs = await SharedPreferences.getInstance();
      final lastOrderSyncTimestamp = prefs.getInt('last_order_sync_timestamp') ?? 0;

      // Obtener pedidos nuevos/modificados desde última sincronización
      final ordersResponse = await _wooService.getOrdersDelta(
        since: lastOrderSyncTimestamp,
      );

      final orders = ordersResponse['orders'] as List? ?? [];
      final serverTime = ordersResponse['server_time'] as int? ?? 0;

      debugPrint('[DeltaSync] Recibidos ${orders.length} pedidos nuevos/modificados');

      _ordersUpdated = 0;

      for (final orderData in orders) {
        try {
          // Convertir a modelo Order
          final order = model.Order.fromJson(orderData);

          // Guardar en ObjectBox
          await _storageService.saveCompletedOrder(order);

          // RESTAR stock en ObjectBox para cada item del pedido
          for (final item in order.items) {
            final product = await _getProductFromLocal(item.productId);

            if (product != null) {
              final currentStock = product.stockQuantity ?? 0;
              final newStock = currentStock - item.quantity;

              debugPrint(
                '[DeltaSync] 📦 Ajustando stock LOCAL por pedido desde WC:\n'
                '    Producto: ${product.name}\n'
                '    Stock antes: $currentStock\n'
                '    Vendido: ${item.quantity}\n'
                '    Stock después: $newStock'
              );

              // Actualizar stock en ObjectBox
              final updatedProduct = product.copyWith(
                stockQuantity: () => newStock,
                stockStatus: () => newStock > 0 ? 'instock' : 'outofstock',
              );

              await _storageService.cacheProduct(updatedProduct);
            }
          }

          _ordersUpdated++;

        } catch (e) {
          debugPrint('[DeltaSync] ❌ Error procesando pedido: $e');
        }
      }

      // Actualizar timestamp de última sincronización de pedidos
      await prefs.setInt('last_order_sync_timestamp', serverTime);

      debugPrint('[DeltaSync] ✅ Sincronización de pedidos completada: $_ordersUpdated pedidos');
      notifyListeners();

    } catch (e) {
      debugPrint('[DeltaSync] ❌ Error sincronizando pedidos: $e');
    }
  }

  /// Sincronizar movimientos de inventario desde WooCommerce hacia la App
  ///
  /// Según CSV líneas 29-32: "cuando se hace desde el plugin de wordpress
  /// deberá enviar el nuevo movimiento de inventario para que la aplicación
  /// detecte el movimiento de inventario y la aplicación modifique la base
  /// de datos como ajuste en los productos"
  Future<void> syncInventoryMovementsFromWooCommerce() async {
    try {
      debugPrint('[DeltaSync] 🔄 Sincronizando movimientos de inventario desde WC...');

      final prefs = await SharedPreferences.getInstance();
      final lastInventorySyncTimestamp = prefs.getInt('last_inventory_sync_timestamp') ?? 0;

      // Obtener movimientos de inventario nuevos desde última sincronización
      final inventoryResponse = await _wooService.getInventoryDelta(
        since: lastInventorySyncTimestamp,
      );

      final movements = inventoryResponse['movements'] as List? ?? [];
      final serverTime = inventoryResponse['server_time'] as int? ?? 0;

      debugPrint('[DeltaSync] Recibidos ${movements.length} movimientos de inventario');

      _inventoryMovementsUpdated = 0;

      for (final movementData in movements) {
        try {
          final productId = movementData['product_id'] as String;
          final quantityChange = movementData['quantity_change'] as int;
          final movementType = movementData['type'] as String;

          final product = await _getProductFromLocal(productId);

          if (product != null) {
            final currentStock = product.stockQuantity ?? 0;
            final newStock = currentStock + quantityChange;

            debugPrint(
              '[DeltaSync] 📦 Ajustando stock LOCAL por movimiento desde WC:\n'
              '    Producto: ${product.name}\n'
              '    Tipo: $movementType\n'
              '    Stock antes: $currentStock\n'
              '    Cambio: $quantityChange\n'
              '    Stock después: $newStock'
            );

            // Actualizar stock en ObjectBox
            final updatedProduct = product.copyWith(
              stockQuantity: () => newStock,
              stockStatus: () => newStock > 0 ? 'instock' : 'outofstock',
            );

            await _storageService.cacheProduct(updatedProduct);
            _inventoryMovementsUpdated++;
          }

        } catch (e) {
          debugPrint('[DeltaSync] ❌ Error procesando movimiento de inventario: $e');
        }
      }

      // Actualizar timestamp de última sincronización de inventario
      await prefs.setInt('last_inventory_sync_timestamp', serverTime);

      debugPrint(
        '[DeltaSync] ✅ Sincronización de inventario completada: '
        '$_inventoryMovementsUpdated movimientos'
      );
      notifyListeners();

    } catch (e) {
      debugPrint('[DeltaSync] ❌ Error sincronizando inventario: $e');
    }
  }

  /// Sincronización completa bidireccional (productos + pedidos + inventario)
  Future<void> performFullBidirectionalSync() async {
    debugPrint('[DeltaSync] 🔄 Iniciando sincronización bidireccional completa...');

    await performDeltaSync(); // Productos (ya existe)
    await syncOrdersFromWooCommerce(); // Pedidos WC → APP
    await syncInventoryMovementsFromWooCommerce(); // Inventario WC → APP

    debugPrint(
      '[DeltaSync] ✅ Sincronización bidireccional completada:\n'
      '    Productos actualizados: $productsUpdated\n'
      '    Pedidos sincronizados: $ordersUpdated\n'
      '    Movimientos de inventario: $inventoryMovementsUpdated'
    );
  }

  /// Helper: Obtener producto desde ObjectBox
  Future<Product?> _getProductFromLocal(String productId) async {
    try {
      return _storageService.getProductById(productId);
    } catch (e) {
      debugPrint('[DeltaSync] ⚠️ Producto $productId no encontrado en local');
      return null;
    }
  }
}