// lib/services/transaction_scope.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'transaction_service.dart';

/// ✓ PROPUESTA 3: Transaction Scope - Helper para usar transacciones fácilmente
///
/// Proporciona una API simple y segura para ejecutar operaciones transaccionales
/// con rollback automático en caso de error.
///
/// Uso:
/// ```dart
/// await TransactionScope.execute(
///   transactionService,
///   (tx) async {
///     await tx.put(ordersBox, orderId, order);
///     await tx.put(productsBox, productId, product);
///     // Si cualquier operación falla, se hace rollback automático
///   },
/// );
/// ```
class TransactionScope {
  final TransactionService _transactionService;
  final Transaction _transaction;

  TransactionScope._(this._transactionService, this._transaction);

  /// Ejecutar un bloque de código dentro de una transacción
  static Future<T> execute<T>(
    TransactionService transactionService,
    Future<T> Function(TransactionScope tx) block, {
    String? name,
  }) async {
    final tx = await transactionService.begin();
    final scope = TransactionScope._(transactionService, tx);

    debugPrint("[TransactionScope] ${name ?? 'Anonymous'} - BEGIN");

    try {
      // Ejecutar bloque
      final result = await block(scope);

      // Commit si todo salió bien
      await transactionService.commit(tx);

      debugPrint("[TransactionScope] ${name ?? 'Anonymous'} - COMMITTED");
      return result;
    } catch (e, stackTrace) {
      // Rollback automático en caso de error
      debugPrint("[TransactionScope] ${name ?? 'Anonymous'} - ERROR: $e");
      debugPrint("StackTrace: $stackTrace");

      try {
        await transactionService.rollback(tx);
        debugPrint("[TransactionScope] ${name ?? 'Anonymous'} - ROLLED BACK");
      } catch (rollbackError) {
        debugPrint("[TransactionScope] ❌ Rollback failed: $rollbackError");
      }

      rethrow;
    }
  }

  /// PUT operation dentro de la transacción
  Future<void> put<T>(Box<T> box, dynamic key, T value) async {
    // Registrar en undo log ANTES de hacer la operación
    await _transactionService.recordPut(_transaction, box, key, value);

    // Ejecutar la operación
    await _transactionService.execute(
      _transaction,
      box.name,
      () async {
        await box.put(key, value);
      },
    );
  }

  /// DELETE operation dentro de la transacción
  Future<void> delete<T>(Box<T> box, dynamic key) async {
    // Registrar en undo log ANTES de hacer la operación
    await _transactionService.recordDelete(_transaction, box, key);

    // Ejecutar la operación
    await _transactionService.execute(
      _transaction,
      box.name,
      () async {
        await box.delete(key);
      },
    );
  }

  /// PUT ALL operation dentro de la transacción
  Future<void> putAll<T>(Box<T> box, Map<dynamic, T> entries) async {
    for (final entry in entries.entries) {
      await put(box, entry.key, entry.value);
    }
  }

  /// DELETE ALL operation dentro de la transacción
  Future<void> deleteAll<T>(Box<T> box, Iterable<dynamic> keys) async {
    for (final key in keys) {
      await delete(box, key);
    }
  }

  /// Ejecutar operación custom (sin undo log automático)
  Future<void> executeRaw(String boxName, Future<void> Function() operation) async {
    await _transactionService.execute(
      _transaction,
      boxName,
      operation,
    );
  }

  /// ID de la transacción
  String get transactionId => _transaction.id;

  /// Estado de la transacción
  TransactionState get state => _transaction.state;

  /// Número de operaciones registradas
  int get operationCount => _transaction.operations.length;
}

/// Helper para operaciones transaccionales comunes
class TransactionHelpers {
  /// Transferir item entre boxes (operación atómica)
  static Future<void> transfer<T>({
    required TransactionService transactionService,
    required Box<T> sourceBox,
    required Box<T> targetBox,
    required dynamic key,
  }) async {
    await TransactionScope.execute(
      transactionService,
      (tx) async {
        // Obtener valor del source
        final value = sourceBox.get(key);
        if (value == null) {
          throw TransactionException("Item not found in source box: $key");
        }

        // Eliminar del source
        await tx.delete(sourceBox, key);

        // Agregar al target
        await tx.put(targetBox, key, value);
      },
      name: 'Transfer-$key',
    );
  }

  /// Swap de dos items (operación atómica)
  static Future<void> swap<T>({
    required TransactionService transactionService,
    required Box<T> box,
    required dynamic key1,
    required dynamic key2,
  }) async {
    await TransactionScope.execute(
      transactionService,
      (tx) async {
        final value1 = box.get(key1);
        final value2 = box.get(key2);

        if (value1 == null || value2 == null) {
          throw TransactionException("One or both items not found");
        }

        await tx.put(box, key1, value2);
        await tx.put(box, key2, value1);
      },
      name: 'Swap-$key1-$key2',
    );
  }

  /// Batch update con validación
  static Future<void> batchUpdate<T>({
    required TransactionService transactionService,
    required Box<T> box,
    required Map<dynamic, T> updates,
    Future<void> Function(Map<dynamic, T>)? validator,
  }) async {
    await TransactionScope.execute(
      transactionService,
      (tx) async {
        // Validar antes de aplicar cambios
        if (validator != null) {
          await validator(updates);
        }

        // Aplicar todos los updates
        await tx.putAll(box, updates);
      },
      name: 'BatchUpdate-${updates.length}',
    );
  }

  /// Conditional update - solo actualiza si la condición se cumple
  static Future<bool> conditionalUpdate<T>({
    required TransactionService transactionService,
    required Box<T> box,
    required dynamic key,
    required T newValue,
    required bool Function(T? currentValue) condition,
  }) async {
    bool updated = false;

    await TransactionScope.execute(
      transactionService,
      (tx) async {
        final currentValue = box.get(key);

        if (condition(currentValue)) {
          await tx.put(box, key, newValue);
          updated = true;
        } else {
          throw TransactionException("Condition not met for update");
        }
      },
      name: 'ConditionalUpdate-$key',
    );

    return updated;
  }

  /// Crear o actualizar con validación de duplicados
  static Future<void> upsert<T>({
    required TransactionService transactionService,
    required Box<T> box,
    required dynamic key,
    required T value,
    required bool Function(T? existing, T newValue) allowUpdate,
  }) async {
    await TransactionScope.execute(
      transactionService,
      (tx) async {
        final existing = box.get(key);

        if (existing != null) {
          // Ya existe, validar si podemos actualizar
          if (!allowUpdate(existing, value)) {
            throw TransactionException("Update not allowed for key: $key");
          }
        }

        await tx.put(box, key, value);
      },
      name: 'Upsert-$key',
    );
  }
}

/// Extension methods para Box para uso más conveniente
extension BoxTransactionExtensions<T> on Box<T> {
  /// PUT transaccional
  Future<void> putTx(
    TransactionService transactionService,
    dynamic key,
    T value,
  ) async {
    await TransactionScope.execute(
      transactionService,
      (tx) async => await tx.put(this, key, value),
      name: 'Put-$name-$key',
    );
  }

  /// DELETE transaccional
  Future<void> deleteTx(
    TransactionService transactionService,
    dynamic key,
  ) async {
    await TransactionScope.execute(
      transactionService,
      (tx) async => await tx.delete(this, key),
      name: 'Delete-$name-$key',
    );
  }

  /// PUT ALL transaccional
  Future<void> putAllTx(
    TransactionService transactionService,
    Map<dynamic, T> entries,
  ) async {
    await TransactionScope.execute(
      transactionService,
      (tx) async => await tx.putAll(this, entries),
      name: 'PutAll-$name-${entries.length}',
    );
  }
}
