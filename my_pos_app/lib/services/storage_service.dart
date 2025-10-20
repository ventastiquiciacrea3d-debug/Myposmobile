// lib/services/storage_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/order.dart';
import '../models/label_print_item.dart';
import '../config/constants.dart';
import '../models/sync_operation.dart';
import '../locator.dart';

class StorageService {
  Box<Product>? _productBox;
  Box<Order>? _orderBox;
  Box<List<String>>? _barcodeIndexBox;
  Box? _settingsBox;
  Box<Order>? _pendingOrderBox;
  Box<LabelPrintItem>? _labelQueueBox;
  Box<SyncOperation>? _syncQueueBox;

  SharedPreferences get _prefs => getIt<SharedPreferences>();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  StorageService();

  Future<void> init() async {
    debugPrint("[StorageService] init: Opening Hive boxes...");
    try {
      _productBox = await Hive.openBox<Product>(hiveProductsBoxName);
      _orderBox = await Hive.openBox<Order>(hiveOrdersBoxName);
      _barcodeIndexBox = await Hive.openBox<List<String>>(hiveBarcodeIndexBoxName);
      _settingsBox = await Hive.openBox(hiveSettingsBoxName);
      _pendingOrderBox = await Hive.openBox<Order>(hivePendingOrdersBoxName);
      _labelQueueBox = await Hive.openBox<LabelPrintItem>(hiveLabelQueueBoxName);
      _syncQueueBox = await Hive.openBox<SyncOperation>(hiveSyncQueueBoxName);
      debugPrint("[StorageService] init: All Hive boxes initialized successfully.");
    } catch (e, stacktrace) {
      debugPrint("[StorageService] !! FATAL ERROR initializing storage: $e\n$stacktrace");
      rethrow;
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

  bool _isBoxReady<T>(Box<T>? box, String boxName) {
    if (box == null || !box.isOpen) {
      debugPrint("[StorageService] Error: Box '$boxName' is not initialized or not open.");
      return false;
    }
    return true;
  }
  bool _isGenericBoxReady(Box? box, String boxName) {
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
  Future<void> setLastSync(DateTime dt) async {
    final box = _settingsBox; if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return;
    try { await box!.put(hiveLastSyncKey, dt.toIso8601String()); } catch(e){debugPrint("Err setLastSync:$e");}
  }
  DateTime? getLastSync() {
    final box = _settingsBox; if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return null;
    try { final s = box!.get(hiveLastSyncKey); return s != null ? DateTime.tryParse(s) : null; } catch(e){return null;}
  }
  Future<void> _updateSearchIndex(Product p) async {
    final indexBox = _barcodeIndexBox;
    if (!_isBoxReady(indexBox, hiveBarcodeIndexBoxName)) return;
    final Set<String> keywords = {};
    final String normalizedText = '${p.name} ${p.sku} ${p.barcode ?? ''}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    keywords.addAll(normalizedText.split(' ').where((s) => s.length > 1));
    for (final keyword in keywords) {
      final List<String> existingIds = indexBox!.get(keyword) ?? [];
      if (!existingIds.contains(p.id)) {
        existingIds.add(p.id);
        await indexBox.put(keyword, existingIds);
      }
    }
  }
  Future<void> cacheProduct(Product p, {List<Map<String, dynamic>>? fullAttributesWithOptions}) async {
    final productBox = _productBox;
    if (!_isBoxReady(productBox, hiveProductsBoxName)) return;
    await productBox!.put(p.id, p.toHiveObject());
    await setProductCacheTimestamp(p.id, DateTime.now());
    await _updateSearchIndex(p);
    final String attributesKey = 'product_faf_${p.id}';
    if (fullAttributesWithOptions != null && fullAttributesWithOptions.isNotEmpty) {
      await _settingsBox!.put(attributesKey, jsonEncode(fullAttributesWithOptions));
    }
  }
  Product? getProductById(String pid, {bool rehydrateAttributes = true}) {
    final productBox = _productBox;
    if (!_isBoxReady(productBox, hiveProductsBoxName)) return null;
    try {
      Product? product = productBox!.get(pid);
      if (product != null && rehydrateAttributes) {
        final attributesJson = _settingsBox?.get('product_faf_${product.id}') as String?;
        if (attributesJson != null && attributesJson.isNotEmpty) {
          final List<Map<String, dynamic>> rehydrated = List<Map<String, dynamic>>.from(jsonDecode(attributesJson));
          return product.copyWith(fullAttributesWithOptions: () => rehydrated);
        }
      }
      return product;
    } catch(e){ return null; }
  }
  Future<List<Product>> searchLocalProductsByNameOrSku(String term) async {
    final indexBox = _barcodeIndexBox;
    if (!_isBoxReady(indexBox, hiveBarcodeIndexBoxName)) return [];
    if (term.trim().isEmpty) return [];
    final keywords = term.toLowerCase().split(' ').where((s) => s.length > 1).toList();
    if (keywords.isEmpty) return [];
    Set<String>? matchingIds;
    for (final keyword in keywords) {
      final List<String> idsForKeyword = indexBox!.get(keyword) ?? [];
      if (matchingIds == null) {
        matchingIds = idsForKeyword.toSet();
      } else {
        matchingIds.retainAll(idsForKeyword);
      }
      if (matchingIds.isEmpty) break;
    }
    if (matchingIds == null || matchingIds.isEmpty) return [];
    final List<Product> results = [];
    for (final id in matchingIds) {
      final product = getProductById(id);
      if (product != null) {
        results.add(product);
      }
    }
    return results;
  }
  Future<void> setProductCacheTimestamp(String productId, DateTime timestamp) async {
    final box = _settingsBox; if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return;
    try { await box!.put('ts_prod_$productId', timestamp.toIso8601String()); } catch (e) { debugPrint("Err setProductCacheTimestamp: $e"); }
  }
  DateTime? getProductCacheTimestamp(String productId) {
    final box = _settingsBox; if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return null;
    try { final ts = box!.get('ts_prod_$productId'); return (ts is String) ? DateTime.tryParse(ts) : null; } catch (e) { return null; }
  }
  Product? getCachedProductByBarcode(String bc) {
    final box = _productBox; if (!_isBoxReady(box, hiveProductsBoxName)) return null;
    try {
      final product = box!.values.firstWhereOrNull((p) => p.barcode == bc);
      return product != null ? getProductById(product.id, rehydrateAttributes: true) : null;
    } catch (e) { return null; }
  }
  Product? getProductBySku(String sku) {
    final box = _productBox; if (!_isBoxReady(box, hiveProductsBoxName)) return null;
    if (sku.trim().isEmpty) return null;
    try {
      final product = box!.values.firstWhereOrNull((p) => p.sku.toLowerCase() == sku.trim().toLowerCase());
      return product != null ? getProductById(product.id, rehydrateAttributes: true) : null;
    } catch (e) { return null; }
  }
  Future<void> savePendingOrder(Order order, String localId) async {
    final box = _pendingOrderBox; if (!_isBoxReady(box, hivePendingOrdersBoxName)) return;
    try {
      await box!.put(localId, order.id == localId ? order : order.copyWith(id: localId));
    } catch (e) { debugPrint("ERROR saving pending order $localId: $e"); }
  }
  Map<String, Order> getPendingOrders() {
    final box = _pendingOrderBox; if (!_isBoxReady(box, hivePendingOrdersBoxName)) return {};
    try {
      return box!.toMap().map((key, value) => MapEntry(key.toString(), value));
    } catch (e) { return {}; }
  }
  Future<void> removePendingOrder(String localId) async {
    final box = _pendingOrderBox; if (!_isBoxReady(box, hivePendingOrdersBoxName)) return;
    try {
      await box!.delete(localId);
    } catch (e) { debugPrint("ERROR removing pending order $localId: $e"); }
  }
  Order? getPendingOrderById(String localId) {
    final box = _pendingOrderBox; if (!_isBoxReady(box, hivePendingOrdersBoxName)) return null;
    try { return box!.get(localId); } catch (e) { return null; }
  }
  Future<void> saveCompletedOrder(Order order) async {
    final box = _orderBox; if (!_isBoxReady(box, hiveOrdersBoxName)) return;
    if (order.id != null && !order.id!.startsWith('local_')) {
      try {
        await box!.put(order.id, order);
        await setOrderCacheTimestamp(order.id!, DateTime.now());
      } catch (e) { debugPrint("ERROR saving completed order ${order.id}: $e"); }
    }
  }
  Order? getCompletedOrderById(String orderId) {
    final box = _orderBox; if (!_isBoxReady(box, hiveOrdersBoxName)) return null;
    try { return box!.get(orderId); } catch (e) { return null; }
  }
  Future<void> setOrderCacheTimestamp(String orderIdOrKey, DateTime timestamp) async {
    final box = _settingsBox; if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return;
    final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
    try { await box!.put(key, timestamp.toIso8601String()); } catch (e) { debugPrint("Err setOrderCacheTimestamp: $e"); }
  }
  DateTime? getOrderCacheTimestamp(String orderIdOrKey) {
    final box = _settingsBox; if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return null;
    final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
    try { final ts = box!.get(key); return (ts is String) ? DateTime.tryParse(ts) : null; } catch (e) { return null; }
  }
  List<Order> getCompletedOrders({int limit = 20}) {
    final box = _orderBox; if (!_isBoxReady(box, hiveOrdersBoxName)) return [];
    try {
      var orders = box!.values.toList();
      orders.sort((a, b) => b.date.compareTo(a.date));
      return orders.take(limit).toList();
    } catch (e) { return []; }
  }
  Future<void> clearCompletedOrdersCache() async {
    final orderBox = _orderBox;
    final settingsBox = _settingsBox;
    if (!_isBoxReady(orderBox, hiveOrdersBoxName) || !_isGenericBoxReady(settingsBox, hiveSettingsBoxName)) return;
    try {
      List<String> keysToRemove = settingsBox!.keys.whereType<String>().where((k) => k.startsWith('ts_order_') || k.startsWith('order_history_')).toList();
      if (keysToRemove.isNotEmpty) await settingsBox.deleteAll(keysToRemove);
      await orderBox!.clear();
    } catch(e) { throw Exception("Error clearing completed orders cache: $e"); }
  }
  Future<List<Product>> getLocalVariationsForProduct(String productId) async {
    final box = _productBox; if (!_isBoxReady(box, hiveProductsBoxName)) return [];
    final parentIdInt = int.tryParse(productId);
    if (parentIdInt == null) return [];
    try {
      final List<Product> baseVariations = box!.values.where((p) => p.isVariation && p.parentId == parentIdInt).toList();
      return baseVariations.map((p) => getProductById(p.id) ?? p).toList();
    } catch (e) { return []; }
  }

  void dispose() {
    debugPrint("[StorageService] Dispose called.");
  }
}