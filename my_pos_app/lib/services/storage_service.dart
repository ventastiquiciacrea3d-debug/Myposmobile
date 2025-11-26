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
  /// Esta función abre temporalmente settingsBox, migra los datos, y la cierra.
  /// Solo se ejecuta una vez (usa flag 'settings_box_migrated_v1').
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
      // No lanzar error - la app puede continuar sin migración
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

  // --- El resto de métodos de la clase permanecen sin cambios ---

  bool _isBoxReady<T>(hive.Box<T>? box, String boxName) {
    if (box == null || !box.isOpen) {
      debugPrint("[StorageService] Error: Box '$boxName' is not initialized or not open.");
      return false;
    }
    return true;
  }
  bool _isGenericBoxReady(hive.Box? box, String boxName) {
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
    await box!.put(operation.id, operation);
  }
  Future<void> removeFromSyncQueue(String operationId) async {
    final box = _syncQueueBox; if (!_isBoxReady(box, hiveSyncQueueBoxName)) return;
    await box!.delete(operationId);
  }
  Future<void> updateSyncOperation(SyncOperation operation) async {
    await addToSyncQueue(operation);
  }
  /// ✅ SHAREDPREFERENCES: Last sync timestamp
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

  // ❌ ELIMINADO: _updateSearchIndex() - Ya no se usa (búsqueda ahora usa ObjectBox queries directas)

  Future<void> cacheProduct(Product p, {List<Map<String, dynamic>>? fullAttributesWithOptions}) async {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.cacheProduct] ❌ ERROR: ObjectBox not initialized");
      throw Exception("ObjectBox not initialized - cannot cache product");
    }

    try {
      // ✅ OBJECTBOX: Convertir y guardar en ProductOptimized
      final optimized = _converter!.productToOptimized(p);
      final box = _db!.store.box<ProductOptimized>();
      box.put(optimized);

      debugPrint("[StorageService.cacheProduct] ✅ Saved product ${p.id} to ObjectBox");
    } catch (e) {
      debugPrint("[StorageService.cacheProduct] ❌ Error saving to ObjectBox: $e");
      rethrow;
    }
  }

  /// ✓ FASE 2 BATCH API: Cachea múltiples productos en una sola operación
  Future<void> cacheProductsBatch(List<Product> products, {Map<String, List<Map<String, dynamic>>>? fullAttributesMap}) async {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.cacheProductsBatch] ❌ ERROR: ObjectBox not initialized");
      throw Exception("ObjectBox not initialized - cannot cache products batch");
    }

    if (products.isEmpty) return;

    debugPrint("[StorageService.cacheProductsBatch] ✅ Caching ${products.length} products to ObjectBox");

    try {
      // ✅ OBJECTBOX: Convertir todos los productos a ProductOptimized
      final List<ProductOptimized> optimizedProducts = products
          .map((p) => _converter!.productToOptimized(p))
          .toList();

      // ✅ OBJECTBOX: UNA SOLA operación batch (100x más rápido que Hive)
      final box = _db!.store.box<ProductOptimized>();
      box.putMany(optimizedProducts);

      debugPrint("[StorageService.cacheProductsBatch] ✅ Successfully cached ${products.length} products to ObjectBox");
    } catch (e) {
      debugPrint("[StorageService.cacheProductsBatch] ❌ Error saving to ObjectBox: $e");
      rethrow;
    }
  }

  /// ✅ OBJECTBOX ONLY: Obtiene producto por ID desde ObjectBox
  Product? getProductById(String pid, {bool rehydrateAttributes = true}) {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.getProductById] ❌ ERROR: ObjectBox not initialized");
      return null;
    }

    try {
      final int productId = int.tryParse(pid) ?? 0;
      if (productId == 0) return null;

      // ✅ OBJECTBOX: Buscar en ProductOptimized
      final box = _db!.store.box<ProductOptimized>();
      final query = box.query(ProductOptimized_.id.equals(productId)).build();
      final optimized = query.findFirst();
      query.close();

      if (optimized == null) {
        debugPrint("[StorageService.getProductById] Producto $pid no encontrado en ObjectBox");
        return null;
      }

      // ✅ Convertir a Product (atributos ya incluidos desde ObjectBox)
      return _converter!.optimizedToProduct(optimized);
    } catch(e) {
      debugPrint("[StorageService.getProductById] ❌ Error: $e");
      return null;
    }
  }

  /// ✅ OBJECTBOX ONLY: Búsqueda de productos por nombre o SKU
  Future<List<Product>> searchLocalProductsByNameOrSku(String term) async {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.searchLocalProductsByNameOrSku] ❌ ERROR: ObjectBox not initialized");
      return [];
    }

    if (term.trim().isEmpty) return [];

    try {
      final searchTerm = term.toLowerCase().trim();

      // ✅ OBJECTBOX: Búsqueda por nombre o SKU
      final box = _db!.store.box<ProductOptimized>();

      // Query builder para buscar en nombre (contains) o SKU exacto
      final queryBuilder = box.query(
          ProductOptimized_.name.contains(searchTerm, caseSensitive: false)
              .or(ProductOptimized_.sku.contains(searchTerm, caseSensitive: false))
      );

      final query = queryBuilder.build();
      final results = query.find();
      query.close();

      // Convertir a Product
      return results.map((opt) => _converter!.optimizedToProduct(opt)).toList();
    } catch (e) {
      debugPrint("[StorageService.searchLocalProductsByNameOrSku] ❌ Error: $e");
      return [];
    }
  }

  /// ✅ SHAREDPREFERENCES: Product cache timestamp
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
  /// ✅ OBJECTBOX ONLY: Obtiene producto por código de barras
  Product? getCachedProductByBarcode(String bc) {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.getCachedProductByBarcode] ❌ ERROR: ObjectBox not initialized");
      return null;
    }

    try {
      // ✅ OBJECTBOX: Búsqueda indexada por barcode
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

  /// ✅ OBJECTBOX ONLY: Obtiene producto por SKU
  Product? getProductBySku(String sku) {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.getProductBySku] ❌ ERROR: ObjectBox not initialized");
      return null;
    }

    if (sku.trim().isEmpty) return null;

    try {
      // ✅ OBJECTBOX: Búsqueda indexada por SKU
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
      throw Exception("ObjectBox not initialized - cannot save pending order");
    }

    try {
      // ✅ OBJECTBOX: Convertir y guardar
      final orderToSave = order.id == localId ? order : order.copyWith(id: localId);
      final compact = _orderConverter!.orderToCompact(orderToSave);

      final box = _db!.store.box<OrderCompact>();
      box.put(compact);

      debugPrint("[StorageService.savePendingOrder] ✅ Saved pending order $localId to ObjectBox");
    } catch (e) {
      debugPrint("[StorageService.savePendingOrder] ❌ Error saving to ObjectBox: $e");
      rethrow;
    }
  }
  /// ✅ OBJECTBOX ONLY: Obtiene órdenes pendientes
  Map<String, model.Order> getPendingOrders() {
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.getPendingOrders] ❌ ERROR: ObjectBox not initialized");
      return {};
    }

    try {
      // ✅ OBJECTBOX: Obtener todas las órdenes NO sincronizadas
      final box = _db!.store.box<OrderCompact>();

      // Query para órdenes pendientes (isSynced = false)
      final query = box.query(OrderCompact_.flags.equals(0)).build(); // flags = 0 significa no synced
      final compactOrders = query.find();
      query.close();

      // Convertir a Map<String, model.Order>
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

  /// ✅ OBJECTBOX ONLY: Elimina orden pendiente
  Future<void> removePendingOrder(String localId) async {
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.removePendingOrder] ❌ ERROR: ObjectBox not initialized");
      return;
    }

    try {
      // ✅ OBJECTBOX: Buscar y eliminar orden por localOrderId
      final box = _db!.store.box<OrderCompact>();
      final query = box.query(OrderCompact_.localOrderId.equals(localId)).build();
      final compact = query.findFirst();
      query.close();

      if (compact != null) {
        box.remove(compact.localId);
        debugPrint("[StorageService.removePendingOrder] ✅ Removed order $localId from ObjectBox");
      }
    } catch (e) {
      debugPrint("[StorageService.removePendingOrder] ❌ Error: $e");
    }
  }

  /// ✅ OBJECTBOX ONLY: Obtiene orden pendiente por ID
  model.Order? getPendingOrderById(String localId) {
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.getPendingOrderById] ❌ ERROR: ObjectBox not initialized");
      return null;
    }

    try {
      // ✅ OBJECTBOX: Buscar por localOrderId indexado
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
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.saveCompletedOrder] ❌ ERROR: ObjectBox not initialized");
      throw Exception("ObjectBox not initialized - cannot save completed order");
    }

    if (order.id != null && !order.id!.startsWith('local_')) {
      try {
        // ✅ OBJECTBOX: Convertir y guardar orden completada (ya sincronizada)
        final compact = _orderConverter!.orderToCompact(order);
        final box = _db!.store.box<OrderCompact>();
        box.put(compact);

        debugPrint("[StorageService.saveCompletedOrder] ✅ Saved completed order ${order.id} to ObjectBox");
      } catch (e) {
        debugPrint("[StorageService.saveCompletedOrder] ❌ Error saving to ObjectBox: $e");
        rethrow;
      }
    }
  }

  /// ✅ OBJECTBOX ONLY: Obtiene orden completada por ID
  model.Order? getCompletedOrderById(String orderId) {
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.getCompletedOrderById] ❌ ERROR: ObjectBox not initialized");
      return null;
    }

    try {
      // ✅ OBJECTBOX: Buscar por orderId indexado
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

  /// ✅ SHAREDPREFERENCES: Order cache timestamp
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
  /// ✅ OBJECTBOX ONLY: Obtiene órdenes completadas
  List<model.Order> getCompletedOrders({int limit = 20}) {
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.getCompletedOrders] ❌ ERROR: ObjectBox not initialized");
      return [];
    }

    try {
      // ✅ OBJECTBOX: Obtener órdenes sincronizadas ordenadas por fecha descendente
      final box = _db!.store.box<OrderCompact>();

      // Query para órdenes completadas (isSynced = true) ordenadas por fecha
      final query = box.query(OrderCompact_.flags.greaterThan(0))
          .order(OrderCompact_.date, flags: 1) // 1 = descending
          .build();

      query.limit = limit;
      final compactOrders = query.find();
      query.close();

      // Convertir a Order
      return compactOrders.map((compact) => _orderConverter!.compactToOrder(compact)).toList();
    } catch (e) {
      debugPrint("[StorageService.getCompletedOrders] ❌ Error: $e");
      return [];
    }
  }

  /// ✅ OBJECTBOX ONLY: Limpia todas las órdenes completadas del cache
  Future<void> clearCompletedOrdersCache() async {
    if (_db == null || _orderConverter == null) {
      debugPrint("[StorageService.clearCompletedOrdersCache] ❌ ERROR: ObjectBox not initialized");
      return;
    }

    try {
      final box = _db!.store.box<OrderCompact>();

      // Query para órdenes sincronizadas (flags > 0)
      final query = box.query(OrderCompact_.flags.greaterThan(0)).build();
      final orderIds = query.findIds();
      query.close();

      if (orderIds.isNotEmpty) {
        box.removeMany(orderIds);
        debugPrint("[StorageService.clearCompletedOrdersCache] ✅ Cleared ${orderIds.length} completed orders from ObjectBox");
      } else {
        debugPrint("[StorageService.clearCompletedOrdersCache] No completed orders to clear");
      }
    } catch (e) {
      debugPrint("[StorageService.clearCompletedOrdersCache] ❌ Error: $e");
    }
  }

  /// ✅ OBJECTBOX ONLY: Obtiene variaciones de un producto
  Future<List<Product>> getLocalVariationsForProduct(String productId) async {
    if (_db == null || _converter == null) {
      debugPrint("[StorageService.getLocalVariationsForProduct] ❌ ERROR: ObjectBox not initialized");
      return [];
    }

    final parentIdInt = int.tryParse(productId);
    if (parentIdInt == null) return [];

    try {
      // ✅ OBJECTBOX: Query indexado por parentId
      final box = _db!.store.box<ProductOptimized>();

      // Buscar todos los productos con este parentId
      final query = box.query(ProductOptimized_.parentId.equals(parentIdInt)).build();
      final variations = query.find();
      query.close();

      // Convertir a Product
      return variations.map((opt) => _converter!.optimizedToProduct(opt)).toList();
    } catch (e) {
      debugPrint("[StorageService.getLocalVariationsForProduct] ❌ Error: $e");
      return [];
    }
  }

  /// ❌ DEPRECADO: cleanupLegacyAttributeKeys no longer needed
  /// SettingsBox ha sido migrado a SharedPreferences, no hay claves legacy que limpiar
  Future<int> cleanupLegacyAttributeKeys() async {
    debugPrint('[StorageService.cleanupLegacyAttributeKeys] ⏭️ Method deprecated - settingsBox migrated to SharedPreferences');
    return 0;
  }

  void dispose() {
    // Si el servicio de ObjectBox se usó en el hilo principal, debe cerrarse al final del ciclo de vida.
    // Asumimos que DatabaseService.dispose() maneja el cierre de ObjectBox.
    debugPrint("[StorageService] Dispose called.");
  }
}