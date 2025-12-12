# GUÍA RÁPIDA: CUÁNDO USAR API vs LOCAL

## DECISIÓN RÁPIDA

```
┌─────────────────────────────────────────────────────────────┐
│ ¿Qué operación necesitas hacer?                             │
└─────────────────────────────────────────────────────────────┘
           │
           ├─ Buscar/Listar PRODUCTOS ────────→ 🔵 SOLO LOCAL (ObjectBox)
           │                                      ❌ NUNCA usar API
           │
           ├─ Ver VARIACIONES de producto ───→ 🔵 SOLO LOCAL (ObjectBox)
           │                                      ❌ NUNCA usar API
           │
           ├─ Buscar/Crear CLIENTES ─────────→ 🟢 SOLO API (WooCommerce)
           │                                      ❌ NUNCA cachear local
           │
           ├─ Crear/Completar PEDIDOS ───────→ 🟡 LOCAL + API
           │                                      1. Guardar local
           │                                      2. Restar stock local
           │                                      3. Enviar API (paralelo)
           │
           ├─ Ajustar INVENTARIO ────────────→ 🟡 LOCAL-FIRST
           │                                      1. Actualizar local
           │                                      2. Guardar historial
           │                                      3. Sincronizar API (background)
           │
           └─ SINCRONIZAR catálogo ──────────→ 🔷 MANUAL
                                                 Solo cuando usuario lo pida
```

---

## REGLAS DE ORO

### 🔵 PRODUCTOS Y VARIACIONES - NUNCA API

```dart
// ✅ CORRECTO
await productRepository.searchProductsByTerm(
  query,
  localOnly: true,  // ← SIEMPRE true
);

// ❌ INCORRECTO
await productRepository.searchProductsByTerm(
  query,
  localOnly: false, // ← NUNCA hacer esto
);

// ❌ INCORRECTO
if (localResults.isEmpty) {
  return await apiSearch(query); // ← NUNCA fallback a API
}
```

**Justificación:**
- Catálogo grande (500-5000 productos)
- Búsqueda instantánea (<50ms local vs 500-2000ms API)
- Offline-first (funciona sin internet)
- No cambia frecuentemente

**Si no hay resultados:**
→ Usuario debe ir a Configuración → Sincronizar

---

### 🟢 CLIENTES - SIEMPRE API

```dart
// ✅ CORRECTO
await wooCommerceService.searchCustomersAPI(query);
await wooCommerceService.getCustomers();

// ❌ INCORRECTO
await storageService.cacheCustomer(customer); // ← NO hacer
final cached = storageService.getCustomer(id); // ← NO existe
```

**Justificación:**
- Datos sensibles (privacidad)
- Siempre actualizado (cambios desde web)
- Dataset pequeño (10-100 clientes típicos)
- Búsqueda rápida en API (<500ms)

**Si no hay internet:**
→ Usuario NO puede buscar clientes (comportamiento correcto)

---

### 🟡 PEDIDOS - LOCAL + API EN PARALELO

```dart
// ✅ FLUJO CORRECTO

// PASO 1: Guardar LOCAL
final completedOrder = order.copyWith(
  orderStatus: 'completed',
  isSynced: false, // ← Importante
);
await orderRepository.saveCompletedOrder(completedOrder);

// PASO 2: Restar stock LOCAL
for (final item in order.items) {
  await productRepository.decrementStock(item.productId, item.quantity);
}

// PASO 3: Enviar API (NO BLOQUEA)
syncManager.enqueueSyncOperation(
  SyncOperation(type: SyncOperationType.createOrder, data: orderData),
);

// ✅ UI ya está actualizada, usuario puede continuar
```

**¿Por qué este orden?**
- UI responde instantáneamente
- Stock correcto en dispositivo local
- Si falla API, se reintenta después
- Ambas bases quedan sincronizadas

---

### 🟡 INVENTARIO - LOCAL-FIRST

```dart
// ✅ FLUJO CORRECTO

// PASO 1: Actualizar LOCAL (20-50ms)
for (final item in items) {
  final product = await productRepo.getProductById(item.productId);
  final newStock = product.stockQuantity + item.quantityChanged;

  await storageService.cacheProduct(
    product.copyWith(stockQuantity: newStock),
  );
}

// PASO 2: Guardar historial LOCAL
await inventoryRepository.saveMovement(movement);

// PASO 3: UI actualizada (usuario puede seguir)
setState(() => isLoading = false);

// PASO 4: API en background (NO BLOQUEA)
Future.microtask(() {
  wooService.batchUpdateStock(items);
});


// ❌ FLUJO INCORRECTO
// NUNCA hacer esto:
await wooService.updateStock(items); // ← BLOQUEA 2-5 segundos
await storageService.updateLocal(items); // ← Usuario esperando...
```

---

### 🔷 SINCRONIZACIÓN - SOLO MANUAL

```dart
// ✅ CORRECTO - Usuario presiona botón
Future<void> onSyncButtonPressed() async {
  showDialog("Sincronizando catálogo...");

  await syncManager.syncProductsFromWooCommerce();

  showDialog("✅ Sincronización completa");
}

// ❌ INCORRECTO - Polling automático
// NUNCA hacer esto:
Timer.periodic(Duration(minutes: 5), (timer) {
  syncManager.syncProducts(); // ← NO hacer
});

// ❌ INCORRECTO - Sincronización al inicio
// NUNCA hacer esto:
@override
void initState() {
  super.initState();
  syncManager.syncProducts(); // ← NO hacer sin preguntar
}
```

**¿Cuándo sincronizar?**
- Primera vez (setup inicial)
- Usuario presiona botón "Sincronizar"
- Usuario reporta "producto no encontrado"

**¿Cuándo NO sincronizar?**
- Al abrir la app
- Periódicamente en background
- Después de cada operación

---

## TABLA DE DECISIÓN RÁPIDA

| Operación | Código | Ubicación |
|-----------|--------|-----------|
| **Buscar producto por nombre** | `productRepo.searchProductsByTerm(query, localOnly: true)` | `scanner_notifier.dart:126` |
| **Buscar por código barras** | `productRepo.searchProductByBarcodeOrSku(code)` | `scanner_notifier.dart:358` |
| **Obtener variaciones** | `productRepo.getVariationById(parentId, varId)` | `product_repository.dart:77` |
| **Buscar cliente** | `wooService.searchCustomersAPI(query)` | `customer_notifier.dart:132` |
| **Crear pedido** | `orderRepo.saveCompletedOrder(order) + syncManager.enqueue()` | `order_notifier.dart` |
| **Ajustar inventario** | `inventoryNotifier.performMassInventoryAdjustment()` | `inventory_notifier.dart:219` |
| **Sincronizar catálogo** | `syncManager.syncProductsFromWooCommerce()` | Botón en UI |

---

## ERRORES COMUNES Y SOLUCIONES

### ❌ Error 1: "Producto no encontrado" al escanear

**Causa:** Producto no está en ObjectBox

**Solución:**
```dart
// NO hacer fallback a API
// MOSTRAR al usuario:
showDialog(
  "Producto no sincronizado.\n"
  "Ve a Configuración → Sincronizar catálogo"
);
```

### ❌ Error 2: Inventario se actualiza lento

**Causa:** Llamar API antes de actualizar local

**Solución:**
```dart
// ✅ Actualizar local PRIMERO
await storageService.updateLocalStock();
setState(); // ← UI actualizada YA

// Luego API en background
Future.microtask(() => wooService.updateStock());
```

### ❌ Error 3: Cliente no aparece en búsqueda

**Causa:** Sin conexión a internet

**Solución:**
```dart
// NO cachear clientes
// MOSTRAR error:
catch (NetworkException e) {
  showError("Sin conexión. No se pueden buscar clientes.");
}
```

---

## CHECKLIST DE IMPLEMENTACIÓN

Cuando implementes una nueva feature, verifica:

- [ ] **Productos/Variaciones:** ¿Usas `localOnly: true`?
- [ ] **Productos:** ¿NO tienes fallback a API?
- [ ] **Clientes:** ¿SIEMPRE llamas API directamente?
- [ ] **Clientes:** ¿NO cacheas en ObjectBox/Hive?
- [ ] **Pedidos:** ¿Guardas local ANTES de llamar API?
- [ ] **Pedidos:** ¿Restas stock local INMEDIATAMENTE?
- [ ] **Inventario:** ¿Actualizas local PRIMERO?
- [ ] **Inventario:** ¿API va en background (Future.microtask)?
- [ ] **Sincronización:** ¿Solo se ejecuta manualmente?
- [ ] **Logs:** ¿Indican "LOCAL" o "API" claramente?

---

## PERFORMANCE ESPERADO

| Operación | Tiempo | Ubicación Código |
|-----------|--------|------------------|
| Búsqueda producto local | < 50ms | `product_repository.dart:133-148` |
| Escaneo barcode | < 20ms | `scanner_notifier.dart:350-381` |
| Actualización inventario local | < 100ms | `inventory_notifier.dart:243-279` |
| Guardar pedido local | < 50ms | `order_repository.dart` |
| Sincronización API (background) | 1-3s | No bloquea UI |

Si alguna operación es más lenta, revisar implementación.

---

## LOGS DE VERIFICACIÓN

### ✅ Búsqueda Local (Correcto)

```
[ProductRepository.searchProductsByTerm] ✅ Using LOCAL results only: 15 productos found
```

### ❌ Búsqueda API (Incorrecto)

```
[ProductRepository.searchProductsByTerm] 📡 Fetching from API: camiseta
```

Si ves el segundo log, hay un error en la implementación.

---

## CONTACTO

**Documentación completa:** `ARQUITECTURA_API_VS_LOCAL.md`

**Preguntas frecuentes:**
- "¿Por qué productos son solo local?" → Rendimiento + offline-first
- "¿Por qué clientes son solo API?" → Privacidad + datos actualizados
- "¿Por qué no sincronización automática?" → Batería + control del usuario

---

**Última actualización:** 2025-12-12
