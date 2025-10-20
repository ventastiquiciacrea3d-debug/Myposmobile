// lib/services/sync_manager.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'woocommerce_service.dart';
import 'storage_service.dart';
import 'connectivity_service.dart';
import '../models/order.dart';
import '../models/inventory_movement.dart';
import '../models/sync_operation.dart';
import '../config/constants.dart';

enum SyncTask { none, pending, full }

class SyncManager extends ChangeNotifier {
  final WooCommerceService _wooCommerceService;
  final StorageService _storageService;
  final ConnectivityService _connectivityService;

  bool _isSyncing = false;
  SyncTask _currentTask = SyncTask.none;
  String? _currentProgressMessage;
  String? _lastError;
  int _queueLength = 0;
  Timer? _syncTimer;

  bool get isSyncing => _isSyncing;
  SyncTask get currentTask => _currentTask;
  String? get currentProgressMessage => _currentProgressMessage;
  String? get lastError => _lastError;
  int get queueLength => _queueLength;

  SyncManager({
    required WooCommerceService wooCommerceService,
    required StorageService storageService,
    required ConnectivityService connectivityService,
  })  : _wooCommerceService = wooCommerceService,
        _storageService = storageService,
        _connectivityService = connectivityService {
    _connectivityService.onConnectivityChanged.listen(_handleConnectivityChange);
    _queueLength = _storageService.getSyncQueue().length;
    _scheduleNextSync();
  }

  void _handleConnectivityChange(bool isConnected) {
    if (isConnected) {
      debugPrint("[SyncManager] Connectivity restored. Triggering sync process.");
      triggerSync();
    }
  }

  void _scheduleNextSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(minutes: 5), () {
      debugPrint("[SyncManager] Scheduled sync triggered.");
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

  Future<void> addOperation(SyncOperationType type, Map<String, dynamic> data) async {
    final operation = SyncOperation(type: type, data: data);
    await _storageService.addToSyncQueue(operation);
    _updateQueueLength();
    debugPrint("[SyncManager] Operation ${type.name} added to queue. Queue size: $_queueLength");
    triggerSync(); // Intenta sincronizar inmediatamente
  }

  Future<void> triggerSync() async {
    if (_isSyncing) return;

    final isConnected = await _connectivityService.checkConnectivity();
    if (!isConnected) {
      debugPrint("[SyncManager] Sync trigger ignored: No network connection.");
      return;
    }

    final queue = _storageService.getSyncQueue();
    if (queue.isEmpty) {
      debugPrint("[SyncManager] Sync trigger ignored: Queue is empty.");
      _scheduleNextSync();
      return;
    }

    _isSyncing = true;
    _currentTask = SyncTask.pending;
    _lastError = null;
    _updateQueueLength();
    notifyListeners();

    int successCount = 0;
    final int totalOperations = queue.length;

    for (int i = 0; i < totalOperations; i++) {
      final operation = queue[i];
      _currentProgressMessage = "Sincronizando ${i + 1} de $totalOperations: ${_getOperationName(operation.type)}...";
      notifyListeners();

      try {
        await _processOperation(operation);
        await _storageService.removeFromSyncQueue(operation.id);
        successCount++;
        _updateQueueLength();
      } catch (e) {
        _lastError = "Error en operación ${_getOperationName(operation.type)}: $e";
        operation.retryCount++;
        await _storageService.updateSyncOperation(operation);

        if (e is AuthenticationException || operation.retryCount > 3) {
          _currentProgressMessage = "Error crítico. Sincronización detenida.";
          notifyListeners();
          break; // Detener el bucle en error crítico
        }
      }
    }

    if(successCount == totalOperations) {
      _currentProgressMessage = "Sincronización completada ($successCount operaciones).";
    } else {
      _currentProgressMessage = "$successCount de $totalOperations operaciones sincronizadas. Algunas fallaron.";
    }

    _isSyncing = false;
    _currentTask = SyncTask.none;
    notifyListeners();
    _scheduleNextSync();
  }

  String _getOperationName(SyncOperationType type) {
    switch(type) {
      case SyncOperationType.createOrder: return "Crear Pedido";
      case SyncOperationType.updateOrderStatus: return "Actualizar Estado";
      case SyncOperationType.inventoryAdjustment: return "Ajuste de Inventario";
    }
  }

  Future<void> _processOperation(SyncOperation operation) async {
    debugPrint("[SyncManager] Processing operation ${operation.id} of type ${operation.type.name}");
    switch (operation.type) {
      case SyncOperationType.createOrder:
        final order = Order.fromJson(operation.data['order']);
        final serverId = await _wooCommerceService.createOrderAPI(order);
        if (serverId != null) {
          final localId = operation.data['localId'];
          if (localId != null) {
            await _storageService.removePendingOrder(localId);
          }
        } else {
          throw ApiException("El servidor no devolvió un ID para el pedido creado.");
        }
        break;
      case SyncOperationType.updateOrderStatus:
        await _wooCommerceService.updateOrderStatus(operation.data['orderId'], operation.data['newStatus']);
        break;
      case SyncOperationType.inventoryAdjustment:
        final movement = InventoryMovement.fromJson(operation.data['movement']);
        await _wooCommerceService.submitInventoryAdjustment(movement);
        break;
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}