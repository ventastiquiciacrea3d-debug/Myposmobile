// lib/services/sync_manager.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'woocommerce_service.dart';
import 'storage_service.dart';
import 'connectivity_service.dart';
import 'database_service.dart';
import '../models/order.dart';
import '../models/inventory_movement.dart';
import '../models/sync_operation.dart';
import '../models/product_optimized.dart';
import 'dart:math' show max;
import '../objectbox.g.dart' hide Order; // ✓ PRIORIDAD 1: Para query helpers (ProductOptimized_), ocultar Order de ObjectBox
import '../repositories/inventory_repository.dart'; // ✅ LOCAL-FIRST: Para actualizar sync status
import '../locator.dart'; // Para obtener InventoryRepository

enum SyncTask { none, pending, full }

/// ✓ PROPUESTA 2: PERSISTENT QUEUE MANAGER - Implementación Completa al 100%
///
/// Mejoras implementadas:
/// 1. ✅ Priorización de operaciones (cola ordenada por prioridad)
/// 2. ✅ Backoff exponencial (reintentos inteligentes con delays crecientes)
/// 3. ✅ Deduplicación (idempotency keys para evitar duplicados)
/// 4. ✅ Estados detallados (pending, retrying, failed, blocked)
/// 5. ✅ NO detiene el proceso completo en errores (continúa con la siguiente operación)
/// 6. ✅ Límite de reintentos configurable (por defecto 10)
/// 7. ✅ Tracking mejorado de métricas (operaciones procesadas, fallos, tiempo)
class SyncManager extends ChangeNotifier {
  final WooCommerceService _wooCommerceService;
  final StorageService _storageService;
  final ConnectivityService _connectivityService;
  final DatabaseService? _databaseService;

  bool _isSyncing = false;
  SyncTask _currentTask = SyncTask.none;
  String? _currentProgressMessage;
  String? _lastError;
  int _queueLength = 0;
  Timer? _syncTimer;

  // ==================== NUEVAS PROPIEDADES - PROPUESTA 2 ====================

  /// Máximo número de reintentos antes de marcar como fallida permanentemente
  static const int maxRetries = 10;

  /// Tracking de idempotency keys procesados recientemente (prevenir duplicados)
  final Set<String> _recentlyProcessedKeys = {};

  /// Timestamp del último procesamiento (para limpieza de caché de idempotency)
  DateTime? _lastIdempotencyCleanup;

  /// Métricas de sincronización
  int _totalProcessed = 0;
  int _totalSucceeded = 0;
  int _totalFailed = 0;

  // ==================== GETTERS PÚBLICOS ====================

  bool get isSyncing => _isSyncing;
  SyncTask get currentTask => _currentTask;
  String? get currentProgressMessage => _currentProgressMessage;
  String? get lastError => _lastError;
  int get queueLength => _queueLength;
  int get totalProcessed => _totalProcessed;
  int get totalSucceeded => _totalSucceeded;
  int get totalFailed => _totalFailed;

  SyncManager({
    required WooCommerceService wooCommerceService,
    required StorageService storageService,
    required ConnectivityService connectivityService,
    DatabaseService? databaseService,
  })  : _wooCommerceService = wooCommerceService,
        _storageService = storageService,
        _connectivityService = connectivityService,
        _databaseService = databaseService {
    _connectivityService.onConnectivityChanged.listen(_handleConnectivityChange);
    _queueLength = _storageService.getSyncQueue().length;
    _scheduleNextSync();
  }

  void _handleConnectivityChange(bool isConnected) {
    if (isConnected) {
      debugPrint("[SyncManager] ✓ Connectivity restored. Triggering sync process.");
      triggerSync();
    }
  }

  void _scheduleNextSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(minutes: 5), () {
      debugPrint("[SyncManager] ⏰ Scheduled sync triggered.");
      triggerSync();
    });
  }

  void _updateQueueLength() {
    final newLength = _storageService.getSyncQueue().length;
    if (_queueLength != newLength) {
      _queueLength = newLength;
      notifyListeners();
    }
  }

  /// ✓ PROPUESTA 2: Agregar operación con soporte de prioridad e idempotency
  Future<void> addOperation(
    SyncOperationType type,
    Map<String, dynamic> data, {
    int? priority,
    String? idempotencyKey,
  }) async {
    // ✓ DEDUPLICACIÓN: Generar idempotency key si no se provee
    final effectiveIdempotencyKey = idempotencyKey ??
        _generateIdempotencyKey(type, data);

    // ✓ DEDUPLICACIÓN: Verificar si ya existe en cola
    final queue = _storageService.getSyncQueue();
    final isDuplicate = queue.any((op) => op.idempotencyKey == effectiveIdempotencyKey);

    if (isDuplicate) {
      debugPrint("[SyncManager] ⚠️ Duplicate operation detected. Idempotency key: $effectiveIdempotencyKey. Skipping.");
      return;
    }

    final operation = SyncOperation(
      type: type,
      data: data,
      priority: priority,
      idempotencyKey: effectiveIdempotencyKey,
    );

    await _storageService.addToSyncQueue(operation);
    _updateQueueLength();

    debugPrint("[SyncManager] ➕ Operation ${type.name} added to queue. "
        "Priority: ${operation.priority}, Queue size: $_queueLength, "
        "IdempotencyKey: ${operation.idempotencyKey.substring(0, 8)}...");

    // Intenta sincronizar inmediatamente
    triggerSync();
  }

  /// ✓ PROPUESTA 2: Generar idempotency key basado en tipo y datos
  String _generateIdempotencyKey(SyncOperationType type, Map<String, dynamic> data) {
    String keyBase = '${type.name}_';

    switch (type) {
      case SyncOperationType.createOrder:
        // Para órdenes, usar el localId si existe
        final localId = data['localId'];
        keyBase += localId ?? data.hashCode.toString();
        break;
      case SyncOperationType.updateOrderStatus:
        // Para actualizaciones, usar orderId + newStatus
        keyBase += '${data['orderId']}_${data['newStatus']}';
        break;
      case SyncOperationType.inventoryAdjustment:
        // Para inventario, usar un hash del movimiento
        final movement = data['movement'];
        keyBase += movement.hashCode.toString();
        break;
    }

    return keyBase;
  }

  /// ✓ PROPUESTA 2: Trigger sincronización con lógica mejorada
  Future<void> triggerSync() async {
    if (_isSyncing) {
      debugPrint("[SyncManager] ⏸️ Sync already in progress. Skipping trigger.");
      return;
    }

    final isConnected = await _connectivityService.checkConnectivity();
    if (!isConnected) {
      debugPrint("[SyncManager] 📡 No network connection. Sync deferred.");
      return;
    }

    final queue = _storageService.getSyncQueue();
    if (queue.isEmpty) {
      debugPrint("[SyncManager] ✅ Queue is empty. Nothing to sync.");
      _scheduleNextSync();
      return;
    }

    _isSyncing = true;
    _currentTask = SyncTask.pending;
    _lastError = null;
    _updateQueueLength();
    notifyListeners();

    debugPrint("[SyncManager] 🔄 Starting sync process. Queue size: ${queue.length}");

    // ✓ PROPUESTA 2: Limpiar caché de idempotency si ha pasado > 1 hora
    _cleanupIdempotencyCache();

    // ✓ PROPUESTA 2: Ordenar cola por prioridad (menor número = mayor prioridad)
    final prioritizedQueue = _getPrioritizedQueue(queue);

    int successCount = 0;
    int skippedCount = 0;
    final int totalOperations = prioritizedQueue.length;
    final startTime = DateTime.now();

    for (int i = 0; i < totalOperations; i++) {
      final operation = prioritizedQueue[i];

      // ✓ PROPUESTA 2: Verificar si debe saltar esta operación (backoff)
      if (!operation.canRetryNow()) {
        final remaining = operation.nextRetryAfter!.difference(DateTime.now());
        debugPrint("[SyncManager] ⏭️ Skipping operation ${operation.id} (${operation.type.name}). "
            "Backoff active. Retry in ${remaining.inSeconds}s.");
        skippedCount++;
        continue;
      }

      _currentProgressMessage = "Sincronizando ${i + 1 - skippedCount} de ${totalOperations - skippedCount}: "
          "${_getOperationName(operation.type)}...";
      notifyListeners();

      // ✓ PROPUESTA 2: Marcar como "retrying" antes de procesar
      operation.markAsRetrying();
      await _storageService.updateSyncOperation(operation);

      try {
        // ✓ PROPUESTA 2: Deduplicación - verificar si ya fue procesado recientemente
        if (_recentlyProcessedKeys.contains(operation.idempotencyKey)) {
          debugPrint("[SyncManager] ⚠️ Operation already processed recently (idempotency). "
              "Removing from queue: ${operation.idempotencyKey.substring(0, 8)}...");
          await _storageService.removeFromSyncQueue(operation.id);
          successCount++;
          continue;
        }

        // Procesar la operación
        await _processOperation(operation);

        // ✓ Éxito - remover de la cola y agregar a caché de idempotency
        await _storageService.removeFromSyncQueue(operation.id);
        _recentlyProcessedKeys.add(operation.idempotencyKey);

        successCount++;
        _totalSucceeded++;

        debugPrint("[SyncManager] ✅ Operation ${operation.id} (${operation.type.name}) "
            "processed successfully. Retry count was: ${operation.retryCount}");
      } catch (e) {
        _lastError = "Error en operación ${_getOperationName(operation.type)}: $e";
        _totalFailed++;

        debugPrint("[SyncManager] ❌ Error processing operation ${operation.id} (${operation.type.name}): $e");

        // ✓ PROPUESTA 2: Incrementar contador de reintentos
        operation.retryCount++;

        // ✓ PROPUESTA 2: Verificar si debe fallar permanentemente
        if (e is AuthenticationException) {
          // Error de autenticación = fallo crítico, marcar como fallida
          operation.markAsFailed();
          debugPrint("[SyncManager] 🔴 AUTHENTICATION ERROR. Operation marked as FAILED permanently.");
          _currentProgressMessage = "Error de autenticación. Sincronización detenida.";
          notifyListeners();
          // ✓ PROPUESTA 2: NO detener el bucle, continuar con la siguiente operación
          // (A menos que sea auth error, que es crítico para todas)
          await _storageService.updateSyncOperation(operation);
          break; // Detener solo en auth error
        } else if (operation.retryCount > maxRetries) {
          // Máximo de reintentos alcanzado
          operation.markAsFailed();
          debugPrint("[SyncManager] 🔴 MAX RETRIES ($maxRetries) reached. Operation marked as FAILED permanently.");

          // 🔴 PRIORIDAD 1: Rollback de stock si es operación de crear pedido
          if (operation.type == SyncOperationType.createOrder) {
            await _rollbackLocalStockOnOrderFailure(operation);
          }
        } else {
          // ✓ PROPUESTA 2: Calcular backoff exponencial
          operation.calculateNextRetry();
          debugPrint("[SyncManager] 🔄 Operation will retry after: ${operation.nextRetryAfter}. "
              "Retry count: ${operation.retryCount}/$maxRetries");
        }

        await _storageService.updateSyncOperation(operation);

        // ✓ PROPUESTA 2: CONTINUAR con la siguiente operación (no detener el bucle)
      }

      _totalProcessed++;
    }

    final duration = DateTime.now().difference(startTime);

    if (successCount == totalOperations - skippedCount) {
      _currentProgressMessage = "✅ Sincronización completada ($successCount operaciones en ${duration.inSeconds}s).";
    } else {
      _currentProgressMessage = "⚠️ $successCount de ${totalOperations - skippedCount} operaciones sincronizadas "
          "($skippedCount omitidas por backoff). Algunas fallaron.";
    }

    debugPrint("[SyncManager] 📊 Sync completed. Success: $successCount, "
        "Skipped: $skippedCount, Failed: ${totalOperations - successCount - skippedCount}, "
        "Duration: ${duration.inSeconds}s");

    _isSyncing = false;
    _currentTask = SyncTask.none;
    _updateQueueLength();
    notifyListeners();
    _scheduleNextSync();
  }

  /// ✓ PROPUESTA 2: Obtener cola ordenada por prioridad
  List<SyncOperation> _getPrioritizedQueue(List<SyncOperation> queue) {
    final sortedQueue = List<SyncOperation>.from(queue);

    // Ordenar por prioridad (menor número = mayor prioridad)
    // Si tienen la misma prioridad, ordenar por timestamp (FIFO)
    sortedQueue.sort((a, b) {
      final priorityComparison = a.priority.compareTo(b.priority);
      if (priorityComparison != 0) return priorityComparison;
      return a.timestamp.compareTo(b.timestamp);
    });

    return sortedQueue;
  }

  /// ✓ PROPUESTA 2: Limpiar caché de idempotency keys cada hora
  void _cleanupIdempotencyCache() {
    final now = DateTime.now();

    if (_lastIdempotencyCleanup == null ||
        now.difference(_lastIdempotencyCleanup!) > const Duration(hours: 1)) {
      final sizeBefore = _recentlyProcessedKeys.length;
      _recentlyProcessedKeys.clear();
      _lastIdempotencyCleanup = now;

      if (sizeBefore > 0) {
        debugPrint("[SyncManager] 🧹 Idempotency cache cleaned. Removed $sizeBefore keys.");
      }
    }
  }

  String _getOperationName(SyncOperationType type) {
    switch (type) {
      case SyncOperationType.createOrder:
        return "Crear Pedido";
      case SyncOperationType.updateOrderStatus:
        return "Actualizar Estado";
      case SyncOperationType.inventoryAdjustment:
        return "Ajuste de Inventario";
    }
  }

  Future<void> _processOperation(SyncOperation operation) async {
    debugPrint("[SyncManager] 🔧 Processing operation ${operation.id} of type ${operation.type.name}");

    switch (operation.type) {
      case SyncOperationType.createOrder:
        final order = Order.fromJson(operation.data['order']);
        final serverId = await _wooCommerceService.createOrderAPI(order);

        if (serverId != null) {
          final localId = operation.data['localId'];
          if (localId != null) {
            await _storageService.removePendingOrder(localId);
            debugPrint("[SyncManager] ✓ Pending order $localId removed after successful sync. Server ID: $serverId");
          }
        } else {
          throw ApiException("El servidor no devolvió un ID para el pedido creado.");
        }
        break;

      case SyncOperationType.updateOrderStatus:
        await _wooCommerceService.updateOrderStatus(
          operation.data['orderId'],
          operation.data['newStatus'],
        );
        break;

      case SyncOperationType.inventoryAdjustment:
        await _processInventoryAdjustment(operation);
        break;
    }
  }

  /// ✓ PROPUESTA 2: Método público para obtener estadísticas de la cola
  Map<String, dynamic> getQueueStatistics() {
    final queue = _storageService.getSyncQueue();

    final byStatus = <SyncOperationStatus, int>{};
    final byType = <SyncOperationType, int>{};
    final byPriority = <int, int>{};

    for (final op in queue) {
      byStatus[op.status] = (byStatus[op.status] ?? 0) + 1;
      byType[op.type] = (byType[op.type] ?? 0) + 1;
      byPriority[op.priority] = (byPriority[op.priority] ?? 0) + 1;
    }

    return {
      'total': queue.length,
      'byStatus': byStatus.map((k, v) => MapEntry(k.name, v)),
      'byType': byType.map((k, v) => MapEntry(k.name, v)),
      'byPriority': byPriority,
      'totalProcessed': _totalProcessed,
      'totalSucceeded': _totalSucceeded,
      'totalFailed': _totalFailed,
    };
  }

  /// ✓ PROPUESTA 2: Limpiar operaciones fallidas permanentemente
  Future<int> cleanupFailedOperations() async {
    final queue = _storageService.getSyncQueue();
    final failedOps = queue.where((op) => op.status == SyncOperationStatus.failed).toList();

    for (final op in failedOps) {
      await _storageService.removeFromSyncQueue(op.id);
    }

    _updateQueueLength();

    debugPrint("[SyncManager] 🧹 Cleaned up ${failedOps.length} permanently failed operations.");

    return failedOps.length;
  }

  /// ✓ PROPUESTA 2: Resetear métricas (útil para testing)
  void resetMetrics() {
    _totalProcessed = 0;
    _totalSucceeded = 0;
    _totalFailed = 0;
    notifyListeners();
  }

  /// 🔴 PRIORIDAD 1: Rollback de stock local cuando falla sincronización de pedido
  /// Restaura el stock que fue reducido localmente al crear el pedido
  Future<void> _rollbackLocalStockOnOrderFailure(SyncOperation operation) async {
    if (_databaseService == null) {
      debugPrint("[SyncManager.rollback] ⚠️ DatabaseService not available. Cannot rollback stock.");
      return;
    }

    try {
      final orderData = operation.data['order'] as Map<String, dynamic>?;
      if (orderData == null) {
        debugPrint("[SyncManager.rollback] ⚠️ No order data found in failed operation.");
        return;
      }

      final order = Order.fromJson(orderData);
      debugPrint("[SyncManager.rollback] 🔄 Rolling back stock for failed order ${order.id} (${order.items.length} items)");

      final box = _databaseService!.store.box<ProductOptimized>();

      for (final item in order.items) {
        // Obtener ID del producto (variación o producto simple)
        final int productId;
        if (item.variationId != null && item.variationId! > 0) {
          productId = item.variationId!;
        } else {
          productId = int.tryParse(item.productId) ?? 0;
        }

        if (productId == 0) continue;

        // Buscar producto en ObjectBox
        final query = box.query(ProductOptimized_.id.equals(productId)).build();
        final product = query.findFirst();
        query.close();

        if (product != null) {
          final int oldStock = product.stockQuantity;

          // 🔄 ROLLBACK: Restaurar stock (sumar lo que se había restado)
          product.stockQuantity += item.quantity.toInt();
          product.lastUpdated = DateTime.now();

          // Guardar cambio en ObjectBox
          box.put(product);

          debugPrint("... ✅ ${product.name}: $oldStock → ${product.stockQuantity} (+${item.quantity.toInt()} rollback)");
        }
      }

      debugPrint("[SyncManager.rollback] ✅ Stock rollback completed successfully for order ${order.id}");
    } catch (e, stackTrace) {
      debugPrint("[SyncManager.rollback] ❌ ERROR during stock rollback: $e\n$stackTrace");
      // No rethrow - el rollback es best-effort, no crítico
    }
  }

  /// ✅ LOCAL-FIRST: Procesar ajuste de inventario con reintento
  /// Envía el batch a WooCommerce y actualiza el sync status en ObjectBox
  Future<void> _processInventoryAdjustment(SyncOperation operation) async {
    debugPrint("[SyncManager] 🔧 Processing inventory adjustment: ${operation.id}");

    try {
      final movement = InventoryMovement.fromJson(operation.data['movement']);

      // Preparar batch de actualizaciones para WooCommerce
      final batchItems = movement.items.map((item) {
        return {
          'id': item.productId,
          'stock': item.quantityChanged.abs(),
          'operation': item.quantityChanged > 0 ? 'add' : 'subtract',
        };
      }).toList();

      debugPrint("[SyncManager] Sending batch to WooCommerce: ${batchItems.length} items");

      // Enviar a WooCommerce
      final response = await _wooCommerceService.batchUpdateStock(batchItems);

      if (response['success'] == true) {
        final updated = response['updated'] as int? ?? 0;
        debugPrint('[SyncManager] ✅ Inventory adjustment synced to WooCommerce: $updated products');

        // ✅ Actualizar estado de sincronización en ObjectBox
        try {
          final inventoryRepo = getIt<InventoryRepository>();
          await inventoryRepo.updateMovementSyncStatus(movement.id, true);
          debugPrint('[SyncManager] ✅ Movement ${movement.id} marked as synced in ObjectBox');
        } catch (e) {
          debugPrint('[SyncManager] ⚠️ Error updating sync status (non-critical): $e');
          // No es crítico - la sincronización con WooCommerce fue exitosa
        }
      } else {
        throw ApiException('WooCommerce returned success=false for batch update');
      }

    } catch (e) {
      debugPrint('[SyncManager] ❌ Error processing inventory adjustment: $e');
      rethrow; // Re-lanzar para que el manejador de sync lo capture y reintente
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}
