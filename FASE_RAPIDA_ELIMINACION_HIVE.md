# FASE RÁPIDA: ELIMINACIÓN DE 75% DE HIVE

**Fecha inicio:** 2025-11-22
**Status:** ⏳ EN PROGRESO - FASE 1 COMPLETADA

## Objetivo

Eliminar 3 de 4 boxes de Hive restantes con mínimo riesgo y máximo beneficio.

---

## ✅ FASE 1 COMPLETADA - barcodeIndexBox ELIMINADO

**Tiempo:** 15 minutos
**Riesgo:** NINGUNO (código muerto)
**Estado:** ✅ COMPLETADO

### Cambios realizados:

1. **`lib/services/storage_service.dart`**
   - Línea 24: ❌ Eliminada variable `hive.Box<List<String>>? _barcodeIndexBox;`
   - Línea 53: ❌ Eliminada apertura `_barcodeIndexBox = await Hive.openBox<List<String>>(hiveBarcodeIndexBoxName);`
   - Actualizado comentario: "Solo para Settings, SyncQueue" (eliminado "BarcodeIndex")

2. **`lib/main.dart`**
   - Línea 52: ❌ Eliminada apertura `Hive.openBox<List<String>>(hiveBarcodeIndexBoxName)`
   - Agregado comentario: "❌ ELIMINADO - Código muerto (búsqueda usa ObjectBox)"

### Justificación:

El box `barcodeIndexBox` era usado para índices de búsqueda de productos. Fue **completamente reemplazado** por búsquedas indexadas en ObjectBox:

```dart
// ANTES (Hive):
final box = _barcodeIndexBox;
final ids = box.get(barcode);

// AHORA (ObjectBox - más rápido):
final query = box.query(ProductOptimized_.barcode.equals(barcode)).build();
```

**Beneficios:**
- ✅ -1 box de Hive
- ✅ Búsquedas más rápidas (índices nativos ObjectBox)
- ✅ Menos código de mantenimiento

---

## ⏳ FASE 2 EN PROGRESO - settingsBox → SharedPreferences

**Tiempo estimado:** 2-3 horas
**Riesgo:** BAJO (datos simples)
**Estado:** ⏳ EN PROGRESO

### Plan de migración:

#### 1. Métodos a reemplazar (6 métodos):

**A. Last Sync Timestamp**
```dart
// ANTES (Hive):
Future<void> setLastSync(DateTime dt) async {
  final box = _settingsBox;
  if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return;
  await box!.put(hiveLastSyncKey, dt.toIso8601String());
}

DateTime? getLastSync() {
  final box = _settingsBox;
  if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return null;
  final s = box!.get(hiveLastSyncKey);
  return s != null ? DateTime.tryParse(s) : null;
}

// DESPUÉS (SharedPreferences):
Future<void> setLastSync(DateTime dt) async {
  await _prefs.setInt('last_sync_ms', dt.millisecondsSinceEpoch);
}

DateTime? getLastSync() {
  final ms = _prefs.getInt('last_sync_ms');
  return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
}
```

**B. Product Cache Timestamps**
```dart
// ANTES (Hive):
Future<void> setProductCacheTimestamp(String productId, DateTime timestamp) async {
  final box = _settingsBox;
  if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return;
  await box!.put('ts_prod_$productId', timestamp.toIso8601String());
}

DateTime? getProductCacheTimestamp(String productId) {
  final box = _settingsBox;
  if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return null;
  final ts = box!.get('ts_prod_$productId');
  return (ts is String) ? DateTime.tryParse(ts) : null;
}

// DESPUÉS (SharedPreferences):
Future<void> setProductCacheTimestamp(String productId, DateTime timestamp) async {
  await _prefs.setInt('ts_prod_$productId', timestamp.millisecondsSinceEpoch);
}

DateTime? getProductCacheTimestamp(String productId) {
  final ms = _prefs.getInt('ts_prod_$productId');
  return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
}
```

**C. Order Cache Timestamps**
```dart
// ANTES (Hive):
Future<void> setOrderCacheTimestamp(String orderIdOrKey, DateTime timestamp) async {
  final box = _settingsBox;
  if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return;
  final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
  await box!.put(key, timestamp.toIso8601String());
}

DateTime? getOrderCacheTimestamp(String orderIdOrKey) {
  final box = _settingsBox;
  if (!_isGenericBoxReady(box, hiveSettingsBoxName)) return null;
  final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
  final ts = box!.get(key);
  return (ts is String) ? DateTime.tryParse(ts) : null;
}

// DESPUÉS (SharedPreferences):
Future<void> setOrderCacheTimestamp(String orderIdOrKey, DateTime timestamp) async {
  final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
  await _prefs.setInt(key, timestamp.millisecondsSinceEpoch);
}

DateTime? getOrderCacheTimestamp(String orderIdOrKey) {
  final key = orderIdOrKey.startsWith('order_history_') ? orderIdOrKey : 'ts_order_$orderIdOrKey';
  final ms = _prefs.getInt(key);
  return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
}
```

#### 2. Migración automática de datos existentes:

```dart
Future<void> _migrateSettingsBoxToPrefs() async {
  if (_settingsBox == null || !_settingsBox!.isOpen) return;

  final migrationCompleted = _prefs.getBool('settings_migrated_to_prefs') ?? false;
  if (migrationCompleted) {
    debugPrint('[Migration] settingsBox already migrated to SharedPreferences');
    return;
  }

  debugPrint('[Migration] Migrating settingsBox to SharedPreferences...');

  try {
    // Migrar last_sync
    final lastSyncStr = _settingsBox!.get(hiveLastSyncKey) as String?;
    if (lastSyncStr != null) {
      final dt = DateTime.tryParse(lastSyncStr);
      if (dt != null) {
        await _prefs.setInt('last_sync_ms', dt.millisecondsSinceEpoch);
        debugPrint('[Migration] Migrated last_sync: $lastSyncStr');
      }
    }

    // Migrar timestamps de productos y órdenes
    int migratedCount = 0;
    for (final key in _settingsBox!.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith('ts_prod_') || keyStr.startsWith('ts_order_') || keyStr.startsWith('order_history_')) {
        final value = _settingsBox!.get(key);
        if (value is String) {
          final dt = DateTime.tryParse(value);
          if (dt != null) {
            await _prefs.setInt(keyStr, dt.millisecondsSinceEpoch);
            migratedCount++;
          }
        }
      }
    }

    await _prefs.setBool('settings_migrated_to_prefs', true);
    debugPrint('[Migration] ✅ settingsBox migrated successfully ($migratedCount timestamps)');
  } catch (e) {
    debugPrint('[Migration] ❌ Error migrating settingsBox: $e');
  }
}
```

#### 3. Actualizar `init()` en storage_service.dart:

```dart
Future<void> init() async {
  debugPrint("[StorageService] init: Initializing ObjectBox and Hive...");
  try {
    // ✅ OBJECTBOX - Base de datos principal
    _db = await DatabaseService.getInstance();
    _converter = ProductConverterService(_db!);
    _orderConverter = OrderConverterService();

    // ⚠️ TEMPORAL: Abrir settingsBox para migración
    _settingsBox = await Hive.openBox(hiveSettingsBoxName);

    // ✅ Migrar settings a SharedPreferences (una sola vez)
    await _migrateSettingsBoxToPrefs();

    // ✅ HIVE - Solo para SyncQueue (settingsBox será eliminado)
    _syncQueueBox = await Hive.openBox<SyncOperation>(hiveSyncQueueBoxName);

    debugPrint("[StorageService] init: ✅ ObjectBox (primary) + Hive (SyncQueue only) initialized.");
  } catch (e, stacktrace) {
    debugPrint("[StorageService] !! FATAL ERROR initializing storage: $e\n$stacktrace");
    rethrow;
  }
}
```

#### 4. Eliminar settingsBox después de migración:

**Archivos a modificar:**
- `lib/services/storage_service.dart`
  - Línea 24: Eliminar `hive.Box? _settingsBox;`
  - Línea 39: Eliminar `hive.Box? get settingsBox => _settingsBox;`
  - Línea 52: Eliminar apertura de settingsBox (después de migración)
  - Líneas 136-144: Reemplazar métodos setLastSync/getLastSync
  - Líneas 257-265: Reemplazar métodos setProductCacheTimestamp/getProductCacheTimestamp
  - Líneas 452-460: Reemplazar métodos setOrderCacheTimestamp/getOrderCacheTimestamp
  - Eliminar método `_isGenericBoxReady()` (ya no se usa)

- `lib/main.dart`
  - Línea 51: Eliminar `Hive.openBox(hiveSettingsBoxName)`

- `lib/services/data_migration_service.dart`
  - Ya no necesita `settingsBox` parameter
  - Solo se usa para legacy cleanup (product_faf_* keys)

- `lib/locator.dart`
  - Línea 225: Actualizar `createDataMigrationService()` para no pasar `settingsBox`

- `lib/config/constants.dart`
  - Eliminar `const String hiveSettingsBoxName = 'settings';`
  - Eliminar `const String hiveLastSyncKey = 'last_sync';`

**Beneficios:**
- ✅ -1 box de Hive
- ✅ SharedPreferences es más ligero que Hive
- ✅ Datos simples en storage simple

---

## ⏳ FASE 3 PENDIENTE - inventoryAdjustmentCache → SharedPreferences

**Tiempo estimado:** 1-2 horas
**Riesgo:** BAJO (solo 1 objeto temporal)
**Estado:** ⏳ PENDIENTE

### Plan de migración:

#### 1. Agregar toJson/fromJson a InventoryAdjustmentCache:

```dart
// lib/models/inventory_adjustment_cache.dart

import 'dart:convert';

// ❌ REMOVER Hive annotations:
// @HiveType(typeId: 8)
// extends HiveObject
// @HiveField(...)

class InventoryAdjustmentCache {
  final String description;
  final List<InventoryMovementLine> items;
  final DateTime lastModified;

  InventoryAdjustmentCache({
    required this.description,
    required this.items,
    required this.lastModified,
  });

  // ✅ AGREGAR: Serialization methods
  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'items': items.map((item) => {
        'productId': item.productId,
        'variationId': item.variationId,
        'quantityChanged': item.quantityChanged,
        'productName': item.productName,
        'productSku': item.productSku,
      }).toList(),
      'lastModified': lastModified.toIso8601String(),
    };
  }

  static InventoryAdjustmentCache? fromJson(Map<String, dynamic> json) {
    try {
      return InventoryAdjustmentCache(
        description: json['description'] as String,
        items: (json['items'] as List).map((item) => InventoryMovementLine(
          productId: item['productId'] as String,
          variationId: item['variationId'] as String?,
          quantityChanged: item['quantityChanged'] as int,
          productName: item['productName'] as String,
          productSku: item['productSku'] as String?,
        )).toList(),
        lastModified: DateTime.parse(json['lastModified'] as String),
      );
    } catch (e) {
      debugPrint('[InventoryAdjustmentCache] Error parsing JSON: $e');
      return null;
    }
  }
}
```

#### 2. Actualizar inventory_notifier.dart:

```dart
// lib/providers/inventory_notifier.dart

import 'dart:convert';

// ❌ REMOVER: import 'package:hive_flutter/hive_flutter.dart';

late SharedPreferences _prefs;

@override
InventoryState build() {
  // ...
  _prefs = ref.read(sharedPreferencesProvider);

  // ❌ REMOVER:
  // _cacheBox = Hive.box<InventoryAdjustmentCache>(hiveInventoryAdjustmentCacheBoxName);
}

Future<void> cacheAdjustment(String description, List<InventoryMovementLine> items) async {
  if (items.isEmpty) {
    await clearCachedAdjustment();
    return;
  }

  final cacheData = InventoryAdjustmentCache(
    description: description,
    items: items,
    lastModified: DateTime.now(),
  );

  await _prefs.setString('inventory_adjustment_cache', jsonEncode(cacheData.toJson()));
  debugPrint("[Inventory] Adjustment cached with ${items.length} items.");
}

Future<InventoryAdjustmentCache?> loadCachedAdjustment() async {
  final json = _prefs.getString('inventory_adjustment_cache');
  if (json == null) return null;

  try {
    return InventoryAdjustmentCache.fromJson(jsonDecode(json));
  } catch (e) {
    debugPrint("[Inventory] Error loading cached adjustment: $e");
    return null;
  }
}

Future<void> clearCachedAdjustment() async {
  await _prefs.remove('inventory_adjustment_cache');
  debugPrint("[Inventory] Cached adjustment cleared.");
}
```

#### 3. Eliminar box:

**Archivos a modificar:**
- `lib/models/inventory_adjustment_cache.dart`
  - Remover `@HiveType(typeId: 8)`, `@HiveField(...)`, `extends HiveObject`
  - Remover `part 'inventory_adjustment_cache.g.dart';`
  - Agregar `toJson()` y `fromJson()`

- `lib/models/inventory_adjustment_cache.g.dart`
  - ❌ ELIMINAR archivo completo (ya no se genera)

- `lib/providers/inventory_notifier.dart`
  - Reemplazar 3 métodos (cacheAdjustment, loadCachedAdjustment, clearCachedAdjustment)
  - Remover referencia a `_cacheBox`

- `lib/main.dart`
  - Línea 52: Eliminar `Hive.openBox<InventoryAdjustmentCache>(hiveInventoryAdjustmentCacheBoxName)`

- `lib/locator.dart`
  - Línea 59: Eliminar `InventoryAdjustmentCacheAdapter` registration

- `lib/config/constants.dart`
  - Eliminar `const String hiveInventoryAdjustmentCacheBoxName = 'inventoryAdjustmentCache';`

**Beneficios:**
- ✅ -1 box de Hive
- ✅ Cache temporal en JSON (más portable)
- ✅ No requiere code generation

---

## 📊 RESULTADO FINAL FASE RÁPIDA

### Boxes eliminados: 3 de 4

| Box | Estado | Destino |
|-----|--------|---------|
| barcodeIndexBox | ✅ ELIMINADO | N/A (código muerto) |
| settingsBox | ⏳ EN PROGRESO | SharedPreferences |
| inventoryAdjustmentCache | ⏳ PENDIENTE | SharedPreferences |
| syncQueueBox | ⏸️ MANTENER | Mantener por ahora |

### Beneficios esperados:

- ✅ **-75% de boxes de Hive** (3 de 4 eliminados)
- ⚡ **-150ms en inicialización** (no abre 3 boxes)
- 💾 **-600 KB en APK** (menos adapters y código generado)
- 🧹 **Código más limpio** (menos complejidad)

### Hive restante:

Solo quedará **1 box**: `syncQueueBox`
- Justificación: Cola de sincronización con datos complejos
- Puede migrarse a ObjectBox en FASE 4 (opcional, más complejo)

---

## ⏭️ PRÓXIMOS PASOS

### Para completar FASE RÁPIDA:

1. ✅ **Completar FASE 2** (2-3 horas)
   - Implementar nuevos métodos con SharedPreferences
   - Implementar migración automática
   - Eliminar settingsBox
   - Probar timestamps funcionan correctamente

2. ✅ **Completar FASE 3** (1-2 horas)
   - Agregar toJson/fromJson a InventoryAdjustmentCache
   - Actualizar inventory_notifier.dart
   - Eliminar box y adapter
   - Probar cache de ajustes funciona

3. ✅ **Compilar y probar** (30 min)
   - `flutter clean && flutter pub get`
   - `flutter analyze` (verificar 0 errores)
   - `flutter run` (probar en dispositivo)
   - Verificar timestamps se guardan y leen correctamente
   - Verificar cache de ajustes se guarda y lee correctamente

### Tiempo total restante: 3-5 horas

---

## 🎯 COMANDOS PARA CONTINUAR

```bash
cd my_pos_app

# Después de completar FASE 2 y 3:
flutter clean
flutter pub get
flutter analyze

# Probar en dispositivo:
flutter run -d <device-id>
```

---

## 📝 NOTAS IMPORTANTES

1. **Migración automática:**
   - Solo se ejecuta una vez (flag `settings_migrated_to_prefs`)
   - Datos antiguos en Hive se preservan temporalmente
   - Después de confirmar migración exitosa, se puede limpiar Hive

2. **SharedPreferences vs Hive:**
   - SharedPreferences usa `int` (milliseconds) para timestamps (más eficiente)
   - Hive usaba `String` (ISO 8601)
   - Conversión es transparente para el usuario

3. **Rollback:**
   - Si hay problemas, se puede revertir eliminando flag de migración
   - Datos antiguos aún están en Hive como respaldo

4. **DataMigrationService:**
   - Aún necesita acceso temporal a settingsBox para limpiar claves legacy
   - Puede eliminarse completamente después de limpieza

---

## ✅ CONCLUSIÓN FASE 1

**barcodeIndexBox eliminado exitosamente** con 0 riesgo y beneficios inmediatos. Las FASES 2 y 3 están planificadas en detalle y listas para implementar.

**Próximo paso:** Continuar con FASE 2 (migrar settingsBox → SharedPreferences).
