// lib/repositories/inventory_repository.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:my_pos_mobile_barcode/services/woocommerce_service.dart';

import '../models/inventory_movement.dart';
import '../models/inventory_movement_compact.dart';
import '../models/product.dart' as app_product;
import '../locator.dart';
import '../repositories/product_repository.dart';
import '../services/database_service.dart';
import '../services/inventory_converter_service.dart';
import '../services/storage_service.dart'; // 🔍 Para debug de sync queue
import '../objectbox.g.dart';
import '../services/sync_manager.dart'; // ✅ Importar SyncManager
import '../models/sync_operation.dart'; // ✅ Importar tipos de Sync

/// ✓ PROPUESTA 1: InventoryRepository con patrón SWR (Stale-While-Revalidate) completo
///
/// Mejoras implementadas:
/// 1. ✅ Stream de eventos para notificar actualizaciones desde API
/// 2. ✅ Método getInventoryMovementsWithSWR() optimizado
/// 3. ✅ Background updates automáticos con cache stale
/// 4. ✅ Fallback a caché en errores de red
/// 5. ✅ Cache warming para precarga de datos
/// 6. ✅ Integración con SyncManager para subida inmediata
class InventoryRepository {
  final WooCommerceService _wooCommerceService = getIt<WooCommerceService>();
  final ProductRepository _productRepository = getIt<ProductRepository>();
  // ✅ Obtener instancia de SyncManager
  final SyncManager _syncManager = getIt<SyncManager>();

  String? errorMessage;

  // ✅ OBJECTBOX - Base de datos principal
  DatabaseService? _db;
  InventoryConverterService? _converter;

  // ✓ PROPUESTA 1: Stream para notificar updates desde API
  final StreamController<InventoryMovement> _movementUpdateController = StreamController<InventoryMovement>.broadcast();
  Stream<InventoryMovement> get onMovementUpdatedFromApi => _movementUpdateController.stream;

  // ✅ Stream para emitir conteo de movimientos no sincronizados (evita llamadas repetidas)
  final StreamController<int> _unsyncedCountController = StreamController<int>.broadcast();
  Stream<int> get unsyncedMovementsCountStream => _unsyncedCountController.stream;
  int _cachedUnsyncedCount = 0;

  static const Duration inventoryHistoryCacheTTL = Duration(minutes: 30);
  static const Duration inventoryProductsCacheTTL = Duration(hours: 1);

  // Timestamp de último fetch desde API
  DateTime? _lastInventoryHistoryFetch;

  // ✅ Control de background refresh para evitar múltiples llamadas simultáneas
  bool _isBackgroundRefreshInProgress = false;
  DateTime? _lastBackgroundRefreshAttempt;

  InventoryRepository() {
    debugPrint("[InventoryRepository] ✓ Initialized with SWR pattern (TTL Cache Mode for Inventory).");
    _initObjectBox();
  }

  Future<void> _initObjectBox() async {
    try {
      _db = await DatabaseService.getInstance();
      _converter = InventoryConverterService();
      debugPrint("[InventoryRepository] ✅ ObjectBox initialized");
    } catch (e) {
      debugPrint("[InventoryRepository] ⚠️ ObjectBox initialization failed: $e");
    }
  }

  /// ✅ OBJECTBOX ONLY: Método SWR optimizado para obtener movimientos de inventario
  /// Retorna caché inmediatamente si existe, actualiza en background si stale
  Future<Map<String, dynamic>> getInventoryMovementsWithSWR({
    int page = 1,
    int perPage = 25,
    String? searchTerm,
    Duration ttlDuration = inventoryHistoryCacheTTL,
  }) async {
    debugPrint("[InventoryRepository.getInventoryMovementsWithSWR] 🔍 Page: $page, PerPage: $perPage (TTL: ${ttlDuration.inMinutes}min)");

    // ✅ OBJECTBOX: Verificar inicialización
    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository.getInventoryMovementsWithSWR] ❌ ERROR: ObjectBox not initialized");
      return {'movements': <InventoryMovement>[], 'total_pages': 0};
    }

    // ✅ OBJECTBOX: Leer desde ObjectBox
    List<InventoryMovement> cachedMovements = [];
    try {
      final box = _db!.store.box<InventoryMovementCompact>();
      final compactMovements = box.getAll();
      cachedMovements = compactMovements
          .map((compact) => _converter!.compactToMovement(compact))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      debugPrint("... ✅ Loaded ${cachedMovements.length} movements from ObjectBox");
    } catch (e) {
      debugPrint("[InventoryRepository.getInventoryMovementsWithSWR] ❌ Error loading from ObjectBox: $e");
      // Continuar con lista vacía
    }

    // Helper para filtrar movimientos
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

    // ✓ PROPUESTA 1: Si hay caché, verificar si es fresh o stale
    if (cachedMovements.isNotEmpty && _lastInventoryHistoryFetch != null) {
      final isFresh = DateTime.now().isBefore(_lastInventoryHistoryFetch!.add(ttlDuration));

      if (isFresh) {
        debugPrint("... 🟢 [FRESH] Returning cached inventory movements. Triggering background refresh.");
        _fetchAndUpdateInventoryInBackground(); // Refresh en background de todas formas
      } else {
        debugPrint("... 🟡 [STALE] Returning stale cached inventory movements. Triggering background update.");
        _fetchAndUpdateInventoryInBackground(); // Actualizar en background
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

    // ✓ Cache MISS o nunca se ha fetched - Fetch desde API
    try {
      debugPrint("... 📡 Fetching Inventory History from API...");
      cachedMovements = await _fetchAndCacheInventoryHistory();
      debugPrint("... ✅ Inventory History fetched and cached successfully");
    } on NetworkException {
      debugPrint("... 🔴 Network error. Falling back to cached movements");
      if (cachedMovements.isEmpty) rethrow;
    } on ApiException {
      debugPrint("... 🔴 API error. Falling back to cached movements");
      if (cachedMovements.isEmpty) rethrow;
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

  /// ✅ OBJECTBOX ONLY: Background update silencioso para mantener caché fresco
  /// Incluye debouncing para evitar múltiples llamadas simultáneas
  Future<void> _fetchAndUpdateInventoryInBackground() async {
    // ✅ Evitar múltiples refreshes simultáneos
    if (_isBackgroundRefreshInProgress) {
      debugPrint("... ⏭️ [Background Update] Already in progress, skipping");
      return;
    }

    // ✅ Evitar refreshes muy frecuentes (mínimo 10 segundos entre intentos)
    if (_lastBackgroundRefreshAttempt != null &&
        DateTime.now().difference(_lastBackgroundRefreshAttempt!) < const Duration(seconds: 10)) {
      debugPrint("... ⏭️ [Background Update] Too soon (${DateTime.now().difference(_lastBackgroundRefreshAttempt!).inSeconds}s), skipping");
      return;
    }

    _isBackgroundRefreshInProgress = true;
    _lastBackgroundRefreshAttempt = DateTime.now();

    debugPrint("... 🔄 [Background Update] Starting for Inventory History");
    try {
      await _fetchAndCacheInventoryHistory();
      debugPrint("... ✅ [Background Update] Cache updated for Inventory History");
    } catch (e) {
      debugPrint("... ⚠️ [Background Update] Failed for Inventory History: ${e.toString()}");
    } finally {
      _isBackgroundRefreshInProgress = false;
    }
  }

  /// ✅ OBJECTBOX ONLY: Fetch desde API y guardar en ObjectBox
  Future<List<InventoryMovement>> _fetchAndCacheInventoryHistory() async {
    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository._fetchAndCacheInventoryHistory] ❌ ERROR: ObjectBox not initialized");
      return [];
    }

    final serverMovements = await _wooCommerceService.getInventoryHistory();

    // 🔍 DEBUG: Log de movimientos recibidos del servidor
    debugPrint("... 🔍 [DEBUG] Server returned ${serverMovements.length} movements");
    if (serverMovements.isNotEmpty) {
      debugPrint("... 🔍 [DEBUG] First 3 movement IDs from server:");
      for (var i = 0; i < (serverMovements.length > 3 ? 3 : serverMovements.length); i++) {
        final m = serverMovements[i];
        debugPrint("...   ${i + 1}. ${m.id} - ${m.description}");
      }
    }

    try {
      final box = _db!.store.box<InventoryMovementCompact>();

      // ⚡ FIX: Obtener todos los movimientos existentes para preservar localIds
      final existingQuery = box.query().build();
      final existingMovements = existingQuery.find();
      existingQuery.close();

      // Crear mapa de movementId -> ObjectBox localId
      final existingLocalIds = <String, int>{};
      for (final existing in existingMovements) {
        existingLocalIds[existing.movementId] = existing.localId;
      }

      // Convertir movimientos y asignar localId si ya existen
      final compactMovements = serverMovements.map((movement) {
        // ✅ Marcar como sincronizado porque vienen del servidor
        final syncedMovement = InventoryMovement(
          id: movement.id,
          date: movement.date,
          type: movement.type,
          description: movement.description,
          items: movement.items,
          isSynced: true,  // ✅ Vienen del servidor, están sincronizados
          userId: movement.userId,
          userName: movement.userName,
        );

        final compact = _converter!.movementToCompact(syncedMovement);

        // ⚡ FIX: Si ya existe, copiar el localId para actualizar
        if (existingLocalIds.containsKey(compact.movementId)) {
          compact.localId = existingLocalIds[compact.movementId]!;
        }

        return compact;
      }).toList();

      // ⚡ FIX: Guardar todos sin removeAll() para evitar race conditions
      // putMany() actualizará existentes y creará nuevos
      box.putMany(compactMovements);

      // ✅ FIX CRÍTICO: NO eliminar movimientos locales
      // Los movimientos creados en la app NO se guardan en WordPress (solo actualizan stock)
      // Por lo tanto, NUNCA aparecerán en /inventory-history del servidor
      // Solo debemos AGREGAR movimientos del servidor, NUNCA eliminar los locales

      final serverMovementIds = serverMovements.map((m) => m.id).toSet();

      // 🔍 DEBUG: Loggear IDs del servidor para diagnóstico
      debugPrint("\n========== 🔍 INVENTORY SYNC DEBUG ==========");
      debugPrint("... 🔍 [DEBUG] Server returned ${serverMovementIds.length} movements");
      final serverIdsList = serverMovementIds.toList();
      for (var i = 0; i < (serverIdsList.length > 3 ? 3 : serverIdsList.length); i++) {
        debugPrint("...   Server ID ${i + 1}: ${serverIdsList[i]}");
      }

      // Encontrar movimientos locales que NO están en el servidor (para info solamente)
      final localOnlyMovements = existingMovements
          .where((e) => !serverMovementIds.contains(e.movementId))
          .toList();

      debugPrint("... 🔍 [DEBUG] Found ${localOnlyMovements.length} local-only movements:");
      for (var i = 0; i < (localOnlyMovements.length > 3 ? 3 : localOnlyMovements.length); i++) {
        final mov = localOnlyMovements[i];
        debugPrint("...   - ${mov.movementId} (isSynced: ${mov.isSynced})");
      }

      // ✅ NO eliminar nada - los movimientos locales son la fuente de verdad
      debugPrint("... ✅ Keeping all ${localOnlyMovements.length} local movements (NOT deleting)");
      debugPrint("... ℹ️  Local movements are app's source of truth and should never be deleted");
      debugPrint("========== END INVENTORY SYNC DEBUG ==========\n");

      debugPrint("... ✅ Saved ${compactMovements.length} movements to ObjectBox (${existingLocalIds.length} updated, ${compactMovements.length - existingLocalIds.length} new)");
    } catch (e) {
      debugPrint("[InventoryRepository._fetchAndCacheInventoryHistory] ❌ Error saving to ObjectBox: $e");
      // Continuar de todas formas, retornar los movimientos del servidor
    }

    // Actualizar timestamp de último fetch
    _lastInventoryHistoryFetch = DateTime.now();

    // ✅ CORRECCIÓN CRÍTICA: Volver a leer TODOS los movimientos de ObjectBox
    // Esto incluye los del servidor + los locales no sincronizados
    List<InventoryMovement> allMovements = [];
    try {
      final box = _db!.store.box<InventoryMovementCompact>();
      final compactMovements = box.getAll();
      allMovements = compactMovements
          .map((compact) => _converter!.compactToMovement(compact))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      final unsyncedCount = allMovements.where((m) => !m.isSynced).length;
      debugPrint("... ✅ Loaded ${allMovements.length} total movements from ObjectBox (${serverMovements.length} from server, $unsyncedCount unsynced local)");
    } catch (e) {
      debugPrint("[InventoryRepository._fetchAndCacheInventoryHistory] ❌ Error reading all movements: $e");
      // Fallback a solo los del servidor
      allMovements = serverMovements;
    }

    // Notificar listeners de cada movimiento nuevo del servidor
    for (final movement in serverMovements) {
      _movementUpdateController.add(movement);
    }

    debugPrint("... ✅ Fetched and synced ${serverMovements.length} movements from server. Returning ${allMovements.length} total.");
    return allMovements;
  }

  // ==================== NUEVO MÉTODO PARA CREACIÓN ROBUSTA ====================

  /// ✅ NUEVO MÉTODO ROBUSTO: Crea movimiento localmente y lo encola
  /// Reemplaza al antiguo submitInventoryAdjustment directo
  Future<void> createInventoryMovement(InventoryMovement movement) async {
    debugPrint("[InventoryRepository] Creating inventory movement: ${movement.description}");
    debugPrint("  Movement ID: ${movement.id}");
    debugPrint("  Date: ${movement.date}");
    debugPrint("  Type: ${movement.type}");
    debugPrint("  Items count: ${movement.items.length}");

    // ✅ DEBUG: Log detalles de cada item
    for (var item in movement.items) {
      debugPrint("  Item: ${item.productName}");
      debugPrint("    ProductID: ${item.productId}");
      debugPrint("    VariationID: ${item.variationId}");
      debugPrint("    SKU: ${item.sku}");
      debugPrint("    Quantity: ${item.quantityChanged}");
    }

    errorMessage = null;

    try {
      // 1. Guardar localmente primero (Estado: No Sincronizado)
      // Aseguramos que isSynced sea false
      final localMovement = InventoryMovement(
        id: movement.id,
        date: movement.date,
        type: movement.type,
        description: movement.description,
        items: movement.items,
        isSynced: false, // 🔴 Importante: Marcado como no sincronizado
        userId: movement.userId,
        userName: movement.userName,
      );

      debugPrint("[InventoryRepository] Saving to ObjectBox...");
      await saveInventoryMovement(localMovement);
      debugPrint("[InventoryRepository] ✅ Saved to ObjectBox");

      // Notificar a la UI inmediatamente para que aparezca en la lista
      _movementUpdateController.add(localMovement);
      debugPrint("[InventoryRepository] ✅ Notified UI");

      // 2. Agregar a la cola de sincronización (SyncManager)
      // Esto garantiza que se envíe inmediatamente si hay red, o luego si no.
      debugPrint("[InventoryRepository] Queueing for sync...");
      await _syncManager.addOperation(
        SyncOperationType.inventoryAdjustment,
        {'movement': localMovement.toJson()},
        priority: SyncPriority.high,
      );

      debugPrint("[InventoryRepository] ✅ Movement created locally and queued for sync.");

    } catch (e) {
      debugPrint("[InventoryRepository] ❌ Error creating movement: $e");
      errorMessage = "Error al guardar el movimiento: $e";
      rethrow;
    }
  }

  /// Mantenemos este por compatibilidad, pero lo redirigimos al nuevo flujo
  Future<void> submitInventoryAdjustment(InventoryMovement movement) async {
    return createInventoryMovement(movement);
  }

  // ==================== MÉTODOS LEGACY (Backward compatibility) ====================

  /// ✅ OBJECTBOX ONLY: Método legacy - usa getInventoryMovementsWithSWR internamente
  Future<Map<String, dynamic>> getInventoryMovements({
    int page = 1,
    int perPage = 25,
    String? searchTerm,
    bool forceApi = false,
  }) async {
    if (forceApi) {
      // Si forceApi, hacer fetch directo sin caché
      try {
        final movements = await _fetchAndCacheInventoryHistory();

        final filtered = searchTerm != null && searchTerm.trim().isNotEmpty
            ? movements.where((m) {
          final term = searchTerm.toLowerCase().trim();
          return m.description.toLowerCase().contains(term) ||
              m.userName?.toLowerCase().contains(term) == true ||
              m.items.any((item) =>
              item.productName.toLowerCase().contains(term) ||
                  item.sku.toLowerCase().contains(term));
        }).toList()
            : movements;

        final totalItems = filtered.length;
        final totalPages = (totalItems / perPage).ceil();
        final startIndex = (page - 1) * perPage;
        final paginatedMovements = filtered.skip(startIndex).take(perPage).toList();

        return {
          'movements': paginatedMovements,
          'total_pages': totalPages,
        };
      } catch (e) {
        // En error, intentar caché como fallback
        if (_db == null || _converter == null) {
          debugPrint("[InventoryRepository.getInventoryMovements] ❌ ERROR: ObjectBox not initialized");
          rethrow;
        }

        try {
          final box = _db!.store.box<InventoryMovementCompact>();
          final compactMovements = box.getAll();
          List<InventoryMovement> cachedMovements = compactMovements
              .map((compact) => _converter!.compactToMovement(compact))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          if (cachedMovements.isEmpty) rethrow;

          final filtered = searchTerm != null && searchTerm.trim().isNotEmpty
              ? cachedMovements.where((m) {
            final term = searchTerm.toLowerCase().trim();
            return m.description.toLowerCase().contains(term) ||
                m.userName?.toLowerCase().contains(term) == true ||
                m.items.any((item) =>
                item.productName.toLowerCase().contains(term) ||
                    item.sku.toLowerCase().contains(term));
          }).toList()
              : cachedMovements;

          final totalItems = filtered.length;
          final totalPages = (totalItems / perPage).ceil();
          final startIndex = (page - 1) * perPage;
          final paginatedMovements = filtered.skip(startIndex).take(perPage).toList();

          return {
            'movements': paginatedMovements,
            'total_pages': totalPages,
          };
        } catch (cacheError) {
          debugPrint("[InventoryRepository.getInventoryMovements] ❌ Error loading from cache: $cacheError");
          rethrow;
        }
      }
    }

    // Usar método SWR
    return getInventoryMovementsWithSWR(
      page: page,
      perPage: perPage,
      searchTerm: searchTerm,
      ttlDuration: inventoryHistoryCacheTTL,
    );
  }

  /// ✅ OBJECTBOX ONLY: Guardar movement en ObjectBox
  Future<void> saveInventoryMovement(InventoryMovement movement) async {
    debugPrint("[InventoryRepository] Saving inventory movement ID: ${movement.id}");

    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository.saveInventoryMovement] ❌ ERROR: ObjectBox not initialized");
      throw StateError('ObjectBox not initialized');
    }

    try {
      final box = _db!.store.box<InventoryMovementCompact>();

      // ⚡ FIX: Buscar si ya existe el movimiento por su movementId
      final query = box.query(InventoryMovementCompact_.movementId.equals(movement.id)).build();
      final existing = query.findFirst();
      query.close();

      // Convertir a InventoryMovementCompact
      final compact = _converter!.movementToCompact(movement);

      // ⚡ FIX: Si ya existe, copiar el localId para actualizar en lugar de insertar
      if (existing != null) {
        compact.localId = existing.localId;
      }

      // Guardar (actualizar o insertar)
      box.put(compact);

      debugPrint("[InventoryRepository] ✅ Movement ID ${movement.id} ${existing != null ? 'updated' : 'saved'} to ObjectBox");

      // ✅ Actualizar conteo de movimientos no sincronizados
      await _updateUnsyncedCount();
    } catch (e) {
      debugPrint("[InventoryRepository.saveInventoryMovement] ❌ Error saving to ObjectBox: $e");
      rethrow;
    }
  }


  /// ✅ OBJECTBOX ONLY: Eliminar movement de ObjectBox
  Future<void> deleteInventoryMovement(String movementId) async {
    debugPrint("[InventoryRepository] Deleting inventory movement ID: $movementId");

    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository.deleteInventoryMovement] ❌ ERROR: ObjectBox not initialized");
      throw StateError('ObjectBox not initialized');
    }

    try {
      // ✅ OBJECTBOX: Buscar y eliminar por movementId
      final box = _db!.store.box<InventoryMovementCompact>();
      final query = box.query(InventoryMovementCompact_.movementId.equals(movementId)).build();
      final compact = query.findFirst();
      query.close();

      if (compact != null) {
        box.remove(compact.localId);
        debugPrint("[InventoryRepository] ✅ Movement ID $movementId deleted from ObjectBox");
      } else {
        debugPrint("[InventoryRepository] ⚠️ Movement ID $movementId not found in ObjectBox");
      }
    } catch (e) {
      debugPrint("[InventoryRepository.deleteInventoryMovement] ❌ Error deleting from ObjectBox: $e");
      rethrow;
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

        // 🟡 PRIORIDAD 2: Paralelizar carga de variaciones
        // Antes: Loop secuencial - 50 productos variables = ~30s
        // Ahora: Batches paralelos de 10 - 50 productos variables = ~6s
        final variableProducts = products.where((p) => p.isVariable).toList();
        debugPrint("[InventoryRepository] 🟡 OPTIMIZED: Loading variations for ${variableProducts.length} variable products in parallel");

        const int concurrentLimit = 10;
        final List<Future<Map<String, dynamic>>> variationFutures = [];

        for (int i = 0; i < variableProducts.length; i++) {
          final parent = variableProducts[i];
          allProducts.add(parent);

          // Agregar future de carga de variaciones
          variationFutures.add(
              _wooCommerceService.getAllVariationsForProduct(parent.id).then((variationsData) {
                return {'parent': parent, 'variations': variationsData};
              }).catchError((e) {
                debugPrint("⚠️ Failed to load variations for product ${parent.id}: $e");
                return {'parent': parent, 'variations': <Map<String, dynamic>>[]};
              })
          );

          // 🟡 Ejecutar batch cuando alcanzamos el límite o fin de lista
          if (variationFutures.length >= concurrentLimit || i == variableProducts.length - 1) {
            final results = await Future.wait(variationFutures);
            for (final result in results) {
              final parent = result['parent'] as app_product.Product;
              final variationsData = result['variations'] as List;
              for (final variationJson in variationsData) {
                allProducts.add(app_product.Product.fromJson(
                    variationJson as Map<String, dynamic>,
                    parentNameForVariation: parent.name
                ));
              }
            }
            variationFutures.clear();
            debugPrint("... ✅ Loaded variations batch (${i + 1}/${variableProducts.length})");
          }
        }

        debugPrint("... 🟡 OPTIMIZED: All variations loaded in parallel batches");
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

  /// 🟡 PRIORIDAD 2: Optimizado con paralelización y batching
  /// Antes: N llamadas secuenciales (100 productos = ~50s)
  /// Ahora: Batches de 10 en paralelo (100 productos = ~10s)
  Future<void> updateMultipleProductsStock(List<Map<String, dynamic>> updates) async {
    debugPrint("[InventoryRepository] 🟡 OPTIMIZED: Updating stock for ${updates.length} products in batch.");
    try {
      // 1. Enviar batch update al API
      await _wooCommerceService.updateMultipleProductsStock(updates);
      debugPrint("... Batch stock update sent successfully.");

      // 🟡 PRIORIDAD 2: Paralelizar refresh de caché con batching
      const int concurrentLimit = 10; // Máximo 10 requests simultáneos
      final List<Future<void>> refreshFutures = [];

      for (int i = 0; i < updates.length; i++) {
        final update = updates[i];
        final productId = update['product_id']?.toString();
        final variationId = update['variation_id']?.toString();

        // Agregar future al batch
        if (variationId != null && variationId != '0' && productId != null) {
          refreshFutures.add(
              _productRepository.getVariationById(productId, variationId, forceApi: true)
                  .catchError((e) {
                debugPrint("⚠️ Failed to refresh variation $variationId: $e");
                return null;
              })
          );
        } else if (productId != null) {
          refreshFutures.add(
              _productRepository.getProductById(productId, forceApi: true)
                  .catchError((e) {
                debugPrint("⚠️ Failed to refresh product $productId: $e");
                return null;
              })
          );
        }

        // 🟡 Ejecutar batch cuando alcanzamos el límite o fin de lista
        if (refreshFutures.length >= concurrentLimit || i == updates.length - 1) {
          await Future.wait(refreshFutures);
          refreshFutures.clear();
          debugPrint("... ✅ Refreshed batch (${i + 1}/${updates.length})");
        }
      }

      debugPrint("... 🟡 OPTIMIZED: All ${updates.length} products refreshed in parallel batches");
    } catch (e) {
      debugPrint("Error in InventoryRepository updating multiple stocks: $e");
      rethrow;
    }
  }

  Future<void> resetAllStockToZero() async {
    debugPrint("[InventoryRepository] resetAllStockToZero() llamado. Esta función requiere implementación en el backend.");
    throw UnimplementedError("La funcionalidad de resetear todo el stock a cero no está implementada en el servicio API.");
  }


  // ==================== CACHE MANAGEMENT ====================

  /// ✓ PROPUESTA 1: Método para invalidar caché de inventario
  Future<void> invalidateInventoryCache() async {
    debugPrint("[InventoryRepository] 🗑️ Invalidating inventory history cache");
    _lastInventoryHistoryFetch = null;
  }

  /// ✓ PROPUESTA 1: Método para pre-cargar movimientos en caché (cache warming)
  Future<void> warmCache({int count = 25}) async {
    debugPrint("[InventoryRepository] 🔥 Warming cache with $count recent inventory movements...");
    try {
      final response = await getInventoryMovementsWithSWR(page: 1, perPage: count);
      debugPrint("... ✅ Cache warmed with ${(response['movements'] as List).length} inventory movements");
    } catch (e) {
      debugPrint("... ⚠️ Cache warming failed: $e");
    }
  }

  // ==================== LOCAL-FIRST METHODS ====================

  /// ✅ LOCAL-FIRST: Actualizar estado de sincronización de un movimiento
  /// Usado cuando la sincronización con WooCommerce tiene éxito
  Future<void> updateMovementSyncStatus(String movementId, bool isSynced) async {
    debugPrint("[InventoryRepository] Updating sync status for movement: $movementId → isSynced: $isSynced");

    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository.updateMovementSyncStatus] ❌ ERROR: ObjectBox not initialized");
      throw StateError('ObjectBox not initialized');
    }

    try {
      final box = _db!.store.box<InventoryMovementCompact>();

      // Buscar el movimiento por su movementId
      final query = box.query(InventoryMovementCompact_.movementId.equals(movementId)).build();
      final movement = query.findFirst();
      query.close();

      if (movement != null) {
        // Actualizar el campo isSynced
        movement.isSynced = isSynced;
        box.put(movement);

        debugPrint("[InventoryRepository] ✅ Sync status updated: $movementId → isSynced: $isSynced");

        // Emitir evento de actualización
        final fullMovement = _converter!.compactToMovement(movement);
        _movementUpdateController.add(fullMovement);
      } else {
        debugPrint("[InventoryRepository] ⚠️ Movement not found: $movementId");
      }
    } catch (e) {
      debugPrint("[InventoryRepository.updateMovementSyncStatus] ❌ Error: $e");
      rethrow;
    }
  }

  /// ✅ LOCAL-FIRST: Obtener movimientos locales (no depende de WooCommerce)
  /// Retorna solo datos de ObjectBox, usado para mostrar historial offline
  Future<List<InventoryMovement>> getLocalMovements({
    int page = 1,
    int perPage = 25,
    bool onlyUnsynced = false,
  }) async {
    debugPrint("[InventoryRepository] Getting local movements (page: $page, perPage: $perPage, onlyUnsynced: $onlyUnsynced)");

    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository.getLocalMovements] ❌ ERROR: ObjectBox not initialized");
      return [];
    }

    try {
      final box = _db!.store.box<InventoryMovementCompact>();

      // Construir query
      Query<InventoryMovementCompact> query;

      // Filtrar solo no sincronizados si se solicita
      if (onlyUnsynced) {
        query = box.query(InventoryMovementCompact_.isSynced.equals(false))
            .order(InventoryMovementCompact_.date, flags: Order.descending)
            .build();
      } else {
        query = box.query()
            .order(InventoryMovementCompact_.date, flags: Order.descending)
            .build();
      }

      // Paginación
      final offset = (page - 1) * perPage;
      query.offset = offset;
      query.limit = perPage;

      final compactMovements = query.find();
      query.close();

      // Convertir a InventoryMovement completo
      final movements = compactMovements
          .map((compact) => _converter!.compactToMovement(compact))
          .toList();

      debugPrint("[InventoryRepository] ✅ Found ${movements.length} local movements");

      return movements;
    } catch (e) {
      debugPrint("[InventoryRepository.getLocalMovements] ❌ Error: $e");
      return [];
    }
  }

  /// ✅ LOCAL-FIRST: Obtener conteo de movimientos pendientes de sincronización
  /// Útil para mostrar badges o indicadores en UI
  /// Ahora con caché para evitar llamadas repetidas
  Future<int> getUnsyncedMovementsCount({bool forceRefresh = false}) async {
    if (_db == null) {
      debugPrint("[InventoryRepository.getUnsyncedMovementsCount] ❌ ObjectBox not initialized");
      return 0;
    }

    // Retornar caché si no se fuerza refresh
    if (!forceRefresh && _cachedUnsyncedCount >= 0) {
      return _cachedUnsyncedCount;
    }

    try {
      final box = _db!.store.box<InventoryMovementCompact>();
      final query = box.query(InventoryMovementCompact_.isSynced.equals(false)).build();
      final count = query.count();
      query.close();

      // Solo log si cambió el conteo
      if (_cachedUnsyncedCount != count) {
        debugPrint("[InventoryRepository] 📊 Unsynced movements count: $count");
        _cachedUnsyncedCount = count;
        _unsyncedCountController.add(count); // Emitir al stream
      }

      return count;
    } catch (e) {
      debugPrint("[InventoryRepository.getUnsyncedMovementsCount] ❌ Error: $e");
      return 0;
    }
  }

  /// ✅ Método auxiliar para actualizar el conteo de movimientos no sincronizados
  /// Llamar después de guardar/actualizar/eliminar movimientos
  Future<void> _updateUnsyncedCount() async {
    await getUnsyncedMovementsCount(forceRefresh: true);
  }

  /// ✅ LOCAL-FIRST: SOLO sincronizar historial cuando sea necesario (manual o forzado)
  /// Este método NO se llama automáticamente, solo cuando el usuario lo solicita
  Future<void> syncHistoryFromWooCommerce({bool forceUpdate = false}) async {
    if (!forceUpdate) {
      debugPrint('[InventoryRepository] ⏭️ Sync not forced, skipping WooCommerce sync');
      return;
    }

    debugPrint('[InventoryRepository] 🔄 Syncing history FROM WooCommerce (forced)...');

    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository] ❌ ObjectBox not initialized");
      return;
    }

    try {
      // Obtener historial de WooCommerce (esto depende del endpoint disponible)
      // Por ahora usamos getInventoryMovementsWithSWR que consulta la API
      final response = await getInventoryMovementsWithSWR(page: 1, perPage: 100);

      if (response['movements'] != null && response['movements'] is List) {
        final box = _db!.store.box<InventoryMovementCompact>();
        int imported = 0;

        for (final movementData in response['movements']) {
          try {
            // Verificar si ya existe localmente
            final movementId = movementData['id']?.toString() ?? '';
            if (movementId.isEmpty) continue;

            final query = box.query(InventoryMovementCompact_.movementId.equals(movementId)).build();
            final existing = query.findFirst();
            query.close();

            if (existing == null) {
              // Crear nuevo movimiento desde WooCommerce
              final movement = InventoryMovement.fromJson(movementData);
              // Marcarlo como sincronizado porque viene de WooCommerce
              final syncedMovement = InventoryMovement(
                id: movement.id,
                date: movement.date,
                type: movement.type,
                description: movement.description,
                items: movement.items,
                isSynced: true, // ✅ Ya viene de WooCommerce
              );

              final compact = _converter!.movementToCompact(syncedMovement);
              box.put(compact);
              imported++;
            }
          } catch (e) {
            debugPrint('[InventoryRepository] ⚠️ Error importing movement: $e');
          }
        }

        debugPrint('[InventoryRepository] ✅ Sync from WooCommerce completed: $imported movements imported');
      }
    } catch (e) {
      debugPrint('[InventoryRepository] ❌ Error syncing from WooCommerce: $e');
      rethrow;
    }
  }

  /// 🔍 DEBUG: Método de diagnóstico para investigar movimientos faltantes
  Future<void> debugPrintAllMovements() async {
    if (_db == null || _converter == null) {
      debugPrint("[InventoryRepository.DEBUG] ❌ ObjectBox not initialized");
      return;
    }

    debugPrint("\n==================== 🔍 DIAGNÓSTICO DE INVENTARIO ====================");

    // 1. Contar todos los movimientos en ObjectBox
    final box = _db!.store.box<InventoryMovementCompact>();
    final allCompact = box.getAll();

    debugPrint("[DEBUG] Total movimientos en ObjectBox: ${allCompact.length}");

    // 2. Separar sincronizados vs no sincronizados
    final synced = allCompact.where((m) => m.isSynced).toList();
    final unsynced = allCompact.where((m) => !m.isSynced).toList();

    debugPrint("[DEBUG] Sincronizados: ${synced.length}");
    debugPrint("[DEBUG] NO sincronizados: ${unsynced.length}");

    // 3. Mostrar últimos 5 movimientos (todos, ordenados por fecha)
    allCompact.sort((a, b) => b.date.compareTo(a.date));
    final latest5 = allCompact.take(5).toList();

    debugPrint("\n--- 📋 ÚLTIMOS 5 MOVIMIENTOS EN OBJECTBOX ---");
    for (var i = 0; i < latest5.length; i++) {
      final compact = latest5[i];
      final movement = _converter!.compactToMovement(compact);
      final dateTime = compact.date;

      debugPrint("${i + 1}. [${compact.isSynced ? '✅ SYNCED' : '❌ UNSYNCED'}]");
      debugPrint("   ID: ${compact.movementId}");
      debugPrint("   Fecha: $dateTime (${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')})");
      debugPrint("   Tipo: ${movement.type}");
      debugPrint("   Descripción: ${movement.description}");
      debugPrint("   Items: ${movement.items.length}");

      if (movement.items.isNotEmpty) {
        final firstItem = movement.items.first;
        debugPrint("   Primer Item: ${firstItem.productName}");
        debugPrint("     - SKU: ${firstItem.sku}");
        debugPrint("     - ProductID: ${firstItem.productId}");
        debugPrint("     - VariationID: ${firstItem.variationId ?? 'null'}");
        debugPrint("     - Cantidad: ${firstItem.quantityChanged}");
      }
      debugPrint("");
    }

    // 4. Obtener estadísticas de la cola de sincronización
    final syncStats = _syncManager.getQueueStatistics();

    debugPrint("\n--- 📊 ESTADÍSTICAS DE SYNC QUEUE ---");
    debugPrint("Total operaciones en cola: ${syncStats['total']}");
    debugPrint("Por estado: ${syncStats['byStatus']}");
    debugPrint("Por tipo: ${syncStats['byType']}");
    debugPrint("Procesadas: ${syncStats['totalProcessed']}");
    debugPrint("Exitosas: ${syncStats['totalSucceeded']}");
    debugPrint("Fallidas: ${syncStats['totalFailed']}");

    // 5. Mostrar operaciones de INVENTORY ADJUSTMENT en la cola
    final storageService = getIt<StorageService>();
    final allOperations = storageService.getSyncQueue();
    final inventoryOps = allOperations.where((op) => op.type == SyncOperationType.inventoryAdjustment).toList();

    debugPrint("\n--- 🔍 OPERACIONES DE INVENTARIO EN SYNC QUEUE ---");
    debugPrint("Total operaciones de inventario: ${inventoryOps.length}");

    if (inventoryOps.isNotEmpty) {
      for (var i = 0; i < inventoryOps.length; i++) {
        final op = inventoryOps[i];
        final timestamp = op.timestamp;

        debugPrint("\n${i + 1}. Operación de Inventario:");
        debugPrint("   ID: ${op.id}");
        debugPrint("   Estado: ${op.status.name}");
        debugPrint("   Timestamp: $timestamp (${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')})");
        debugPrint("   Reintentos: ${op.retryCount}");
        debugPrint("   Prioridad: ${op.priority}");

        // Intentar extraer información del movimiento
        try {
          if (op.data['movement'] != null) {
            final movementData = op.data['movement'];
            if (movementData is Map) {
              debugPrint("   Movement ID: ${movementData['id']}");
              debugPrint("   Descripción: ${movementData['description']}");

              if (movementData['items'] != null && movementData['items'] is List) {
                final items = movementData['items'] as List;
                debugPrint("   Items: ${items.length}");

                if (items.isNotEmpty) {
                  final firstItem = items.first;
                  debugPrint("   Primer Item:");
                  debugPrint("     - Producto: ${firstItem['productName']}");
                  debugPrint("     - SKU: ${firstItem['sku']}");
                  debugPrint("     - ProductID: ${firstItem['productId']}");
                  debugPrint("     - VariationID: ${firstItem['variationId'] ?? 'null'}");
                }
              }
            }
          }
        } catch (e) {
          debugPrint("   ⚠️ Error extrayendo datos: $e");
        }
      }
    } else {
      debugPrint("  ✅ No hay operaciones de inventario en la cola");
    }

    debugPrint("\n==================== FIN DIAGNÓSTICO ====================\n");
  }

  void dispose() {
    _movementUpdateController.close();
    debugPrint("[InventoryRepository] Disposed.");
  }
}