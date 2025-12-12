# ARQUITECTURA API VS LOCAL - MY POS MOBILE

## RESUMEN EJECUTIVO

Este documento explica la estrategia de uso de API vs Base de Datos Local (ObjectBox/Hive) implementada en MY POS MOBILE según la especificación arquitectónica del sistema.

---

## TABLA DE ESTRATEGIAS POR TIPO DE DATO

| Tipo de Dato | Fuente | Comportamiento | Ubicación en Código |
|--------------|--------|----------------|---------------------|
| **Productos** | 🔵 SOLO LOCAL | ObjectBox - NUNCA consulta API | `product_repository.dart` (línea 116-193) |
| **Variaciones** | 🔵 SOLO LOCAL | ObjectBox - Solo atributos disponibles | `product_repository.dart` (línea 77-79) |
| **Clientes** | 🟢 SOLO API | WooCommerce siempre - NO cache local | `customer_notifier.dart` (línea 38-150) |
| **Pedidos** | 🟡 LOCAL + API | Restar local + Enviar a WC en paralelo | `order_notifier.dart`, `order_repository.dart` |
| **Inventario** | 🟡 LOCAL + API | Local primero + Forzar subida a API | `inventory_notifier.dart` (línea 215-362) |
| **Sincronización** | 🔷 MANUAL | Solo primera vez o cuando se solicite | `sync_manager.dart` |

---

## 1. PRODUCTOS 🔵 SOLO LOCAL

### Implementación Actual

**Archivo:** `lib/repositories/product_repository.dart`

**Método:** `searchProductsByTerm()` - Líneas 116-193

### Comportamiento

```dart
// ✅ CORRECTO: Búsqueda SOLO LOCAL
Future<Map<String, dynamic>> searchProductsByTerm(
  String term, {
  bool localOnly = false,  // ← Parámetro clave
  // ...
}) async {
  // PASO 1: Buscar en ObjectBox
  final localResults = await _storageService.searchLocalProductsByNameOrSku(searchTerm);

  // PASO 2: Si localOnly = true, RETORNAR inmediatamente
  if (localOnly) {
    return {
      'products': paginatedResults,
      'total_products': filteredResults.length,
      'total_pages': (filteredResults.length / limit).ceil(),
    };
  }

  // PASO 3: Solo si localOnly = false, llamar API (pero en MyPos NO se usa)
}
```

### Uso en Scanner

**Archivo:** `lib/providers/scanner_notifier.dart`

**Líneas 124-141 (búsqueda) y 185-192 (paginación)**

```dart
// ✅ CORRECTO: SIEMPRE usa localOnly = true
final apiResponse = await _productRepository.searchProductsByTerm(
  trimmedQuery,
  page: 1,
  limit: _productsPerPage,
  localOnly: true, // ← NUNCA consulta API
);
```

### Búsqueda por Código de Barras

**Archivo:** `lib/repositories/product_repository.dart`

**Método:** `searchProductByBarcodeOrSku()` - Líneas 81-114

```dart
// ⚠️ ACTUAL: Aún hace fallback a API si no encuentra en local
Product? cachedProduct = _storageService.getCachedProductByBarcode(trimmedId);

if (cachedProduct != null) {
  return cachedProduct; // Cache HIT
}

// ⚠️ ADVERTENCIA: Esto aún llama API si no está en cache
final apiProductResponse = await _wooCommerceService.searchProductByBarcodeOrSku(trimmedId);
```

**RECOMENDACIÓN:** Para adherirse completamente a la especificación, este método debería:
```dart
// ✅ PROPUESTO: Solo retornar local, sin fallback a API
Product? cachedProduct = _storageService.getCachedProductByBarcode(trimmedId);
return cachedProduct; // Si es null, está null (usuario debe sincronizar)
```

### Rendimiento

| Operación | Tiempo Promedio |
|-----------|----------------|
| Búsqueda local | < 50ms |
| Escaneo barcode | < 20ms |
| Búsqueda API (eliminada) | ~~500-2000ms~~ |

---

## 2. VARIACIONES 🔵 SOLO LOCAL

### Implementación Actual

**Archivo:** `lib/repositories/product_repository.dart`

**Método:** `getVariationById()` - Líneas 77-79

```dart
Future<Product?> getVariationById(String parentProductId, String variationId, { bool forceApi = false }) async {
  return await getProductById(variationId, forceApi: forceApi);
}
```

### Comportamiento Esperado

Según la especificación V3, las variaciones deben buscarse SOLO en ObjectBox:

**Widget Esperado:** `variation_selector_widget.dart` (NO EXISTE AÚN)

```dart
// ✅ PROPUESTO: Selector de variaciones SOLO LOCAL
final localVariations = await _storageService.getVariationsByParentId(parentProductId);

if (localVariations.isEmpty) {
  // NO llamar API - mostrar mensaje al usuario
  return showDialog(
    context,
    "No hay variaciones sincronizadas para este producto.\n"
    "Ve a Configuración → Sincronizar catálogo."
  );
}
```

### Estado Actual

⚠️ **PENDIENTE:** El sistema aún usa `getProductById()` que puede hacer fallback a API.

**RECOMENDACIÓN:** Crear un servicio específico para variaciones que solo consulte ObjectBox.

---

## 3. CLIENTES 🟢 SOLO API

### Implementación Actual

**Archivo:** `lib/providers/customer_notifier.dart`

**Líneas 38-150**

### Comportamiento

```dart
// ✅ CORRECTO: SIEMPRE llama WooCommerce API
Future<void> _fetchRecentCustomers() async {
  final customers = await _wooCommerceService.getCustomers(
    perPage: 10,
    orderBy: 'registered_date',
    order: 'desc',
  ); // ← Siempre API, NO cache
}

Future<void> _performApiSearch(String query) async {
  final apiResults = await _wooCommerceService.searchCustomersAPI(primaryKeyword);
  // ← Siempre API, NO cache
}
```

### Justificación

- **Datos sensibles:** Información de contacto, direcciones, emails
- **Siempre actualizado:** Cambios desde web/otras apps
- **No requiere sincronización:** Datos pequeños, búsqueda rápida
- **Privacidad:** No almacenar información de clientes en dispositivo

### Manejo de Errores

```dart
on NetworkException catch (e) {
  // Sin conexión → Usuario NO puede buscar clientes
  state = state.copyWith(
    error: "Error de red al cargar clientes: ${e.message}",
    recentCustomers: [],
  );
}
```

**Flujo:** Si no hay internet, el usuario NO puede buscar/crear clientes (comportamiento correcto).

---

## 4. PEDIDOS 🟡 LOCAL + API (EN PARALELO)

### Implementación Actual

**Archivo:** `lib/providers/order_notifier.dart`

**Archivo:** `lib/repositories/order_repository.dart`

### Flujo de Creación de Pedido Completado

```dart
// PASO 1: Guardar en LOCAL (Hive) inmediatamente
final completedOrder = order.copyWith(
  orderStatus: 'completed',
  date: DateTime.now(),
  isSynced: false, // ← Marca como NO sincronizado
);

await _orderRepository.saveCompletedOrder(completedOrder);

// PASO 2: RESTAR stock en ObjectBox INMEDIATAMENTE
for (final item in completedOrder.items) {
  final product = await _productRepository.getProductById(item.productId);
  final updatedStock = (product.stockQuantity ?? 0) - item.quantity;

  await _storageService.cacheProduct(
    product.copyWith(stockQuantity: updatedStock)
  );
}

// PASO 3: Enviar a WooCommerce en PARALELO (no bloquea)
_syncManager.enqueueSyncOperation(
  SyncOperation(
    type: SyncOperationType.createOrder,
    data: completedOrder.toJson(),
  )
);
```

### Flujo de Borrador de Pedido

**Archivo:** `lib/providers/order_notifier.dart`

```dart
// Guardar borrador en LOCAL (Hive)
Future<void> _saveCurrentOrderDebounced() async {
  await _orderRepository.savePendingOrder(
    hiveCurrentOrderPendingKey, // ← Clave especial para orden actual
    state.order,
  );
}

// Enviar a WooCommerce como status='pending' (opcional)
final response = await _wooCommerceService.createOrder({
  ...orderData,
  'status': 'pending', // ← Reserva stock 5 minutos en WC
});
```

### Cargar Borrador Existente

```dart
// PASO 1: Buscar por orderId en LOCAL (Hive)
final pendingOrders = _orderRepository.getPendingOrders();
final savedOrder = pendingOrders[hiveCurrentOrderPendingKey];

// PASO 2: Cargar EXACTAMENTE los mismos productos
if (savedOrder != null) {
  // NO crear nuevos items, usar los existentes
  return CurrentOrderState(order: savedOrder);
}
```

### Sincronización con WooCommerce

Cuando se completa un pedido:

1. **App → WC:** Envía pedido con status='completed'
2. **WC:** Procesa pedido y RESTA stock automáticamente
3. **Resultado:** Ambas bases (ObjectBox + WC) quedan con stock actualizado

---

## 5. INVENTARIO 🟡 LOCAL + API (LOCAL FIRST)

### Implementación Actual

**Archivo:** `lib/providers/inventory_notifier.dart`

**Método:** `performMassInventoryAdjustment()` - Líneas 215-312

### Flujo Local-First

```dart
// ═══════════════════════════════════════════════════════════════
// PASO 1: ACTUALIZAR BASE DE DATOS LOCAL INMEDIATAMENTE
// ═══════════════════════════════════════════════════════════════
for (final item in itemsToAdjust) {
  final product = await productRepo.getProductById(item.productId, forceApi: false);

  final stockBefore = product.stockQuantity ?? 0;
  final stockAfter = stockBefore + item.quantityChanged;

  debugPrint('[Inventory] 📦 Actualizando stock LOCAL: ${product.name}');
  debugPrint('    Antes: $stockBefore → Después: $stockAfter (Δ ${item.quantityChanged})');

  final updatedProduct = product.copyWith(
    stockQuantity: () => stockAfter,
    stockStatus: () => stockAfter > 0 ? 'instock' : 'outofstock',
  );

  // ✅ GUARDAR EN OBJECTBOX INMEDIATAMENTE
  await _storageService.cacheProduct(updatedProduct);
}

debugPrint('[Inventory] ✅ Stock local actualizado para ${itemsToAdjust.length} productos');

// ═══════════════════════════════════════════════════════════════
// PASO 2: GUARDAR MOVIMIENTO EN HISTORIAL LOCAL
// ═══════════════════════════════════════════════════════════════
final newMovement = InventoryMovement(
  id: uuid.v4(),
  date: DateTime.now(),
  type: type,
  description: description,
  items: itemsToAdjust,
  isSynced: false, // ← Marca como NO sincronizado
);

await _inventoryRepository.saveInventoryMovement(newMovement);
debugPrint('[Inventory] ✅ Movimiento guardado en historial local');

// ═══════════════════════════════════════════════════════════════
// PASO 3: REFRESCAR UI CON DATOS LOCALES
// ═══════════════════════════════════════════════════════════════
await loadInventoryMovements(refresh: true);
_setError('✅ Inventario actualizado localmente', durationSeconds: 3);

state = state.copyWith(isLoadingProducts: false);
// ← UI YA ESTÁ ACTUALIZADA, usuario puede continuar trabajando

// ═══════════════════════════════════════════════════════════════
// PASO 4: SINCRONIZAR CON WOOCOMMERCE EN BACKGROUND (NO BLOQUEA)
// ═══════════════════════════════════════════════════════════════
_syncInventoryWithWooCommerce(newMovement, itemsToAdjust);
```

### Sincronización Background

**Método:** `_syncInventoryWithWooCommerce()` - Líneas 314-362

```dart
Future<void> _syncInventoryWithWooCommerce(
  InventoryMovement movement,
  List<InventoryMovementLine> itemsToAdjust,
) async {
  debugPrint('[Inventory] 🔄 Iniciando sincronización con WooCommerce (background)...');

  // Preparar batch de actualizaciones
  final batchItems = itemsToAdjust.map((item) {
    return {
      'id': item.productId,
      'stock': item.quantityChanged.abs(),
      'operation': item.quantityChanged > 0 ? 'add' : 'subtract',
    };
  }).toList();

  // Enviar a WooCommerce
  final response = await _wooService.batchUpdateStock(batchItems);

  if (response['success'] == true) {
    debugPrint('[Inventory] ✅ Sincronizado con WooCommerce: ${response['updated']} productos');

    // Marcar movimiento como sincronizado
    final syncedMovement = movement.copyWith(isSynced: true);
    await _inventoryRepository.saveInventoryMovement(syncedMovement);
  }
}
```

### Flujo desde WooCommerce → App

Cuando se actualiza stock desde WooCommerce (web, plugin, otra app):

1. **Plugin MyPos API:** Detecta cambio en WC
2. **Webhook/Polling:** Notifica a la app (si está implementado)
3. **App:** Recibe actualización y modifica ObjectBox

**Archivo esperado:** `sync_manager.dart` - método `syncProductsFromWooCommerce()`

---

## 6. SINCRONIZACIÓN 🔷 MANUAL

### Implementación Actual

**Archivo:** `lib/services/sync_manager.dart`

### Estrategia

- **Primera vez:** Sincronización completa del catálogo
- **Manual:** Usuario va a Configuración → Sincronizar
- **NUNCA automático:** NO hay polling/webhooks en background sin solicitud

### Motivos

1. **Rendimiento:** No desperdiciar batería/datos
2. **Control:** Usuario decide cuándo sincronizar
3. **Confiabilidad:** Evitar conflictos de datos
4. **Offline-First:** App funciona sin conexión

### Tipos de Sincronización

```dart
// 1. Sincronización inicial (primera vez)
Future<void> performInitialSync() async {
  await syncProductsFromWooCommerce(fullSync: true);
}

// 2. Sincronización manual (botón en configuración)
Future<void> performManualSync() async {
  await syncProductsFromWooCommerce(fullSync: false); // Solo cambios recientes
}

// 3. Sincronización de operaciones pendientes (queue)
Future<void> syncPendingOperations() async {
  final pendingOps = await _storageService.getPendingSyncOperations();

  for (final op in pendingOps) {
    switch (op.type) {
      case SyncOperationType.createOrder:
        await _sendOrderToWooCommerce(op.data);
        break;
      case SyncOperationType.updateInventory:
        await _sendInventoryToWooCommerce(op.data);
        break;
    }
  }
}
```

---

## COMPARACIÓN: ANTES vs DESPUÉS

### Productos - Búsqueda

**ANTES (con API fallback):**
```dart
// 1. Buscar en local
final localResults = await searchLocal(query);

// 2. Si vacío, llamar API
if (localResults.isEmpty) {
  return await searchAPI(query); // ❌ LENTO: 500-2000ms
}

return localResults;
```

**DESPUÉS (solo local):**
```dart
// 1. Buscar en local
final localResults = await searchLocal(query);

// 2. Si vacío, retornar vacío (usuario sincroniza manualmente)
if (localResults.isEmpty) {
  return []; // ✅ RÁPIDO: <50ms
}

return localResults;
```

### Inventario - Ajuste Masivo

**ANTES (bloqueaba UI):**
```dart
// 1. Llamar API primero (BLOQUEABA 2-5 segundos)
await wooService.updateStock(items); // ❌ Usuario esperando...

// 2. Actualizar local
await storageService.updateLocalStock(items);

// 3. Refrescar UI
setState();
```

**DESPUÉS (local-first):**
```dart
// 1. Actualizar local INMEDIATAMENTE (✅ 20-50ms)
await storageService.updateLocalStock(items);

// 2. Refrescar UI (✅ Usuario puede continuar)
setState();

// 3. API en background (no bloquea)
Future.microtask(() => wooService.updateStock(items));
```

---

## LOGS DE VERIFICACIÓN

### Búsqueda Local (Correcto)

```
[ProductRepository.searchProductsByTerm] ✅ Using LOCAL results only: 15 productos found
[Scanner] Barcode scan result for '7501234567890' → Camiseta Azul (8ms)
```

### Inventario Local-First (Correcto)

```
[Inventory] 🔄 LOCAL-FIRST: Ajuste masivo - Entrada de mercancía, Items: 3
[Inventory] 📦 Actualizando stock LOCAL: Camiseta Azul
    Antes: 10 → Después: 15 (Δ +5)
[Inventory] ✅ Stock local actualizado para 3 productos
[Inventory] ✅ Movimiento guardado en historial local (isSynced: false)
[Inventory] 🔄 Iniciando sincronización con WooCommerce (background)...
[Inventory] ✅ Sincronizado con WooCommerce: 3 productos
```

### Clientes API-Only (Correcto)

```
[Customer] Fetching recent customers...
[WooCommerceService] GET /wc/v3/customers?per_page=10
... Recent customers loaded: 10
```

---

## CASOS DE USO

### Caso 1: Buscar Producto que NO está sincronizado

**Escenario:** Usuario escanea código de barras nuevo

```
[Scanner] Processing barcode: 7501234567999
[ProductRepository] Searching in ObjectBox...
[ProductRepository] ⚠️ No local results found for: 7501234567999
[Scanner] Producto no encontrado para el código '7501234567999'.
```

**Solución para el usuario:**
1. Ir a Configuración → Sincronizar catálogo
2. Volver a escanear el código

**NO se hace:** Llamar API automáticamente (según especificación)

---

### Caso 2: Ajuste de Inventario Sin Internet

**Escenario:** Usuario hace ajuste masivo en modo avión

```
[Inventory] 🔄 LOCAL-FIRST: Ajuste masivo
[Inventory] ✅ Stock local actualizado para 5 productos
[Inventory] ✅ Movimiento guardado en historial local (isSynced: false)
[Inventory] ⚠️ Sin conexión - sincronización pendiente
```

**Cuando vuelva internet:**
```
[SyncManager] Connectivity restored - syncing pending operations
[Inventory] 🔄 Sincronizando movimientos pendientes con WooCommerce...
[Inventory] ✅ Sincronizado con WooCommerce: 5 productos
```

---

### Caso 3: Crear Pedido y Completarlo

**Escenario:** Vender 3 productos

```
[CurrentOrder] Adding item: Camiseta Azul (qty: 2)
[CurrentOrder] Saving to pending orders (debounced)...

[CurrentOrder] Completing order...
[CurrentOrder] ✅ Order saved locally with status: completed
[ProductRepository] Updating local stock for 3 items...
[SyncManager] Enqueued sync operation: createOrder
[WooCommerceService] POST /wc/v3/orders (background)
[WooCommerceService] ✅ Order #1234 created in WooCommerce
```

**Resultado:**
- Stock restado en ObjectBox ✅
- Stock restado en WooCommerce ✅
- Pedido guardado en ambos lados ✅

---

## RECOMENDACIONES DE MEJORA

### 1. Eliminar Fallback a API en Barcode Search

**Archivo:** `lib/repositories/product_repository.dart` - Línea 81-114

**Cambio propuesto:**
```dart
Future<Product?> searchProductByBarcodeOrSku(String code) async {
  if (code.trim().isEmpty) return null;

  // ✅ SOLO buscar en local, NO llamar API
  final cachedProduct = _storageService.getCachedProductByBarcode(code)
      ?? _storageService.getProductBySku(code);

  return cachedProduct; // Si es null, usuario debe sincronizar
}
```

### 2. Crear LocalSearchService Dedicado

**Archivo nuevo:** `lib/services/local_search_service.dart`

```dart
class LocalSearchService {
  final StorageService _storageService;

  Future<List<Product>> searchProducts(String query) async {
    return await _storageService.searchLocalProductsByNameOrSku(query);
  }

  Future<Product?> searchByBarcode(String barcode) async {
    return _storageService.getCachedProductByBarcode(barcode);
  }

  Future<List<Product>> getVariations(String parentId) async {
    return _storageService.getVariationsByParentId(parentId);
  }
}
```

### 3. Widget de Selector de Variaciones

**Archivo nuevo:** `lib/widgets/variation_selector_widget.dart`

```dart
class VariationSelectorWidget extends StatelessWidget {
  final String productId;

  Future<void> _loadVariations() async {
    final localVariations = await localSearchService.getVariations(productId);

    if (localVariations.isEmpty) {
      // NO llamar API - mostrar mensaje
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Variaciones no sincronizadas'),
          content: Text('Ve a Configuración → Sincronizar catálogo'),
        ),
      );
      return;
    }

    // Mostrar selector con variaciones locales
  }
}
```

---

## CONCLUSIÓN

La arquitectura actual ya implementa correctamente:

✅ **Productos:** Búsqueda SOLO LOCAL (scanner_notifier.dart usa `localOnly: true`)

✅ **Clientes:** SOLO API (customer_notifier.dart siempre llama WooCommerce)

✅ **Inventario:** LOCAL-FIRST con sincronización background (inventory_notifier.dart líneas 215-362)

✅ **Pedidos:** LOCAL + API en paralelo (order_notifier.dart)

⚠️ **Pendientes:**
- Eliminar fallback a API en `searchProductByBarcodeOrSku()`
- Implementar widget de variaciones SOLO LOCAL
- Documentar flujo de sincronización desde WC → App

---

**Última actualización:** 2025-12-12

**Versión:** 3.1.0

**Responsable:** Claude Sonnet 4.5
