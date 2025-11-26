# Plan de Deprecación Gradual de Hive

**Fecha:** 2025-11-22
**Estado:** Planificación
**Objetivo:** Migrar completamente de Hive a ObjectBox

## Estado Actual (Después de Migración de Productos)

### ✅ Ya Migrado a ObjectBox (100%)
- **Products (ProductOptimized)**
  - ✅ Todos los campos incluyendo atributos comprimidos
  - ✅ Métodos usan ObjectBox como primary, Hive como fallback
  - ✅ Claves `product_faf_*` eliminadas del código (ya no se guardan)
  - ✅ Método de limpieza `cleanupLegacyAttributeKeys()` disponible

### ⚠️ Parcialmente Migrado (ObjectBox Primary + Hive Fallback)
- **Orders (OrderCompact)**
  - ✅ `savePendingOrder()` → ObjectBox + Hive fallback
  - ✅ `getPendingOrders()` → ObjectBox + Hive fallback
  - ✅ `removePendingOrder()` → ObjectBox + Hive fallback
  - ✅ `getPendingOrderById()` → ObjectBox + Hive fallback
  - ✅ `saveCompletedOrder()` → ObjectBox + Hive fallback
  - ✅ `getCompletedOrderById()` → ObjectBox + Hive fallback
  - ✅ `getCompletedOrders()` → ObjectBox + Hive fallback
  - ✅ `clearCompletedOrdersCache()` → ObjectBox + Hive fallback

- **Products (ProductOptimized)**
  - ✅ `getProductById()` → ObjectBox primary, Hive fallback
  - ✅ `searchLocalProductsByNameOrSku()` → ObjectBox primary
  - ✅ `getCachedProductByBarcode()` → ObjectBox primary
  - ✅ `getProductBySku()` → ObjectBox primary
  - ✅ `getLocalVariationsForProduct()` → ObjectBox primary

### ❌ Todavía 100% en Hive
- **Labels (LabelPrintItem)**: `_labelQueueBox`
- **SyncOperations (SyncOperation)**: `_syncQueueBox`
- **InventoryAdjustments (InventoryAdjustmentCache)**: No confirmado
- **Settings**: `_settingsBox` (timestamps, configuración)
- **BarcodeIndex**: `_barcodeIndexBox` (search index)

## Fase 1: Eliminar Fallbacks de Hive (LISTO PARA PRODUCCIÓN)

### Objetivos
- Eliminar fallbacks de Hive en métodos de Products y Orders
- ObjectBox como única fuente de verdad
- Mantener Hive solo para Settings, SyncQueue, Labels

### Cambios Requeridos

#### 1.1 Products - Eliminar Fallbacks
**Archivo:** `storage_service.dart`

**Métodos a modificar:**
```dart
// ANTES: ObjectBox + Hive fallback
Product? getProductById(String pid, {bool rehydrateAttributes = true}) {
  if (_db == null || _converter == null) {
    return _getProductByIdFromHive(pid, rehydrateAttributes: rehydrateAttributes);
  }
  // ... ObjectBox logic ...
  catch(e) {
    return _getProductByIdFromHive(pid, ...); // ❌ ELIMINAR fallback
  }
}

// DESPUÉS: Solo ObjectBox
Product? getProductById(String pid) {
  if (_db == null || _converter == null) {
    throw StateError('ObjectBox not initialized'); // ⚠️ Error explícito
  }
  // ... ObjectBox logic ...
  catch(e) {
    debugPrint("[StorageService.getProductById] Error: $e");
    return null; // ✅ Retornar null en vez de fallback
  }
}
```

**Métodos afectados:**
- `getProductById()` ✅
- `searchLocalProductsByNameOrSku()` ✅
- `getCachedProductByBarcode()` ✅
- `getProductBySku()` ✅
- `getLocalVariationsForProduct()` ✅

#### 1.2 Orders - Eliminar Fallbacks
**Métodos afectados:**
- `savePendingOrder()` ⚠️ Mantener fallback temporalmente
- `getPendingOrders()` ✅ Eliminar fallback
- `removePendingOrder()` ✅ Eliminar fallback
- `getPendingOrderById()` ✅ Eliminar fallback
- `saveCompletedOrder()` ⚠️ Mantener fallback temporalmente
- `getCompletedOrderById()` ✅ Eliminar fallback
- `getCompletedOrders()` ✅ Eliminar fallback
- `clearCompletedOrdersCache()` ✅ Eliminar fallback

**Razón para mantener fallbacks en save:**
Los métodos de guardado (`savePendingOrder`, `saveCompletedOrder`) deberían mantener fallback temporalmente para asegurar que no se pierdan datos si ObjectBox falla.

#### 1.3 Eliminar Métodos Legacy de Hive
**Eliminar completamente:**
```dart
// ❌ ELIMINAR estos métodos privados:
Product? _getProductByIdFromHive(String pid, {bool rehydrateAttributes = true})
Future<List<Product>> _searchLocalProductsByNameOrSkuFromHive(String term)
Product? _getCachedProductByBarcodeFromHive(String bc)
Product? _getProductBySkuFromHive(String sku)
Future<List<Product>> _getLocalVariationsForProductFromHive(String productId)

Map<String, model.Order> _getPendingOrdersFromHive()
Future<void> _removePendingOrderFromHive(String localId)
model.Order? _getPendingOrderByIdFromHive(String localId)
model.Order? _getCompletedOrderByIdFromHive(String orderId)
List<model.Order> _getCompletedOrdersFromHive({int limit = 20})
Future<void> _clearCompletedOrdersCacheFromHive()
```

### Riesgos
- ⚠️ Si ObjectBox falla, no hay fallback
- ⚠️ Requiere pruebas extensivas en producción
- ⚠️ Recomendado: Hacer rollout gradual

### Beneficios
- ✅ Código más simple y mantenible
- ✅ Menos superficie de bugs (un solo path de ejecución)
- ✅ Performance mejorada (sin overhead de fallbacks)

## Fase 2: Migrar Labels a ObjectBox

### Estado Actual
Labels usa `LabelPrintItem` (Hive) exclusivamente

### Entidad ya Disponible
✅ `LabelPrintItemCompact` ya existe en `lib/models/label_print_item_compact.dart`
✅ `LabelConverterService` ya existe en `lib/services/label_converter_service.dart`

### Cambios Requeridos

#### 2.1 Actualizar Storage Service
**Archivo:** `storage_service.dart`

**Nuevos métodos:**
```dart
// ✅ NUEVO: Labels en ObjectBox
Future<void> addToLabelQueue(LabelPrintItem item) async {
  if (_db == null) throw StateError('ObjectBox not initialized');

  final converter = LabelConverterService();
  final compact = converter.toCompact(item);

  final box = _db!.store.box<LabelPrintItemCompact>();
  box.put(compact);
}

List<LabelPrintItem> getLabelQueue() {
  if (_db == null) throw StateError('ObjectBox not initialized');

  final box = _db!.store.box<LabelPrintItemCompact>();
  final converter = LabelConverterService();

  return box.getAll().map((c) => converter.fromCompact(c)).toList();
}

Future<void> clearLabelQueue() async {
  if (_db == null) throw StateError('ObjectBox not initialized');

  final box = _db!.store.box<LabelPrintItemCompact>();
  box.removeAll();
}
```

#### 2.2 Deprecar Hive Box
```dart
// ⚠️ DEPRECATED: Label queue ahora en ObjectBox
@deprecated
hive.Box<LabelPrintItem>? _labelQueueBox;
```

### Migración de Datos
Crear método similar a `DataMigrationService` para labels:
```dart
Future<void> migrateLabelQueueToObjectBox() async {
  if (_labelQueueBox == null || !_labelQueueBox!.isOpen) return;

  final labels = _labelQueueBox!.values.toList();
  final converter = LabelConverterService();
  final box = _db!.store.box<LabelPrintItemCompact>();

  for (final label in labels) {
    final compact = converter.toCompact(label);
    box.put(compact);
  }

  await _labelQueueBox!.clear();
}
```

## Fase 3: Migrar InventoryMovements a ObjectBox

### Estado Actual
InventoryMovements probablemente usa `InventoryMovementAdapter` (Hive)

### Entidad ya Disponible
✅ `InventoryMovementCompact` ya existe en `lib/models/inventory_movement_compact.dart`
✅ `InventoryConverterService` ya existe en `lib/services/inventory_converter_service.dart`

### Cambios Similares a Fase 2
- Crear métodos ObjectBox en StorageService
- Migrar datos existentes
- Deprecar Hive box

## Fase 4: SyncQueue - Decisión Estratégica

### Opciones

#### Opción A: Migrar a ObjectBox
**Ventajas:**
- Consistencia (todo en ObjectBox)
- Performance mejorada

**Desventajas:**
- SyncQueue puede ser grande
- Requiere migración cuidadosa

#### Opción B: Mantener en Hive
**Ventajas:**
- SyncQueue ya funciona bien
- Menos riesgo de pérdida de datos
- Operaciones de cola (FIFO) son simples en Hive

**Desventajas:**
- Mantiene dependencia de Hive

**Recomendación:** MANTENER EN HIVE (al menos inicialmente)

## Fase 5: Deprecación Final de Hive

### Qué Mantener en Hive
```dart
// ✅ MANTENER en Hive:
hive.Box? _settingsBox;              // Configuración, timestamps
hive.Box<SyncOperation>? _syncQueueBox; // Cola de sincronización
hive.Box<List<String>>? _barcodeIndexBox; // Índice de búsqueda (opcional)
```

### Qué Eliminar Completamente
```dart
// ❌ ELIMINAR (migrar a ObjectBox):
hive.Box<Product>? _productBox;      // → ProductOptimized
hive.Box<model.Order>? _orderBox;    // → OrderCompact
hive.Box<model.Order>? _pendingOrderBox; // → OrderCompact
hive.Box<LabelPrintItem>? _labelQueueBox; // → LabelPrintItemCompact
```

### Actualizar Inicialización
```dart
Future<void> init() async {
  // ✅ ObjectBox - Base de datos principal
  _db = await DatabaseService.getInstance();
  _converter = ProductConverterService(_db!);
  _orderConverter = OrderConverterService();

  // ⚠️ Hive - Solo configuración y sync queue
  _settingsBox = await Hive.openBox(hiveSettingsBoxName);
  _syncQueueBox = await Hive.openBox<SyncOperation>(hiveSyncQueueBoxName);

  // ❌ ELIMINADO: Product, Order, Label boxes

  debugPrint("[StorageService] init: ObjectBox (primary) + Hive (config only)");
}
```

## Cronograma Recomendado

### Semana 1-2: Fase 1 (Eliminar Fallbacks)
- ✅ Eliminar fallbacks de Products
- ✅ Eliminar fallbacks de Orders (lectura)
- ⚠️ Mantener fallbacks en métodos de guardado
- ✅ Pruebas exhaustivas

### Semana 3-4: Fase 2 (Labels)
- ✅ Implementar métodos ObjectBox para labels
- ✅ Migrar datos existentes
- ✅ Pruebas de impresión de labels

### Semana 5-6: Fase 3 (InventoryMovements)
- ✅ Implementar métodos ObjectBox
- ✅ Migrar datos
- ✅ Pruebas de ajustes de inventario

### Semana 7-8: Fase 4 (SyncQueue - Decisión)
- ⚠️ Evaluar si migrar o mantener en Hive
- ✅ Si se migra: implementar y probar exhaustivamente

### Semana 9-10: Fase 5 (Limpieza Final)
- ✅ Eliminar código Hive legacy
- ✅ Actualizar dependencias pubspec.yaml
- ✅ Eliminar Hive adapters innecesarios
- ✅ Documentación final

## Métricas de Éxito

### Performance
- ✅ Queries de productos: < 5ms (objetivo: 2ms)
- ✅ Queries de orders: < 10ms (objetivo: 5ms)
- ✅ Guardado de productos: < 3ms

### Confiabilidad
- ✅ 0 pérdidas de datos durante migración
- ✅ 0 crashes relacionados con almacenamiento
- ✅ Rollback exitoso si es necesario

### Tamaño
- ✅ Reducción de 30-50% en tamaño de base de datos
- ✅ Menos fragmentación de disco

## Rollback Plan

### Si algo falla en Producción

#### Opción 1: Reactivar Fallbacks
```dart
// Revertir a versión con fallbacks
git revert <commit-hash>
flutter build apk --release
```

#### Opción 2: Migración Manual
```dart
// Ejecutar migración manual en dispositivos afectados
await migrationService.migrateFromObjectBoxToHive();
```

## Código de Referencia

### Eliminar Fallback (Ejemplo)
**ANTES:**
```dart
Product? getProductById(String pid) {
  if (_db == null) {
    return _getProductByIdFromHive(pid); // ❌ Fallback
  }
  try {
    return _converter!.optimizedToProduct(optimized);
  } catch(e) {
    return _getProductByIdFromHive(pid); // ❌ Fallback
  }
}
```

**DESPUÉS:**
```dart
Product? getProductById(String pid) {
  if (_db == null) {
    throw StateError('ObjectBox not initialized');
  }
  try {
    final optimized = box.get(productId);
    if (optimized == null) return null;
    return _converter!.optimizedToProduct(optimized);
  } catch(e) {
    debugPrint("[StorageService.getProductById] Error: $e");
    return null; // ✅ Fail gracefully
  }
}
```

## Notas Importantes

### ⚠️ NO Hacer
- ❌ Eliminar Hive boxes activos sin migración
- ❌ Modificar ObjectBox schema sin migración
- ❌ Cambiar IDs de entidades compact
- ❌ Eliminar código de migración antes de validar en producción

### ✅ Hacer
- ✅ Probar cada fase extensivamente
- ✅ Mantener backups de bases de datos
- ✅ Monitorear métricas en producción
- ✅ Implementar rollback plan
- ✅ Documentar cada cambio

## Contacto y Soporte

Para dudas o problemas:
1. Revisar `MIGRACION_OBJECTBOX_COMPLETADA.md`
2. Revisar este documento
3. Consultar logs de migración
4. Contactar al equipo de desarrollo

---

**Autor:** Claude Code
**Última Actualización:** 2025-11-22
**Estado:** Planificación - No Implementado
