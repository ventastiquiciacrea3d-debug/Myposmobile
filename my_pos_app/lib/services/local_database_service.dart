// lib/services/local_database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/customer_model.dart';

/// Servicio para base de datos local SQLite
class LocalDatabaseService {
  static const String _databaseName = 'mypos_local.db';
  static const int _databaseVersion = 1;

  // Nombre de tablas
  static const String _customersTable = 'customers';

  Database? _database;

  /// Obtener instancia de base de datos
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Inicializar base de datos
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Crear tablas
  Future<void> _onCreate(Database db, int version) async {
    // Tabla de clientes
    await db.execute('''
      CREATE TABLE $_customersTable (
        id INTEGER PRIMARY KEY,
        local_id TEXT UNIQUE,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT,
        company TEXT,
        address TEXT,
        city TEXT,
        state TEXT,
        postcode TEXT,
        country TEXT,
        source TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        is_synced_with_woo INTEGER DEFAULT 0,
        metadata TEXT
      )
    ''');

    // Índices para mejorar búsquedas
    await db.execute(
      'CREATE INDEX idx_customers_email ON $_customersTable(email)',
    );
    await db.execute(
      'CREATE INDEX idx_customers_name ON $_customersTable(first_name, last_name)',
    );
    await db.execute(
      'CREATE INDEX idx_customers_phone ON $_customersTable(phone)',
    );
  }

  /// Actualizar base de datos
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Manejar migraciones futuras
    if (oldVersion < newVersion) {
      // Ejemplo: agregar nuevas columnas
    }
  }

  // ==================== CLIENTES ====================

  /// Guardar o actualizar cliente
  Future<int> saveCustomer(CustomerModel customer) async {
    final db = await database;

    final map = customer.toSQLiteMap();

    if (customer.id != null) {
      // Actualizar existente
      await db.update(
        _customersTable,
        map,
        where: 'id = ?',
        whereArgs: [customer.id],
      );
      return customer.id!;
    } else if (customer.localId != null) {
      // Actualizar por localId
      final existing = await db.query(
        _customersTable,
        where: 'local_id = ?',
        whereArgs: [customer.localId],
      );

      if (existing.isNotEmpty) {
        await db.update(
          _customersTable,
          map,
          where: 'local_id = ?',
          whereArgs: [customer.localId],
        );
        return existing.first['id'] as int;
      }
    }

    // Insertar nuevo
    return await db.insert(_customersTable, map);
  }

  /// Obtener cliente por ID
  Future<CustomerModel?> getCustomerById(int id) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      _customersTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    return CustomerModel.fromSQLite(maps.first);
  }

  /// Obtener cliente por email
  Future<CustomerModel?> getCustomerByEmail(String email) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      _customersTable,
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return CustomerModel.fromSQLite(maps.first);
  }

  /// Obtener todos los clientes
  Future<List<CustomerModel>> getAllCustomers({
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      _customersTable,
      orderBy: orderBy ?? 'updated_at DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((map) => CustomerModel.fromSQLite(map)).toList();
  }

  /// Buscar clientes
  Future<List<CustomerModel>> searchCustomers(String query) async {
    final db = await database;

    final String searchQuery = '%${query.toLowerCase()}%';

    final List<Map<String, dynamic>> maps = await db.query(
      _customersTable,
      where: '''
        LOWER(first_name) LIKE ? OR
        LOWER(last_name) LIKE ? OR
        LOWER(email) LIKE ? OR
        LOWER(phone) LIKE ? OR
        LOWER(company) LIKE ?
      ''',
      whereArgs: [searchQuery, searchQuery, searchQuery, searchQuery, searchQuery],
      orderBy: 'updated_at DESC',
      limit: 50,
    );

    return maps.map((map) => CustomerModel.fromSQLite(map)).toList();
  }

  /// Obtener clientes recientes
  Future<List<CustomerModel>> getRecentCustomers({int limit = 10}) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      _customersTable,
      orderBy: 'updated_at DESC',
      limit: limit,
    );

    return maps.map((map) => CustomerModel.fromSQLite(map)).toList();
  }

  /// Obtener clientes no sincronizados
  Future<List<CustomerModel>> getUnsyncedCustomers() async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      _customersTable,
      where: 'is_synced_with_woo = ? AND email IS NOT NULL AND email != ""',
      whereArgs: [0],
    );

    return maps.map((map) => CustomerModel.fromSQLite(map)).toList();
  }

  /// Eliminar cliente
  Future<int> deleteCustomer(int id) async {
    final db = await database;

    return await db.delete(
      _customersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Limpiar todos los clientes
  Future<int> clearAllCustomers() async {
    final db = await database;
    return await db.delete(_customersTable);
  }

  /// Obtener conteo de clientes
  Future<int> getCustomerCount() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_customersTable',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Sincronizar múltiples clientes desde WooCommerce
  Future<void> syncCustomersFromWooCommerce(
    List<CustomerModel> customers,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      for (final customer in customers) {
        final map = customer.toSQLiteMap();

        await txn.insert(
          _customersTable,
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Marcar cliente como sincronizado
  Future<void> markCustomerAsSynced(int id, int wooCommerceId) async {
    final db = await database;

    await db.update(
      _customersTable,
      {
        'id': wooCommerceId,
        'is_synced_with_woo': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cerrar base de datos
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Eliminar base de datos (para testing o reset)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    await databaseFactory.deleteDatabase(path);
    _database = null;
  }
}
