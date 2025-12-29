// lib/services/storage_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart' hide Box;
import 'package:hive/hive.dart' as hive;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/order.dart' as model;
import '../config/constants.dart';
import '../models/sync_operation.dart';
import '../locator.dart';
import '../models/product_optimized.dart';
import '../models/order_compact.dart';
import '../services/database_service.dart';
import '../services/product_converter_service.dart';
import '../services/order_converter_service.dart';
import '../objectbox.g.dart'; // Para query builders

class StorageService {
  // ✅ HIVE - Solo para SyncQueue (Settings migrado a SharedPreferences)
  hive.Box<SyncOperation>? _syncQueueBox;

  // ✅ OBJECTBOX - Base de datos principal
  DatabaseService? _db;
  ProductConverterService? _converter;
  OrderConverterService? _orderConverter;

  SharedPreferences get _prefs => getIt<SharedPreferences>();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  StorageService();

  // 📌 CORRECCIÓN CLAVE: Añadir isBackgroundService para evitar reabrir ObjectBox
  Future<void> init({bool isBackgroundService = false}) async {
    debugPrint("[StorageService] init: Initializing storage. Background Mode: $isBackgroundService");
    try {
      // ✅ OBJECTBOX - Base de datos principal (solo en el hilo principal)
      if (!isBackgroundService) {
        _db = await DatabaseService.getInstance();
        _converter = ProductConverterService(_db!);
        _orderConverter = OrderConverterService();
      } else {
        debugPrint("[StorageService] ⏭️ Skipping ObjectBox initialization in background isolate.");
      }

      // ✅ MIGRACIÓN UNA VEZ: Migrar datos de settingsBox a SharedPreferences si es necesario
      await _migrateSettingsBoxToPrefs();

      // ✅ HIVE - Solo para SyncQueue (Disponible en ambos isolates)
      _syncQueueBox = await Hive.openBox<SyncOperation>(hiveSyncQueueBoxName);

      debugPrint("[StorageService] init: ✅ Initialization complete. DB (ObjectBox) status: ${isBackgroundService ? 'Skipped' : 'Initialized'}");
    } catch (e, stacktrace) {
      debugPrint("[StorageService] !! FATAL ERROR initializing storage: $e\n$stacktrace");
      rethrow;
    }
  }

  /// ✅ MIGRACIÓN UNA VEZ: Migra datos de settingsBox (Hive) a SharedPreferences
  Future<void> _migrateSettingsBoxToPrefs() async {
    const migrationKey = 'settings_box_migrated_v1';

    // Verificar si ya se migró
    if (_prefs.getBool(migrationKey) == true) {
      debugPrint("[StorageService] ⏭️ Settings migration already completed, skipping...");
      return;
    }

    debugPrint("[StorageService] 🔄 Starting settings migration from Hive to SharedPreferences...");

    hive.Box? tempBox;
    try {
      // Abrir temporalmente settingsBox solo para migración
      tempBox = await Hive.openBox(hiveSettingsBoxName);

      int migratedCount = 0;

      // Migrar todos los timestamps (last_sync, ts_prod_*, ts_order_*, order_history_*)
      for (final key in tempBox.keys) {
        final value = tempBox.get(key);

        // Solo migrar timestamps (String ISO 8601)
        if (value is String && key.toString().startsWith('ts_')) {
          final dt = DateTime.tryParse(value);
          if (dt != null) {
            await _prefs.setInt(key.toString(), dt.millisecondsSinceEpoch);
            migratedCount++;
          }
        } else if (value is String && key == 'last_sync') {
          final dt = DateTime.tryParse(value);
          if (dt != null) {
            await _prefs.setInt('last_sync_ms', dt.millisecondsSinceEpoch);
            migratedCount++;
          }
        } else if (value is String && key.toString().startsWith('order_history_')) {
          final dt = DateTime.tryParse(value);
          if (dt != null) {
            await _prefs.setInt(key.toString(), dt.millisecondsSinceEpoch);
            migratedCount++;
          }
        }
      }

      // Cerrar la caja temporal después de migrar
      await tempBox.close();

      // Marcar migración como completada
      await _prefs.setBool(migrationKey, true);

      debugPrint("[StorageService] ✅ Settings migration completed: $migratedCount timestamps migrated");
    } catch (e) {
      debugPrint("[StorageService] ❌ Error during settings migration: $e");
      // Asegurar que se cierra la caja en caso de error
      if (tempBox?.isOpen == true) {
        await tempBox?.close();
      }
    }
  }

  // --- JWT & Device Credentials ---
  Future<String> getOrCreateDeviceUuid() async {
    String? uuid = await _secureStorage.read(key: secureDeviceUuidKey);
    if (uuid == null || uuid.isEmpty) {
      uuid = const Uuid().v4();
      await _secureStorage.write(key: secureDeviceUuidKey, value: uuid);
    }
    return uuid;
  }
  Future<String?> getDeviceUuid() async => await _secureStorage.read(key: secureDeviceUuidKey);

  // Métodos para Access Token
  Future<void> saveAccessToken(String token) async => await _secureStorage.write(key: secureAccessTokenKey, value: token);
  Future<String?> getAccessToken() async => await _secureStorage.read(key: secureAccessTokenKey);
  Future<void> deleteAccessToken() async => await _secureStorage.delete(key: secureAccessTokenKey);

  // Métodos para Refresh Token
  Future<void> saveRefreshToken(String token) async => await _secureStorage.write(key: secureRefreshTokenKey, value: token);
  Future<String?> getRefreshToken() async => await _secureStorage.read(key: secureRefreshTokenKey);
  Future<void> deleteRefreshToken() async => await _secureStorage.delete(key: secureRefreshTokenKey);

  // --- Limpieza de Credenciales ---
  Future<void> clearApiCredentials() async {
    await _secureStorage.delete(key: secureApiUrlKey);
    await _secureStorage.delete(key: secureConsumerKeyKey);
    await _secureStorage.delete(key: secureConsumerSecretKey);
    await _secureStorage.delete(key: secureMyPosApiKey);
    await deleteAccessToken();
    await deleteRefreshToken();
    await _secureStorage.delete(key: secureJwtTokenKey); // Limpiar clave antigua
    debugPrint("[StorageService] All API credentials cleared.");
  }

  bool _isBoxReady<T>(hive.Box<T>? box, String boxName) {
    if (box == null || !box.isOpen) {
      debugPrint("[StorageService] Error: Box '$boxName' is not initialized or not open.");
      return false;
    }
    return true;
  }

  Future<void> saveConnectionMode(String mode) async => await _prefs.setString(connectionModePrefKey, mode);
  String getConnectionMode() => _prefs.getString(connectionModePrefKey) ?? 'plugin';
  Future<void> saveApiUrl(String url) async => await _secureStorage.write(key: secureApiUrlKey, value: url);
  Future<String?> getApiUrl() async => await _secureStorage.read(key: secureApiUrlKey);
  Future<void> saveConsumerKey(String key) async => await _secureStorage.write(key: secureConsumerKeyKey, value: key);
  Future<String?> getConsumerKey() async => await _secureStorage.read(key: secureConsumerKeyKey);
  Future<void> saveConsumerSecret(String secret) async => await _secureStorage.write(key: secureConsumerSecretKey, value: secret);
  Future<String?> getConsumerSecret() async => await _secureStorage.read(key: secureConsumerSecretKey);
  Future<void> saveMyPosApiKey(String key) async => await _secureStorage.write(key: secureMyPosApiKey, value: key);
  Future<String?> getMyPosApiKey() async => await _secureStorage.read(key: secureMyPosApiKey);

  List<SyncOperation> getSyncQueue() {
    final box = _syncQueueBox; if (!_isBoxReady(box, hiveSyncQueueBoxName)) return [];
    return box!.values.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }
  Future<void> addToSyncQueue(SyncOperation operation) async {
    final box = _syncQueueBox; if (!_isBoxReady(box, hiveSyncQueueBoxName)) return;

    // ✅ FIX: Verificar si ya existe una operación con el mismo idempotencyKey
    try {
      final existing = box!.values.cast<SyncOperation?>().firstWhere(
        (op) => op != null && op.idempotencyKey == operation.idempotencyKey,
        orElse: () => null,
      );

      if (existing != null && existing.id != operation.id) {
        // Ya existe una operación con el mismo idempotencyKey
        // Actualizar la existente en lugar de crear duplicado
        debugPrint('[StorageService] 🔄 Updating existing sync operation: ${existing.id}');
        await box.delete(existing.id);
      }

      await box.put(operation.id, operation);
    } catch (e) {
      debugPrint('[StorageService] Error in addToSyncQueue: $e');
      // Fallback: solo hacer put
      await box!.put(operation.id, operation);
    }
  }

  Future<void> removeFromSyncQueue(String operationId) async {
    final box = _syncQueueBox; if (!_isBoxReady(box, hiveSyncQueueBoxName)) return;
    await box!.delete(operationId);
  }

  Future<void> updateSyncOperation(SyncOperation operation) async {
    final box = _syncQueueBox; if (!_isBoxReady(box, hiveSyncQueueBoxName)) return;

    // ✅ FIX V4: Usar save() si el objeto está vinculado a Hive, o put() si no lo está
    // Esto evita el error "same instance with two different keys"
    try {
      if (operation.isInBox) {
        // El objeto ya está vinculado a Hive, usar save() para actualizar
        await operation.save();
        debugPrint('[StorageService] ✅ Updated sync operation (save): ${operation.id}');
      } else {
        // El objeto no está vinculado, usar put() para agregarlo
        await box!.put(operation.id, operation);
        debugPrint('[StorageService] ✅ Updated sync operation (put): ${operation.id}');
      }
    } catch (e) {
      debugPrint('[StorageService] ❌ Error updating sync operation: $e');
      debugPrint('[StorageService] ❌ Operation details: id=${operation.id}, isInBox=${operation.isInBox}');
    }
  }

  Future<void> setLastSync(DateTime dt) async {
    try {
      await _prefs.setInt('last_sync_ms', dt.millisecondsSinceEpoch);
    } catch(e) {
      debugPrint("Err setLastSync:$e");
    }
  }

  DateTime? getLastSync() {
    try {
      final ms = _prefs.getInt('last_sync_ms');
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch(e) {
      return null;
    }
  }

  Future<void> cacheProduct(Product p, {List<Map<String, dynamic>>? fullAttributesWithOptions}) async {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.cacheProduct] ❌ ERROR: ObjectBox not initialized");
      // throw Exception("ObjectBox not initialized - cannot cache product");
      // Comentado para evitar crash en background isolate si no está listo, pero debe manejarse
      return;
    }

    try {
      final box = _db!.store.box<ProductOptimized>();
      final productId = int.tryParse(p.id) ?? 0;

      // ⚡ FIX: Buscar si ya existe el producto por su WooCommerce ID
      final query = box.query(ProductOptimized_.id.equals(productId)).build();
      final existing = query.findFirst();
      query.close();

      // Convertir a ProductOptimized
      final optimized = _converter!.productToOptimized(p);

      // ⚡ FIX: Si ya existe, copiar el localId para actualizar en lugar de insertar
      if (existing != null) {
        optimized.localId = existing.localId;
      }

      // Guardar (actualizar o insertar)
      box.put(optimized);

      debugPrint("[StorageService.cacheProduct] ✅ ${existing != null ? 'Updated' : 'Saved'} product ${p.id} to ObjectBox");
    } catch (e) {
      debugPrint("[StorageService.cacheProduct] ❌ Error saving to ObjectBox: $e");
      rethrow;
    }
  }

  Future<void> cacheProductsBatch(List<Product> products, {Map<String, List<Map<String, dynamic>>>? fullAttributesMap}) async {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.cacheProductsBatch] ❌ ERROR: ObjectBox not initialized");
      return;
    }

    if (products.isEmpty) return;

    debugPrint("[StorageService.cacheProductsBatch] ✅ Caching ${products.length} products to ObjectBox");

    try {
      final box = _db!.store.box<ProductOptimized>();

      // ⚡ FIX: Obtener todos los productos existentes de una sola vez
      final productIds = products.map((p) => int.tryParse(p.id) ?? 0).toList();
      final existingQuery = box.query(ProductOptimized_.id.oneOf(productIds)).build();
      final existingProducts = existingQuery.find();
      existingQuery.close();

      // Crear mapa de WooCommerce ID -> ObjectBox localId
      final existingLocalIds = <int, int>{};
      for (final existing in existingProducts) {
        existingLocalIds[existing.id] = existing.localId;
      }

      // Convertir productos y asignar localId si ya existen
      final List<ProductOptimized> optimizedProducts = products.map((p) {
        final productId = int.tryParse(p.id) ?? 0;
        final optimized = _converter!.productToOptimized(p);

        // ⚡ FIX: Si ya existe, copiar el localId para actualizar
        if (existingLocalIds.containsKey(productId)) {
          optimized.localId = existingLocalIds[productId]!;
        }

        return optimized;
      }).toList();

      // ✅ OBJECTBOX: UNA SOLA operación batch
      box.putMany(optimizedProducts);

      debugPrint("[StorageService.cacheProductsBatch] ✅ Successfully cached ${products.length} products to ObjectBox");
    } catch (e) {
      debugPrint("[StorageService.cacheProductsBatch] ❌ Error saving to ObjectBox: $e");
      rethrow;
    }
  }

  /// ✅ NUEVO: Eliminar producto por ID (Requerido para Delta Sync)
  Future<void> deleteProduct(String pid) async {
    if (_db == null) {
      debugPrint("[StorageService.deleteProduct] ❌ ERROR: ObjectBox not initialized");
      return;
    }

    try {
      final box = _db!.store.box<ProductOptimized>();
      final productId = int.tryParse(pid) ?? 0;

      // Buscar y eliminar por ID externo de WooCommerce
      final query = box.query(ProductOptimized_.id.equals(productId)).build();
      final count = query.remove();
      query.close();

      if (count > 0) {
        debugPrint("[StorageService.deleteProduct] 🗑️ Deleted product $pid from ObjectBox");
      } else {
        debugPrint("[StorageService.deleteProduct] ⚠️ Product $pid not found for deletion");
      }
    } catch (e) {
      debugPrint("[StorageService.deleteProduct] ❌ Error deleting product: $e");
    }
  }

  Product? getProductById(String pid, {bool rehydrateAttributes = true}) {
    if (_db == null || _converter == null) return null;

    try {
      final int productId = int.tryParse(pid) ?? 0;
      if (productId == 0) return null;

      final box = _db!.store.box<ProductOptimized>();
      final query = box.query(ProductOptimized_.id.equals(productId)).build();
      final optimized = query.findFirst();
      query.close();

      if (optimized == null) return null;

      return _converter!.optimizedToProduct(optimized);
    } catch(e) {
      debugPrint("[StorageService.getProductById] ❌ Error: $e");
      return null;
    }
  }

  Future<List<Product>> searchLocalProductsByNameOrSku(String term) async {
    if (_db == null || _converter == null) return [];
    if (term.trim().isEmpty) return [];

    try {
      final searchTerm = term.toLowerCase().trim();
      final box = _db!.store.box<ProductOptimized>();

      final queryBuilder = box.query(
          ProductOptimized_.name.contains(searchTerm, caseSensitive: false)
              .or(ProductOptimized_.sku.contains(searchTerm, caseSensitive: false))
      );

      final query = queryBuilder.build();
      final results = query.find();
      query.close();

      return results.map((opt) => _converter!.optimizedToProduct(opt)).toList();
    } catch (e) {
      debugPrint("[StorageService.searchLocalProductsByNameOrSku] ❌ Error: $e");
      return [];
    }
  }

  /// Obtiene todos los productos de la base de datos local
  /// Si [includeVariations] es true, retorna productos simples, variables Y variaciones
  /// Si [includeVariations] es false, retorna solo productos padre (simples + variables)
  Future<List<Product>> getAllProducts({bool includeVariations = true}) async {
    if (_db == null || _converter == null) return [];

    try {
      final box = _db!.store.box<ProductOptimized>();

      // Si se incluyen variaciones, obtener todos los productos
      if (includeVariations) {
        final allOptimized = box.getAll();
        final products = allOptimized
            .map((opt) => _converter!.optimizedToProduct(opt))
            .toList();
        debugPrint("[StorageService.getAllProducts] ✅ Retrieved ${products.length} products (with variations)");
        return products;
      }

      // Si NO se incluyen variaciones, filtrar solo productos padre
      final queryBuilder = box.query(
        ProductOptimized_.parentId.equals(0)
      );

      final query = queryBuilder.build();
      final results = query.find();
      query.close();

      final products = results.map((opt) => _converter!.optimizedToProduct(opt)).toList();
      debugPrint("[StorageService.getAllProducts] ✅ Retrieved ${products.length} parent products (no variations)");
      return products;
    } catch (e) {
      debugPrint("[StorageService.getAllProducts] ❌ Error: $e");
      return [];
    }
  }

  Future<void> setProductCacheTimestamp(String productId, DateTime timestamp) async {
    try {
      await _prefs.setInt('ts_prod_$productId', timestamp.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint("Err setProductCacheTimestamp: $e");
    }
  }

  DateTime? getProductCacheTimestamp(String productId) {
    try {
      final ms = _prefs.getInt('ts_prod_$productId');
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (e) {
      return null;
    }
  }

  Product? getCachedProductByBarcode(String bc) {
    if (_db == null || _converter == null) return null;

    try {
      final box = _db!.store.box<ProductOptimized>();
      final query = box.query(ProductOptimized_.barcode.equals(bc)).build();
      final optimized = query.findFirst();
      query.close();

      if (optimized == null) return null;
      return _converter!.optimizedToProduct(optimized);
    } catch (e) {
      debugPrint("[StorageService.getCachedProductByBarcode] ❌ Error: $e");
      return null;
    }
  }

  Product? getProductBySku(String sku) {
    if (_db == null || _converter == null) return null;
    if (sku.trim().isEmpty) return null;

    try {
      final box = _db!.store.box<ProductOptimized>();
      final query = box.query(ProductOptimized_.sku.equals(sku.trim())).build();
      final optimized = query.findFirst();
      query.close();

      if (optimized == null) return null;
      return _converter!.optimizedToProduct(optimized);
    } catch (e) {
      debugPrint("[StorageService.getProductBySku] ❌ Error: $e");
      return null;
    }
  }

  Future<void> savePendingOrder(model.Order order, String localId) async {
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.savePendingOrder] ❌ ERROR: ObjectBox not initialized");
      return;
    }

    try {
      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.localOrderId.equals(localId)).build();
      final existing = query.findFirst();
      query.close();

      final orderToSave = order.id == localId ? order : order.copyWith(id: localId);
      final compact = _orderConverter!.orderToCompact(orderToSave);

      if (existing != null) {
        compact.localId = existing.localId;
      }

      box.put(compact);
      debugPrint("[StorageService.savePendingOrder] ✅ Saved pending order $localId");
    } catch (e) {
      debugPrint("[StorageService.savePendingOrder] ❌ Error saving: $e");
      rethrow;
    }
  }

  Map<String, model.Order> getPendingOrders() {
    if (_db == null || _orderConverter == null) return {};

    try {
      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.flags.equals(0)).build();
      final compactOrders = query.find();
      query.close();

      final Map<String, model.Order> result = {};
      for (final compact in compactOrders) {
        final order = _orderConverter!.compactToOrder(compact);
        result[compact.localOrderId] = order;
      }

      return result;
    } catch (e) {
      debugPrint("[StorageService.getPendingOrders] ❌ Error: $e");
      return {};
    }
  }

  Future<void> removePendingOrder(String localId) async {
    if (_db == null || _orderConverter == null) return;

    try {
      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.localOrderId.equals(localId)).build();
      final compact = query.findFirst();
      query.close();

      if (compact != null) {
        box.remove(compact.localId);
        debugPrint("[StorageService.removePendingOrder] ✅ Removed order $localId");
      }
    } catch (e) {
      debugPrint("[StorageService.removePendingOrder] ❌ Error: $e");
    }
  }

  model.Order? getPendingOrderById(String localId) {
    if (_db == null || _orderConverter == null) return null;

    try {
      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.localOrderId.equals(localId)).build();
      final compact = query.findFirst();
      query.close();

      if (compact == null) return null;
      return _orderConverter!.compactToOrder(compact);
    } catch (e) {
      debugPrint("[StorageService.getPendingOrderById] ❌ Error: $e");
      return null;
    }
  }

  Future<void> saveCompletedOrder(model.Order order) async {
    if (_db == null || _orderConverter == null) return;

    if (order.id != null && !order.id!.startsWith('local_')) {
      try {
        final box = _db!.store.box<OrderCompact>();
        final query = box.query(OrderCompact_.localOrderId.equals(order.id!)).build();
        final existing = query.findFirst();
        query.close();

        final compact = _orderConverter!.orderToCompact(order);

        if (existing != null) {
          compact.localId = existing.localId;
        }

        box.put(compact);
      } catch (e) {
        debugPrint("[StorageService.saveCompletedOrder] ❌ Error: $e");
        rethrow;
      }
    }
  }

  model.Order? getCompletedOrderById(String orderId) {
    if (_db == null || _orderConverter == null) return null;

    try {
      final int? orderIdInt = int.tryParse(orderId);
      if (orderIdInt == null) return null;

      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.orderId.equals(orderIdInt)).build();
      final compact = query.findFirst();
      query.close();

      if (compact == null) return null;
      return _orderConverter!.compactToOrder(compact);
    } catch (e) {
      debugPrint("[StorageService.getCompletedOrderById] ❌ Error: $e");
      return null;
    }
  }

  Future<void> setOrderCacheTimestamp(String orderIdOrKey, DateTime timestamp) async {
    try {
      final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
      await _prefs.setInt(key, timestamp.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint("Err setOrderCacheTimestamp: $e");
    }
  }

  DateTime? getOrderCacheTimestamp(String orderIdOrKey) {
    try {
      final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
      final ms = _prefs.getInt(key);
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (e) {
      return null;
    }
  }

  List<model.Order> getCompletedOrders({int limit = 20}) {
    if (_db == null || _orderConverter == null) return [];

    try {
      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.flags.greaterThan(0))
          .order(OrderCompact_.date, flags: 1)
          .build();

      query.limit = limit;
      final compactOrders = query.find();
      query.close();

      return compactOrders.map((compact) => _orderConverter!.compactToOrder(compact)).toList();
    } catch (e) {
      debugPrint("[StorageService.getCompletedOrders] ❌ Error: $e");
      return [];
    }
  }

  Future<void> clearCompletedOrdersCache() async {
    if (_db == null || _orderConverter == null) return;

    try {
      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.flags.greaterThan(0)).build();
      final orderIds = query.findIds();
      query.close();

      if (orderIds.isNotEmpty) {
        box.removeMany(orderIds);
        debugPrint("[StorageService.clearCompletedOrdersCache] ✅ Cleared ${orderIds.length} completed orders");
      }
    } catch (e) {
      debugPrint("[StorageService.clearCompletedOrdersCache] ❌ Error: $e");
    }
  }

  Future<List<Product>> getLocalVariationsForProduct(String productId) async {
    if (_db == null || _converter == null) return [];

    final parentIdInt = int.tryParse(productId);
    if (parentIdInt == null) return [];

    try {
      final box = _db!.store.box<ProductOptimized>();
      final query = box.query(ProductOptimized_.parentId.equals(parentIdInt)).build();
      final variations = query.find();
      query.close();

      return variations.map((opt) => _converter!.optimizedToProduct(opt)).toList();
    } catch (e) {
      debugPrint("[StorageService.getLocalVariationsForProduct] ❌ Error: $e");
      return [];
    }
  }

  Future<int> cleanupLegacyAttributeKeys() async {
    return 0;
  }

  // ==================== GESTIÓN DE BORRADORES DE PEDIDOS ====================

  /// Guardar borrador de pedido
  Future<void> saveDraftOrder(Map<String, dynamic> draft) async {
    try {
      final draftsBox = Hive.box('draft_orders');
      await draftsBox.put(draft['id'], draft);
      debugPrint('[StorageService] Draft order saved: ${draft['id']}');
    } catch (e) {
      debugPrint('[StorageService] Error saving draft: $e');
      rethrow;
    }
  }

  /// Obtener borrador por ID
  Future<Map<String, dynamic>?> getDraftOrder(String id) async {
    try {
      final draftsBox = Hive.box('draft_orders');
      final draft = draftsBox.get(id);
      if (draft != null) {
        return Map<String, dynamic>.from(draft);
      }
      return null;
    } catch (e) {
      debugPrint('[StorageService] Error loading draft: $e');
      return null;
    }
  }

  /// Obtener todos los borradores
  Future<List<Map<String, dynamic>>> getAllDraftOrders() async {
    try {
      final draftsBox = Hive.box('draft_orders');
      final drafts = draftsBox.values
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Ordenar por fecha de creación (más recientes primero)
      drafts.sort((a, b) {
        final dateA = DateTime.parse(a['createdAt'] ?? '1970-01-01');
        final dateB = DateTime.parse(b['createdAt'] ?? '1970-01-01');
        return dateB.compareTo(dateA);
      });

      return drafts;
    } catch (e) {
      debugPrint('[StorageService] Error loading drafts: $e');
      return [];
    }
  }

  /// Eliminar borrador
  Future<void> deleteDraftOrder(String id) async {
    try {
      final draftsBox = Hive.box('draft_orders');
      await draftsBox.delete(id);
      debugPrint('[StorageService] Draft order deleted: $id');
    } catch (e) {
      debugPrint('[StorageService] Error deleting draft: $e');
      rethrow;
    }
  }

  /// Limpiar todos los borradores
  Future<void> clearAllDraftOrders() async {
    try {
      final draftsBox = Hive.box('draft_orders');
      await draftsBox.clear();
      debugPrint('[StorageService] All draft orders cleared');
    } catch (e) {
      debugPrint('[StorageService] Error clearing drafts: $e');
      rethrow;
    }
  }

  void dispose() {
    debugPrint("[StorageService] Dispose called.");
  }
}