# HALLAZGOS DE VERIFICACIÓN CSV

**Fecha:** 2025-12-12
**Estado:** ❌ ENCONTRADAS 2 DISCREPANCIAS CRÍTICAS

---

## RESUMEN EJECUTIVO

Después de verificar el código contra las especificaciones del CSV, encontré **2 funcionalidades críticas que NO están implementadas** según las especificaciones del CSV:

1. ❌ **Guardar borrador → WooCommerce como 'pending'** (CSV línea 10)
2. ❌ **Sincronización bidireccional WC → APP** (CSV línea 34)

---

## HALLAZGO #1: Guardar Borrador NO se envía a WooCommerce ❌

### CSV Especifica (Línea 10):

```
"Guardar borrador de pedido | local y api enviar a woocommerce
como pedido sin completar para que guarde por 5 minutos los
productos y estos se disminuya del stock si se cancela volvera
la cantidad exacta"
```

### Flujo Esperado:

1. Usuario guarda borrador del pedido
2. **GUARDAR en LOCAL** (Hive/ObjectBox) ✅
3. **ENVIAR a WooCommerce** como status='pending' ❌
4. WooCommerce disminuye stock temporalmente (reserva 5 min)
5. Si se cancela, WC restaura stock automáticamente

### Implementación Actual:

**Archivo:** `my_pos_app/lib/providers/order_notifier.dart`

**Código actual (líneas 170-192):**
```dart
Future<void> _saveCurrentOrderDebounced() async {
  _saveOrderDebounce?.cancel();
  _saveOrderDebounce = Timer(const Duration(milliseconds: 800), () async {
    state.whenData((currentState) async {
      try {
        // ✅ SOLO guarda en LOCAL
        await _orderRepository.savePendingOrder(orderToSave, keyToSave);
        debugPrint("[CurrentOrder] Order saved to Hive with key $keyToSave");

        // ❌ NO envía a WooCommerce como 'pending'

      } catch (e) {
        debugPrint("[CurrentOrder] !! ERROR saving order to Hive: $e");
      }
    });
  });
}
```

### Problema:

- ✅ Guarda borrador en LOCAL
- ❌ NO envía a WooCommerce como status='pending'
- ❌ WooCommerce NO reserva stock
- ❌ Si hay conflicto de stock, no se detecta hasta enviar pedido final

### Impacto:

**ALTO** - Sin la reserva de stock en WooCommerce:
- Dos usuarios pueden vender el mismo producto
- No hay prevención de overselling
- Stock no se sincroniza correctamente

---

## HALLAZGO #2: NO hay Sincronización WC → APP ❌

### CSV Especifica (Línea 34):

```
"Sincronización delta de pedidos | local y api debe forzar a el
ajuste de pedidos local modificando únicamente los productos
seleccionados del pedido y debe forzar la subida a la api como
prioridad para que el plugin detecte el pedido y también pueda
detectarlo como pedido en woocommerce, y cuando se hace desde
wordpress deberá enviar el nuevo pedido a la aplicación para que
la aplicación detecte el nuevo pedido y la aplicación modifique
la base de datos como ajuste en los productos por el nuevo pedido"
```

### Flujo Esperado:

**APP → WooCommerce:** ✅ Implementado
```
App crea pedido → Resta stock local → Envía a WC → WC resta stock
```

**WooCommerce → APP:** ❌ NO Implementado
```
Pedido desde WC/Web → Plugin notifica App → App actualiza ObjectBox → Resta stock local
```

### Implementación Actual:

**Archivo:** `my_pos_app/lib/services/delta_sync_service.dart`

**Código actual (líneas 1-150):**
```dart
class DeltaSyncService extends ChangeNotifier {
  // ✅ SOLO sincroniza PRODUCTOS
  Future<void> performDeltaSync() async {
    final deltaResponse = await _wooService.getDeltaChanges(
      since: lastSyncTimestamp,
      type: 'compact', // Solo productos
      limit: 100,
    );

    // ❌ NO sincroniza PEDIDOS desde WooCommerce
  }
}
```

### Problema:

- ✅ Sincroniza productos WC → APP
- ❌ NO sincroniza pedidos WC → APP
- ❌ NO sincroniza movimientos de inventario WC → APP
- ❌ Si alguien crea pedido desde WP Admin, la app NO lo detecta
- ❌ Stock en app queda desincronizado

### Impacto:

**ALTO** - Sin sincronización bidireccional:
- App y WooCommerce tienen datos inconsistentes
- Dos vendedores (uno en app, uno en web) pueden overselling
- Movimientos de inventario desde WP Admin no se reflejan en app

---

## COMPARACIÓN DETALLADA

### Flujo de Guardar Borrador

#### Según CSV (Línea 10):

```
┌─────────────────────────────────────────────────────┐
│ 1. Usuario edita pedido                              │
│ 2. Guardar en LOCAL (Hive) con orderId              │
│ 3. Enviar a WooCommerce como status='pending'       │
│ 4. WC reserva stock por 5 minutos                   │
│ 5. Si cancela → WC restaura stock automáticamente   │
└─────────────────────────────────────────────────────┘
```

#### Implementación Actual:

```
┌─────────────────────────────────────────────────────┐
│ 1. Usuario edita pedido                              │
│ 2. Guardar en LOCAL (Hive) ✅                       │
│ 3. ❌ NO envía a WooCommerce                         │
│ 4. ❌ Stock NO se reserva                            │
│ 5. ❌ Riesgo de overselling                          │
└─────────────────────────────────────────────────────┘
```

---

### Flujo de Sincronización de Pedidos

#### Según CSV (Línea 34):

```
APP ←──────────────────────→ WooCommerce
 ↓                              ↓
ObjectBox                      MySQL
 ↓                              ↓
- Crea pedido                  - Detecta pedido nuevo
- Resta stock                  - Plugin notifica App
- Envía a WC ✅                - App actualiza ObjectBox ❌
- WC resta stock               - App resta stock ❌
```

#### Implementación Actual:

```
APP ──────────────────────────→ WooCommerce
 ↓                              ↓
ObjectBox                      MySQL
 ↓                              ↓
- Crea pedido                  - Recibe pedido
- Resta stock                  - Resta stock
- Envía a WC ✅

❌ NO hay flujo WC → APP
❌ Pedidos desde WP Admin no se sincronizan
❌ Stock queda desincronizado
```

---

## CASOS DE USO AFECTADOS

### Caso 1: Dos Vendedores, Mismo Producto

**Escenario:**
- Vendedor A (App): Agrega Producto X al borrador
- Vendedor B (Web): Agrega Producto X al carrito
- Ambos completan la venta al mismo tiempo

**Comportamiento Actual:**
1. App NO reserva stock en WC
2. Web NO sabe que App tiene el producto
3. Ambos venden exitosamente
4. Stock negativo en WooCommerce ❌

**Comportamiento Esperado (según CSV):**
1. App reserva stock en WC como 'pending'
2. Web intenta agregar al carrito
3. WC dice "Stock insuficiente"
4. Solo uno puede vender ✅

---

### Caso 2: Venta desde WP Admin

**Escenario:**
- Admin crea pedido desde WP Admin
- Vende 5 unidades de Producto Y
- Vendedor en App busca Producto Y

**Comportamiento Actual:**
1. Admin vende 5 unidades en WP
2. WC resta stock (quedan 10 unidades)
3. App NO detecta el cambio ❌
4. App muestra 15 unidades (incorrecto) ❌
5. App puede vender más de lo disponible

**Comportamiento Esperado (según CSV):**
1. Admin vende 5 unidades en WP
2. WC resta stock (quedan 10 unidades)
3. **Plugin notifica a la App** ✅
4. App actualiza ObjectBox a 10 unidades ✅
5. App muestra stock correcto ✅

---

### Caso 3: Ajuste de Inventario desde WP

**Escenario:**
- Admin ajusta inventario desde plugin WP
- Agrega 50 unidades a Producto Z
- Vendedor en App consulta Producto Z

**Comportamiento Actual:**
1. Admin ajusta +50 en WP
2. WC actualiza stock
3. App NO detecta el cambio ❌
4. App muestra stock antiguo
5. Vendedor cree que no hay stock cuando SÍ hay

**Comportamiento Esperado (según CSV):**
1. Admin ajusta +50 en WP
2. **Plugin notifica a la App** ✅
3. App actualiza ObjectBox +50 ✅
4. App muestra stock correcto ✅

---

## ARCHIVOS AFECTADOS

### Para Hallazgo #1 (Borrador → WC):

**Modificar:**
- `my_pos_app/lib/providers/order_notifier.dart`
  - Método: `_saveCurrentOrderDebounced()` (líneas ~170-192)
  - Agregar: Envío a WooCommerce como status='pending'

**Agregar en WooCommerceService:**
- Método nuevo: `createDraftOrder(Order order)` → POST /wc/v3/orders (status='pending')

---

### Para Hallazgo #2 (Sync WC → APP):

**Modificar:**
- `my_pos_app/lib/services/delta_sync_service.dart`
  - Agregar método: `syncOrdersFromWooCommerce()`
  - Agregar método: `syncInventoryMovementsFromWooCommerce()`

**Agregar en WooCommerceService:**
- Método: `getOrdersDelta(since)` → GET /mypos/v1/orders/delta
- Método: `getInventoryDelta(since)` → GET /mypos/v1/inventory/delta

**Plugin WooCommerce (Backend):**
- Endpoint: `/mypos/v1/orders/delta` (retorna pedidos nuevos/modificados)
- Endpoint: `/mypos/v1/inventory/delta` (retorna movimientos de inventario)
- Webhook: Notificar app cuando hay nuevo pedido/inventario

---

## PRIORIDAD DE IMPLEMENTACIÓN

### CRÍTICA (Afecta integridad de datos)

1. **Sincronización WC → APP** (Hallazgo #2)
   - Sin esto, los datos están SIEMPRE desincronizados
   - Overselling garantizado en multi-usuario
   - Afecta TODOS los casos de uso

### ALTA (Prevención de overselling)

2. **Borrador → WC como 'pending'** (Hallazgo #1)
   - Previene overselling en tiempo real
   - Necesario para múltiples vendedores
   - Mejora UX (usuario sabe si hay stock disponible)

---

## RECOMENDACIONES

### Implementación Inmediata

1. **Sincronización Bidireccional (Hallazgo #2)**
   - Implementar endpoints en plugin WP
   - Implementar sincronización en delta_sync_service.dart
   - Ejecutar cada 30 segundos cuando app está activa
   - Ejecutar al abrir la app

2. **Reserva de Stock en Borrador (Hallazgo #1)**
   - Enviar borrador a WC como status='pending'
   - Implementar timer de 5 minutos en app
   - Si se cancela/expira → Eliminar pedido 'pending' de WC
   - Si se completa → Actualizar status a 'completed'

### Arquitectura Propuesta

```
┌─────────────────────────────────────────────────────────────┐
│                    FLUJO BIDIRECCIONAL                       │
└─────────────────────────────────────────────────────────────┘

APP                              WooCommerce
 │                                    │
 │ 1. Guarda borrador                 │
 ├──────────────────────────────────► │
 │   POST /orders (status=pending)    │
 │                                    │
 │ 2. WC reserva stock 5 min          │
 │                                    │
 │ 3. Completa pedido                 │
 ├──────────────────────────────────► │
 │   PUT /orders/{id} (status=completed)
 │                                    │
 │                                    │ 4. Nuevo pedido desde Web
 │ 5. App consulta delta              │
 │ ◄────────────────────────────────┤
 │   GET /orders/delta                │
 │                                    │
 │ 6. App actualiza ObjectBox         │
 │    (resta stock localmente)        │
 │                                    │
```

---

## CONCLUSIÓN

**Estado Actual:**
- ✅ 90% de funcionalidades LOCAL implementadas correctamente
- ❌ Falta sincronización bidireccional crítica
- ❌ Falta reserva de stock en borradores

**Impacto:**
- **ALTO RIESGO** de overselling
- **ALTO RIESGO** de datos inconsistentes
- No apto para multi-usuario/multi-dispositivo

**Acción Requerida:**
Implementar URGENTEMENTE los 2 hallazgos para cumplir con especificación CSV.

---

**Última actualización:** 2025-12-12
**Responsable:** Claude Sonnet 4.5
**Estado:** ❌ DISCREPANCIAS CRÍTICAS ENCONTRADAS
