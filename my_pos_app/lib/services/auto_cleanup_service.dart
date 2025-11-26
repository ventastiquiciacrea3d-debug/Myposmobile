import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_compact.dart';
import 'database_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../objectbox.g.dart' hide Order;

/// Servicio de limpieza automática inteligente
class AutoCleanupService {
  final DatabaseService _db;

  static const String _lastCleanupKey = 'last_cleanup_timestamp';

  AutoCleanupService(this._db);

  /// Ejecutar limpieza diaria
  Future<void> performDailyCleanup() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCleanup = prefs.getInt(_lastCleanupKey);

    final now = DateTime.now();
    final lastCleanupDate = lastCleanup != null
        ? DateTime.fromMillisecondsSinceEpoch(lastCleanup * 1000)
        : null;

    // Solo ejecutar si han pasado más de 24 horas
    if (lastCleanupDate != null &&
        now.difference(lastCleanupDate).inHours < 24) {
      debugPrint("[AutoCleanup] Last cleanup was ${now.difference(lastCleanupDate).inHours}h ago. Skipping.");
      return;
    }

    debugPrint("[AutoCleanup] 🧹 Starting daily cleanup...");

    final stopwatch = Stopwatch()..start();

    // 1. Eliminar productos sin stock > 60 días
    await _removeOutOfStockProducts(days: 60);

    // 2. Limpiar caché de imágenes > 30 días
    await _cleanImageCache(days: 30);

    stopwatch.stop();

    // Guardar timestamp de última limpieza
    await prefs.setInt(_lastCleanupKey, now.millisecondsSinceEpoch ~/ 1000);

    debugPrint("[AutoCleanup] ✅ Cleanup completed in ${stopwatch.elapsedMilliseconds}ms");
  }

  /// Eliminar productos sin stock antiguos
  Future<int> _removeOutOfStockProducts({required int days}) async {
    final box = _db.store.box<ProductCompact>();

    final cutoffDate = DateTime.now().subtract(Duration(days: days));

    // Query: stock = 0 AND lastUpdated < cutoffDate
    final query = box.query(
      ProductCompact_.stockQuantity.equals(0)
        .and(ProductCompact_.lastUpdated.lessThan(cutoffDate.millisecondsSinceEpoch))
    ).build();

    final toRemove = query.find();
    final count = toRemove.length;

    query.close();

    if (count > 0) {
      // Eliminar en batch
      final idsToRemove = toRemove.map((p) => p.localId).toList();
      box.removeMany(idsToRemove);

      debugPrint("[AutoCleanup] 🗑️ Removed $count out-of-stock products older than $days days");
    }

    return count;
  }

  /// Limpiar caché de imágenes antiguas
  Future<int> _cleanImageCache({required int days}) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDocDir.path}/image_cache');

    if (!await cacheDir.exists()) {
      return 0;
    }

    final cutoff = DateTime.now().subtract(Duration(days: days));
    int deletedCount = 0;

    await for (final entity in cacheDir.list()) {
      if (entity is File) {
        final stat = await entity.stat();

        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
          deletedCount++;
        }
      }
    }

    if (deletedCount > 0) {
      debugPrint("[AutoCleanup] 🖼️ Deleted $deletedCount cached images older than $days days");
    }

    return deletedCount;
  }

  /// Verificar límite de almacenamiento
  Future<void> checkStorageLimit() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${appDocDir.path}/objectbox');

    if (!await dbDir.exists()) {
      return;
    }

    int totalSize = 0;

    await for (final entity in dbDir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    final sizeMB = totalSize / (1024 * 1024);

    debugPrint("[AutoCleanup] DB Size: ${sizeMB.toStringAsFixed(2)} MB");

    // Si supera 50MB, limpiar agresivamente
    if (sizeMB > 50) {
      debugPrint("[AutoCleanup] ⚠️ DB size exceeds 50MB. Triggering emergency cleanup...");
      await _emergencyCleanup();
    }
  }

  /// Limpieza de emergencia (agresiva)
  Future<void> _emergencyCleanup() async {
    debugPrint("[AutoCleanup] 🚨 Emergency cleanup started");

    // 1. Productos sin stock > 30 días (más agresivo)
    await _removeOutOfStockProducts(days: 30);

    // 2. Limpiar TODAS las imágenes en cache
    await _cleanImageCache(days: 0);

    debugPrint("[AutoCleanup] ✅ Emergency cleanup completed");
  }

  /// Obtener estadísticas de almacenamiento
  Future<Map<String, dynamic>> getStorageStats() async {
    final box = _db.store.box<ProductCompact>();

    final appDocDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${appDocDir.path}/objectbox');

    int dbSize = 0;

    if (await dbDir.exists()) {
      await for (final entity in dbDir.list(recursive: true)) {
        if (entity is File) {
          dbSize += await entity.length();
        }
      }
    }

    return {
      'total_products': box.count(),
      'db_size_mb': (dbSize / (1024 * 1024)).toStringAsFixed(2),
      'db_size_bytes': dbSize,
    };
  }
}
