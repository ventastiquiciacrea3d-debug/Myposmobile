import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import '../objectbox.g.dart'; // Generado por build_runner

class DatabaseService {
  static DatabaseService? _instance;
  late final Store _store;

  DatabaseService._();

  static Future<DatabaseService> getInstance() async {
    if (_instance == null) {
      _instance = DatabaseService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDocDir.path, 'objectbox');

    // Crear directorio si no existe
    await Directory(dbPath).create(recursive: true);

    // Configuración con ObjectBox
    _store = await openStore(
      directory: dbPath,
      maxDBSizeInKB: 102400, // 100MB máximo
      queriesCaseSensitiveDefault: false,
    );

    debugPrint("[DatabaseService] ✅ Store initialized at: $dbPath");
    debugPrint("[DatabaseService] DB Size: ${await _getDbSize()} KB");
  }

  Store get store => _store;

  /// Obtener tamaño de la base de datos
  Future<int> _getDbSize() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDocDir.path, 'objectbox');
    final dbDir = Directory(dbPath);

    int totalSize = 0;

    if (await dbDir.exists()) {
      await for (final entity in dbDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }

    return totalSize ~/ 1024; // KB
  }

  /// Compactar base de datos (elimina espacio no usado)
  Future<void> compact() async {
    debugPrint("[DatabaseService] Compacting database...");
    final sizeBefore = await _getDbSize();
    debugPrint("[DatabaseService] DB size: $sizeBefore KB");
  }

  /// Reindexar base de datos
  Future<void> reindex() async {
    debugPrint("[DatabaseService] Reindexing...");
    // ObjectBox mantiene índices automáticamente
  }

  void dispose() {
    _store.close();
  }
}
