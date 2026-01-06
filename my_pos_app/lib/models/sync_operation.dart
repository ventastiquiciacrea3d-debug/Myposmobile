// lib/models/sync_operation.dart
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';

part 'sync_operation.g.dart';

/// ✓ PROPUESTA 2: Tipos de operaciones de sincronización
@HiveType(typeId: 9)
enum SyncOperationType {
  @HiveField(0)
  createOrder,
  @HiveField(1)
  updateOrderStatus,
  @HiveField(2)
  inventoryAdjustment,
  @HiveField(3)
  updateOrder,  // 🔧 NUEVO: Para actualizar pedidos completos (no solo estado)
}

/// ✓ PROPUESTA 2: Estados de una operación de sincronización
@HiveType(typeId: 11)
enum SyncOperationStatus {
  @HiveField(0)
  pending,      // Pendiente de procesamiento
  @HiveField(1)
  retrying,     // Reintentando después de un fallo
  @HiveField(2)
  failed,       // Fallo permanente (max reintentos alcanzado)
  @HiveField(3)
  blocked,      // Bloqueada temporalmente (circuit breaker, backoff)
}

/// ✓ PROPUESTA 2: Niveles de prioridad para operaciones
class SyncPriority {
  static const int critical = 1;   // Ventas, pagos
  static const int high = 2;       // Actualización de inventario
  static const int normal = 3;     // Actualización de estado de orden
  static const int low = 4;        // Reportes, logs
  static const int veryLow = 5;    // Operaciones de limpieza
}

/// ✓ PROPUESTA 2: PERSISTENT QUEUE MANAGER - Modelo Mejorado al 100%
///
/// Mejoras implementadas:
/// 1. ✅ Priorización de operaciones (campo priority)
/// 2. ✅ Backoff exponencial (campo nextRetryAfter)
/// 3. ✅ Deduplicación (campo idempotencyKey)
/// 4. ✅ Estados detallados (campo status)
/// 5. ✅ Tracking de reintentos mejorado (lastAttemptAt)
@HiveType(typeId: 10)
class SyncOperation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final SyncOperationType type;

  @HiveField(2)
  final Map<String, dynamic> data;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  int retryCount;

  // ==================== NUEVOS CAMPOS - PROPUESTA 2 ====================

  /// Prioridad de la operación (1=crítica, 5=muy baja)
  @HiveField(5)
  final int priority;

  /// Timestamp para el siguiente reintento (backoff exponencial)
  @HiveField(6)
  DateTime? nextRetryAfter;

  /// Clave de idempotencia para evitar duplicados
  @HiveField(7)
  final String idempotencyKey;

  /// Estado actual de la operación
  @HiveField(8)
  SyncOperationStatus status;

  /// Timestamp del último intento de procesamiento
  @HiveField(9)
  DateTime? lastAttemptAt;

  SyncOperation({
    required this.type,
    required this.data,
    int? priority,
    String? idempotencyKey,
  })  : id = const Uuid().v4(),
        timestamp = DateTime.now(),
        retryCount = 0,
        priority = priority ?? _getDefaultPriority(type),
        idempotencyKey = idempotencyKey ?? const Uuid().v4(),
        status = SyncOperationStatus.pending,
        nextRetryAfter = null,
        lastAttemptAt = null;

  /// Determina la prioridad por defecto según el tipo de operación
  static int _getDefaultPriority(SyncOperationType type) {
    switch (type) {
      case SyncOperationType.createOrder:
        return SyncPriority.critical; // Ventas son críticas
      case SyncOperationType.updateOrder:
        return SyncPriority.critical; // Actualizaciones de pedidos también son críticas
      case SyncOperationType.inventoryAdjustment:
        return SyncPriority.high; // Inventario es importante
      case SyncOperationType.updateOrderStatus:
        return SyncPriority.normal; // Actualizaciones de estado son normales
    }
  }

  /// ✓ PROPUESTA 2: Calcula el backoff exponencial para el próximo reintento
  /// Formula: min(2^retryCount * baseDelay, maxDelay)
  void calculateNextRetry({
    Duration baseDelay = const Duration(seconds: 5),
    Duration maxDelay = const Duration(hours: 1),
  }) {
    final exponentialSeconds = pow(2, retryCount).toInt() * baseDelay.inSeconds;
    final calculatedDelay = Duration(seconds: min(exponentialSeconds, maxDelay.inSeconds));

    nextRetryAfter = DateTime.now().add(calculatedDelay);
    status = SyncOperationStatus.blocked;
  }

  /// ✓ PROPUESTA 2: Verifica si la operación puede ser reintentada ahora
  bool canRetryNow() {
    if (status == SyncOperationStatus.failed) return false;
    if (nextRetryAfter == null) return true;
    return DateTime.now().isAfter(nextRetryAfter!);
  }

  /// ✓ PROPUESTA 2: Marca la operación como fallida permanentemente
  void markAsFailed() {
    status = SyncOperationStatus.failed;
    nextRetryAfter = null; // No más reintentos
  }

  /// ✓ PROPUESTA 2: Marca la operación como en reintento
  void markAsRetrying() {
    status = SyncOperationStatus.retrying;
    lastAttemptAt = DateTime.now();
  }

  /// ✓ PROPUESTA 2: Resetea el estado a pendiente (útil después de éxito en circuit breaker)
  void resetToPending() {
    status = SyncOperationStatus.pending;
    retryCount = 0;
    nextRetryAfter = null;
    lastAttemptAt = null;
  }

  /// Helper para debugging
  @override
  String toString() {
    return 'SyncOperation('
        'id: $id, '
        'type: ${type.name}, '
        'priority: $priority, '
        'status: ${status.name}, '
        'retryCount: $retryCount, '
        'nextRetry: $nextRetryAfter, '
        'idempotencyKey: $idempotencyKey'
        ')';
  }
}
