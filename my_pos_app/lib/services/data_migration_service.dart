// lib/services/data_migration_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart' as hive;
import '../models/product_optimized.dart';
import '../models/product.dart';
import '../models/order.dart' as model;
import '../models/order_compact.dart';
import '../models/label_print_item.dart';
import '../models/label_print_item_compact.dart';
import '../utils/product_attribute_serializer.dart';
import 'database_service.dart';
import 'order_converter_service.dart';
import 'label_converter_service.dart';
import '../objectbox.g.dart' hide Box; // ✅ Evitar conflicto con hive.Box

/// Servicio de migración de datos Hive → ObjectBox
///
/// **Responsabilidades:**
/// - Migrar atributos de productos desde Hive a ObjectBox
/// - Migrar órdenes (pendientes y completadas) desde Hive a ObjectBox
/// - Migrar cola de impresión de labels desde Hive a ObjectBox
/// - Verificar integridad de la migración
/// - Proporcionar estadísticas y logs detallados
class DataMigrationService {
  final DatabaseService _dbService;
  final hive.Box? _settingsBox;
  final hive.Box<Product>? _productBox;
  final hive.Box<model.Order>? _orderBox;
  final hive.Box<model.Order>? _pendingOrderBox;
  final hive.Box<LabelPrintItem>? _labelQueueBox;
  final OrderConverterService _orderConverter;
  final LabelConverterService _labelConverter;

  DataMigrationService({
    required DatabaseService dbService,
    required hive.Box? settingsBox,
    required hive.Box<Product>? productBox,
    hive.Box<model.Order>? orderBox,
    hive.Box<model.Order>? pendingOrderBox,
    hive.Box<LabelPrintItem>? labelQueueBox,
  })  : _dbService = dbService,
        _settingsBox = settingsBox,
        _productBox = productBox,
        _orderBox = orderBox,
        _pendingOrderBox = pendingOrderBox,
        _labelQueueBox = labelQueueBox,
        _orderConverter = OrderConverterService(),
        _labelConverter = LabelConverterService();

  /// Migra atributos de Hive a ObjectBox
  ///
  /// **Proceso:**
  /// 1. Leer todos los productos de ObjectBox
  /// 2. Para cada producto:
  ///    a. Buscar atributos en Hive (SettingsBox: 'product_faf_{id}')
  ///    b. Buscar Product en Hive (ProductBox) para attributes
  ///    c. Comprimir AMBOS tipos
  ///    d. Actualizar ProductOptimized en ObjectBox
  /// 3. Verificar integridad
  /// 4. Opcionalmente limpiar datos de Hive
  ///
  /// **Parámetros:**
  /// - `deleteHiveDataAfter`: Si true, elimina datos de Hive después de migrar exitosamente
  ///
  /// **Returns:** MigrationResult con estadísticas
  Future<MigrationResult> migrateAttributesHiveToObjectBox({
    bool deleteHiveDataAfter = false,
  }) async {
    final startTime = DateTime.now();
    int totalProducts = 0;
    int successCount = 0;
    int failCount = 0;
    int skippedCount = 0;
    int alreadyMigratedCount = 0;
    final List<String> errors = [];

    try {
      debugPrint('[Migration] ========================================');
      debugPrint('[Migration] INICIANDO MIGRACIÓN Hive → ObjectBox');
      debugPrint('[Migration] ========================================');

      final store = _dbService.store;
      if (store == null) {
        throw Exception('ObjectBox store not initialized');
      }

      final box = store.box<ProductOptimized>();
      final allProducts = box.getAll();
      totalProducts = allProducts.length;

      debugPrint('[Migration] Total productos en ObjectBox: $totalProducts');

      // Procesar cada producto
      for (final productOptimized in allProducts) {
        final productId = productOptimized.id.toString();

        try {
          // 1. Verificar si ya tiene atributos comprimidos
          if (productOptimized.attributesCompressed != null &&
              productOptimized.attributesCompressed!.isNotEmpty) {
            alreadyMigratedCount++;
            continue;
          }

          // 2. Buscar fullAttributesWithOptions en Hive SettingsBox
          List<Map<String, dynamic>>? fullAttrs;
          if (_settingsBox != null) {
            final attributesJson =
                _settingsBox!.get('product_faf_$productId') as String?;
            if (attributesJson != null && attributesJson.isNotEmpty) {
              try {
                fullAttrs = List<Map<String, dynamic>>.from(
                    jsonDecode(attributesJson));
              } catch (e) {
                debugPrint(
                    '[Migration] Producto $productId: Error parsing fullAttributes: $e');
              }
            }
          }

          // 3. Buscar attributes en Hive ProductBox
          List<Map<String, dynamic>>? attrs;
          if (_productBox != null) {
            final hiveProduct = _productBox!.get(productId);
            if (hiveProduct != null && hiveProduct.attributes != null) {
              attrs = hiveProduct.attributes;
            }
          }

          // 4. Si no hay atributos, skip
          if ((attrs == null || attrs.isEmpty) &&
              (fullAttrs == null || fullAttrs.isEmpty)) {
            skippedCount++;
            continue;
          }

          // 5. Comprimir atributos
          final compressed = ProductAttributeSerializer.compressBoth(
            attributes: attrs,
            fullAttributesWithOptions: fullAttrs,
          );

          if (compressed == null) {
            debugPrint(
                '[Migration] Producto $productId: Error comprimiendo atributos');
            failCount++;
            errors.add('Producto $productId: Compresión falló');
            continue;
          }

          // 6. Actualizar en ObjectBox
          productOptimized.attributesCompressed = compressed;
          box.put(productOptimized);

          successCount++;
          debugPrint(
              '[Migration] Producto $productId: ✅ Migrado (${attrs?.length ?? 0} attrs + ${fullAttrs?.length ?? 0} fullAttrs → ${compressed.length} bytes)');
        } catch (e) {
          failCount++;
          errors.add('Producto $productId: $e');
          debugPrint('[Migration] Producto $productId: ❌ Error: $e');
        }
      }

      // 7. Limpieza de Hive (opcional)
      if (deleteHiveDataAfter && successCount > 0) {
        debugPrint('[Migration] Limpiando datos de Hive...');

        if (_settingsBox != null) {
          final keysToDelete = _settingsBox!.keys
              .where((key) => key.toString().startsWith('product_faf_'))
              .toList();

          for (final key in keysToDelete) {
            await _settingsBox!.delete(key);
          }

          debugPrint(
              '[Migration] Eliminadas ${keysToDelete.length} claves de SettingsBox');
        }
      }

      final duration = DateTime.now().difference(startTime);

      debugPrint('[Migration] ========================================');
      debugPrint('[Migration] MIGRACIÓN COMPLETADA');
      debugPrint('[Migration] Total: $totalProducts');
      debugPrint('[Migration] Ya migrados: $alreadyMigratedCount');
      debugPrint('[Migration] Migrados ahora: $successCount');
      debugPrint('[Migration] Fallos: $failCount');
      debugPrint('[Migration] Omitidos (sin attrs): $skippedCount');
      debugPrint('[Migration] Duración: ${duration.inSeconds}s');
      debugPrint('[Migration] ========================================');

      return MigrationResult(
        success: failCount == 0,
        totalProducts: totalProducts,
        alreadyMigratedCount: alreadyMigratedCount,
        successCount: successCount,
        failCount: failCount,
        skippedCount: skippedCount,
        errors: errors,
        duration: duration,
      );
    } catch (e) {
      debugPrint('[Migration] ❌ ERROR FATAL: $e');
      return MigrationResult(
        success: false,
        totalProducts: totalProducts,
        alreadyMigratedCount: alreadyMigratedCount,
        successCount: successCount,
        failCount: failCount,
        skippedCount: skippedCount,
        errors: [...errors, 'Fatal: $e'],
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Migra órdenes de Hive a ObjectBox
  ///
  /// **Proceso:**
  /// 1. Leer todas las órdenes pendientes de Hive (PendingOrderBox)
  /// 2. Leer todas las órdenes completadas de Hive (OrderBox)
  /// 3. Para cada orden:
  ///    a. Convertir usando OrderConverterService
  ///    b. Guardar en ObjectBox
  /// 4. Verificar integridad
  /// 5. Opcionalmente limpiar datos de Hive
  ///
  /// **Parámetros:**
  /// - `deleteHiveDataAfter`: Si true, elimina datos de Hive después de migrar exitosamente
  ///
  /// **Returns:** MigrationResult con estadísticas
  Future<MigrationResult> migrateOrdersHiveToObjectBox({
    bool deleteHiveDataAfter = false,
  }) async {
    final startTime = DateTime.now();
    int totalOrders = 0;
    int successCount = 0;
    int failCount = 0;
    int skippedCount = 0;
    int alreadyMigratedCount = 0;
    final List<String> errors = [];

    try {
      debugPrint('[OrderMigration] ========================================');
      debugPrint('[OrderMigration] INICIANDO MIGRACIÓN Orders Hive → ObjectBox');
      debugPrint('[OrderMigration] ========================================');

      final store = _dbService.store;
      if (store == null) {
        throw Exception('ObjectBox store not initialized');
      }

      final box = store.box<OrderCompact>();

      // 1. MIGRAR ÓRDENES PENDIENTES
      debugPrint('[OrderMigration] Migrando órdenes pendientes...');
      int pendingMigrated = 0;

      if (_pendingOrderBox != null && _pendingOrderBox!.isNotEmpty) {
        final pendingOrders = _pendingOrderBox!.toMap();
        debugPrint('[OrderMigration] Total órdenes pendientes en Hive: ${pendingOrders.length}');

        for (final entry in pendingOrders.entries) {
          final localId = entry.key.toString();
          final order = entry.value;
          totalOrders++;

          try {
            // Verificar si ya existe en ObjectBox
            final query = box.query(OrderCompact_.localOrderId.equals(localId)).build();
            final existing = query.findFirst();
            query.close();

            if (existing != null) {
              alreadyMigratedCount++;
              debugPrint('[OrderMigration] Orden pendiente $localId: Ya existe en ObjectBox');
              continue;
            }

            // Convertir y guardar
            final compact = _orderConverter.orderToCompact(order);
            box.put(compact);

            successCount++;
            pendingMigrated++;
            debugPrint('[OrderMigration] Orden pendiente $localId: ✅ Migrada (${order.items.length} items, total: \$${order.total})');
          } catch (e) {
            failCount++;
            errors.add('Orden pendiente $localId: $e');
            debugPrint('[OrderMigration] Orden pendiente $localId: ❌ Error: $e');
          }
        }

        debugPrint('[OrderMigration] Órdenes pendientes migradas: $pendingMigrated');
      } else {
        debugPrint('[OrderMigration] No hay órdenes pendientes en Hive');
      }

      // 2. MIGRAR ÓRDENES COMPLETADAS
      debugPrint('[OrderMigration] Migrando órdenes completadas...');
      int completedMigrated = 0;

      if (_orderBox != null && _orderBox!.isNotEmpty) {
        final completedOrders = _orderBox!.toMap();
        debugPrint('[OrderMigration] Total órdenes completadas en Hive: ${completedOrders.length}');

        for (final entry in completedOrders.entries) {
          final orderId = entry.key.toString();
          final order = entry.value;
          totalOrders++;

          try {
            // Verificar si ya existe en ObjectBox
            final orderIdInt = int.tryParse(orderId);
            if (orderIdInt == null) {
              skippedCount++;
              debugPrint('[OrderMigration] Orden completada $orderId: ID inválido, skip');
              continue;
            }

            final query = box.query(OrderCompact_.orderId.equals(orderIdInt)).build();
            final existing = query.findFirst();
            query.close();

            if (existing != null) {
              alreadyMigratedCount++;
              debugPrint('[OrderMigration] Orden completada $orderId: Ya existe en ObjectBox');
              continue;
            }

            // Convertir y guardar
            final compact = _orderConverter.orderToCompact(order);
            box.put(compact);

            successCount++;
            completedMigrated++;
            debugPrint('[OrderMigration] Orden completada $orderId: ✅ Migrada (${order.items.length} items, total: \$${order.total})');
          } catch (e) {
            failCount++;
            errors.add('Orden completada $orderId: $e');
            debugPrint('[OrderMigration] Orden completada $orderId: ❌ Error: $e');
          }
        }

        debugPrint('[OrderMigration] Órdenes completadas migradas: $completedMigrated');
      } else {
        debugPrint('[OrderMigration] No hay órdenes completadas en Hive');
      }

      // 3. Limpieza de Hive (opcional)
      if (deleteHiveDataAfter && successCount > 0) {
        debugPrint('[OrderMigration] ⚠️ ADVERTENCIA: Limpieza de Hive está DESHABILITADA para órdenes por seguridad');
        debugPrint('[OrderMigration] Para eliminar datos de Hive manualmente, usar clearCompletedOrdersCache() y limpiar pendingOrders');
      }

      final duration = DateTime.now().difference(startTime);

      debugPrint('[OrderMigration] ========================================');
      debugPrint('[OrderMigration] MIGRACIÓN COMPLETADA');
      debugPrint('[OrderMigration] Total órdenes: $totalOrders');
      debugPrint('[OrderMigration] Ya migradas: $alreadyMigratedCount');
      debugPrint('[OrderMigration] Migradas ahora: $successCount');
      debugPrint('[OrderMigration] Fallos: $failCount');
      debugPrint('[OrderMigration] Omitidas: $skippedCount');
      debugPrint('[OrderMigration] Duración: ${duration.inSeconds}s');
      debugPrint('[OrderMigration] ========================================');

      return MigrationResult(
        success: failCount == 0,
        totalProducts: totalOrders,
        alreadyMigratedCount: alreadyMigratedCount,
        successCount: successCount,
        failCount: failCount,
        skippedCount: skippedCount,
        errors: errors,
        duration: duration,
      );
    } catch (e) {
      debugPrint('[OrderMigration] ❌ ERROR FATAL: $e');
      return MigrationResult(
        success: false,
        totalProducts: totalOrders,
        alreadyMigratedCount: alreadyMigratedCount,
        successCount: successCount,
        failCount: failCount,
        skippedCount: skippedCount,
        errors: [...errors, 'Fatal: $e'],
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Migra labels de Hive a ObjectBox
  ///
  /// **Proceso:**
  /// 1. Leer todos los labels de la cola de impresión de Hive (LabelQueueBox)
  /// 2. Para cada label:
  ///    a. Convertir usando LabelConverterService
  ///    b. Guardar en ObjectBox
  /// 3. Verificar integridad
  /// 4. Opcionalmente limpiar datos de Hive
  ///
  /// **Parámetros:**
  /// - `deleteHiveDataAfter`: Si true, elimina datos de Hive después de migrar exitosamente
  ///
  /// **Returns:** MigrationResult con estadísticas
  Future<MigrationResult> migrateLabelsHiveToObjectBox({
    bool deleteHiveDataAfter = false,
  }) async {
    final startTime = DateTime.now();
    int totalLabels = 0;
    int successCount = 0;
    int failCount = 0;
    int skippedCount = 0;
    int alreadyMigratedCount = 0;
    final List<String> errors = [];

    try {
      debugPrint('[LabelMigration] ========================================');
      debugPrint('[LabelMigration] INICIANDO MIGRACIÓN Labels Hive → ObjectBox');
      debugPrint('[LabelMigration] ========================================');

      final store = _dbService.store;
      if (store == null) {
        throw Exception('ObjectBox store not initialized');
      }

      final box = store.box<LabelPrintItemCompact>();

      // MIGRAR COLA DE LABELS
      debugPrint('[LabelMigration] Migrando cola de impresión...');

      if (_labelQueueBox != null && _labelQueueBox!.isNotEmpty) {
        final labels = _labelQueueBox!.values.toList();
        totalLabels = labels.length;
        debugPrint('[LabelMigration] Total labels en cola Hive: $totalLabels');

        for (final label in labels) {
          try {
            // Verificar si ya existe en ObjectBox por itemId
            final itemId = label.id ?? '';
            if (itemId.isEmpty) {
              skippedCount++;
              debugPrint('[LabelMigration] Label sin ID, skip');
              continue;
            }

            final query = box.query(LabelPrintItemCompact_.itemId.equals(itemId)).build();
            final existing = query.findFirst();
            query.close();

            if (existing != null) {
              alreadyMigratedCount++;
              debugPrint('[LabelMigration] Label $itemId: Ya existe en ObjectBox');
              continue;
            }

            // Convertir y guardar
            final compact = _labelConverter.labelToCompact(label);
            box.put(compact);

            successCount++;
            debugPrint('[LabelMigration] Label $itemId: ✅ Migrado (${label.displayName}, qty: ${label.quantity})');
          } catch (e) {
            failCount++;
            final labelId = label.id ?? 'unknown';
            errors.add('Label $labelId: $e');
            debugPrint('[LabelMigration] Label $labelId: ❌ Error: $e');
          }
        }

        debugPrint('[LabelMigration] Labels migrados: $successCount');
      } else {
        debugPrint('[LabelMigration] No hay labels en cola de Hive');
      }

      // Limpieza de Hive (opcional)
      if (deleteHiveDataAfter && successCount > 0) {
        debugPrint('[LabelMigration] ⚠️ ADVERTENCIA: Limpieza de Hive está DESHABILITADA para labels por seguridad');
        debugPrint('[LabelMigration] Para eliminar datos de Hive manualmente, usar clearLabelQueue()');
      }

      final duration = DateTime.now().difference(startTime);

      debugPrint('[LabelMigration] ========================================');
      debugPrint('[LabelMigration] MIGRACIÓN COMPLETADA');
      debugPrint('[LabelMigration] Total labels: $totalLabels');
      debugPrint('[LabelMigration] Ya migrados: $alreadyMigratedCount');
      debugPrint('[LabelMigration] Migrados ahora: $successCount');
      debugPrint('[LabelMigration] Fallos: $failCount');
      debugPrint('[LabelMigration] Omitidos: $skippedCount');
      debugPrint('[LabelMigration] Duración: ${duration.inSeconds}s');
      debugPrint('[LabelMigration] ========================================');

      return MigrationResult(
        success: failCount == 0,
        totalProducts: totalLabels,
        alreadyMigratedCount: alreadyMigratedCount,
        successCount: successCount,
        failCount: failCount,
        skippedCount: skippedCount,
        errors: errors,
        duration: duration,
      );
    } catch (e) {
      debugPrint('[LabelMigration] ❌ ERROR FATAL: $e');
      return MigrationResult(
        success: false,
        totalProducts: totalLabels,
        alreadyMigratedCount: alreadyMigratedCount,
        successCount: successCount,
        failCount: failCount,
        skippedCount: skippedCount,
        errors: [...errors, 'Fatal: $e'],
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Verifica la integridad de la migración
  ///
  /// Compara productos en Hive vs ObjectBox para detectar discrepancias
  ///
  /// **Returns:** VerificationResult con estadísticas
  Future<VerificationResult> verifyMigration() async {
    int totalChecked = 0;
    int missingAttributes = 0;
    final List<String> issues = [];

    try {
      final store = _dbService.store;
      if (store == null) throw Exception('ObjectBox not initialized');

      final box = store.box<ProductOptimized>();
      final allProducts = box.getAll();

      debugPrint('[Verification] Verificando ${allProducts.length} productos...');

      for (final product in allProducts) {
        totalChecked++;
        final productId = product.id.toString();

        // Verificar si tiene atributos en Hive
        bool hasHiveAttrs = false;
        if (_settingsBox != null) {
          final attributesJson =
              _settingsBox!.get('product_faf_$productId') as String?;
          hasHiveAttrs = attributesJson != null && attributesJson.isNotEmpty;
        }

        bool hasObjectBoxAttrs = product.attributesCompressed != null &&
            product.attributesCompressed!.isNotEmpty;

        if (hasHiveAttrs && !hasObjectBoxAttrs) {
          missingAttributes++;
          issues.add(
              'Producto $productId: Tiene attrs en Hive pero NO en ObjectBox');
        }
      }

      debugPrint('[Verification] ========================================');
      debugPrint('[Verification] VERIFICACIÓN COMPLETADA');
      debugPrint('[Verification] Total verificados: $totalChecked');
      debugPrint('[Verification] Atributos faltantes: $missingAttributes');
      if (missingAttributes == 0) {
        debugPrint('[Verification] ✅ Todos los atributos migrados correctamente');
      } else {
        debugPrint('[Verification] ⚠️ Hay $missingAttributes productos con atributos faltantes');
      }
      debugPrint('[Verification] ========================================');

      return VerificationResult(
        success: missingAttributes == 0,
        totalChecked: totalChecked,
        missingAttributes: missingAttributes,
        issues: issues,
      );
    } catch (e) {
      debugPrint('[Verification] ❌ Error: $e');
      return VerificationResult(
        success: false,
        totalChecked: totalChecked,
        missingAttributes: missingAttributes,
        issues: [...issues, 'Error: $e'],
      );
    }
  }

  /// Obtiene estadísticas de atributos en Hive
  Map<String, dynamic> getHiveAttributesStats() {
    int totalAttributesInHive = 0;
    int totalProductsWithAttributes = 0;

    if (_settingsBox != null) {
      final attributeKeys = _settingsBox!.keys
          .where((key) => key.toString().startsWith('product_faf_'))
          .toList();

      totalProductsWithAttributes = attributeKeys.length;

      for (final key in attributeKeys) {
        try {
          final attributesJson = _settingsBox!.get(key) as String?;
          if (attributesJson != null && attributesJson.isNotEmpty) {
            final attrs = jsonDecode(attributesJson) as List;
            totalAttributesInHive += attrs.length;
          }
        } catch (e) {
          // Skip
        }
      }
    }

    return {
      'total_products_with_attributes': totalProductsWithAttributes,
      'total_attributes': totalAttributesInHive,
      'average_attributes_per_product': totalProductsWithAttributes > 0
          ? (totalAttributesInHive / totalProductsWithAttributes).toStringAsFixed(2)
          : '0',
    };
  }

  /// Obtiene estadísticas de atributos en ObjectBox
  Map<String, dynamic> getObjectBoxAttributesStats() {
    int totalProductsWithAttributes = 0;
    int totalBytes = 0;

    final store = _dbService.store;
    if (store != null) {
      final box = store.box<ProductOptimized>();
      final allProducts = box.getAll();

      for (final product in allProducts) {
        if (product.attributesCompressed != null &&
            product.attributesCompressed!.isNotEmpty) {
          totalProductsWithAttributes++;
          totalBytes += product.attributesCompressed!.length;
        }
      }
    }

    return {
      'total_products_with_attributes': totalProductsWithAttributes,
      'total_bytes': totalBytes,
      'average_bytes_per_product': totalProductsWithAttributes > 0
          ? (totalBytes / totalProductsWithAttributes).toStringAsFixed(2)
          : '0',
    };
  }
}

/// Resultado de la migración
class MigrationResult {
  final bool success;
  final int totalProducts;
  final int alreadyMigratedCount;
  final int successCount;
  final int failCount;
  final int skippedCount;
  final List<String> errors;
  final Duration duration;

  MigrationResult({
    required this.success,
    required this.totalProducts,
    required this.alreadyMigratedCount,
    required this.successCount,
    required this.failCount,
    required this.skippedCount,
    required this.errors,
    required this.duration,
  });

  @override
  String toString() {
    return '''
MigrationResult:
  Success: $success
  Total: $totalProducts
  Ya migrados: $alreadyMigratedCount
  Migrados ahora: $successCount
  Fallos: $failCount
  Omitidos: $skippedCount
  Duración: ${duration.inSeconds}s
  Errores: ${errors.isEmpty ? "Ninguno" : errors.join(", ")}
''';
  }
}

/// Resultado de la verificación
class VerificationResult {
  final bool success;
  final int totalChecked;
  final int missingAttributes;
  final List<String> issues;

  VerificationResult({
    required this.success,
    required this.totalChecked,
    required this.missingAttributes,
    required this.issues,
  });

  @override
  String toString() {
    return '''
VerificationResult:
  Success: $success
  Total verificados: $totalChecked
  Atributos faltantes: $missingAttributes
  Issues: ${issues.isEmpty ? "Ninguno" : issues.join(", ")}
''';
  }
}
