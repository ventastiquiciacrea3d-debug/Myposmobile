# 📋 GUÍA DE PRUEBAS - MIGRACIÓN OBJECTBOX

**Fecha:** 18 de Noviembre, 2025
**Versión:** 1.0
**Estado:** Listo para pruebas funcionales

## ✅ Verificaciones Pre-Inicio

### 1. Compilación
- [x] **APK compilado exitosamente** - `build/app/outputs/flutter-apk/app-debug.apk` (237 MB)
- [x] **0 errores de compilación**
- [x] **183 advertencias** (solo linter, no bloquean)

### 2. Servicios Inicializados
- [x] **DatabaseService** registrado en locator.dart (línea 80-83)
- [x] **StorageService** inicializa ObjectBox + converters (storage_service.dart:50-72)
- [x] **InventoryRepository** inicializa converter (inventory_repository.dart:53)
- [x] **LabelNotifier** inicializa converter (label_notifier.dart:59)

### 3. Arquitectura
```
ESCRITURA: ObjectBox (principal) → Hive (backup)
LECTURA: ObjectBox → fallback a Hive si falla
```

## 🧪 PLAN DE PRUEBAS

### NIVEL 1: Inicialización (CRÍTICO)

**Objetivo:** Verificar que la app inicie sin crashes

#### Paso 1.1: Primera Ejecución
```bash
cd my_pos_app
flutter run
```

**✅ Éxito esperado:**
- App muestra splash screen
- No hay errores en consola
- Llega a pantalla principal

**❌ Fallo esperado:**
- Crash inmediato → Ver logs de DatabaseService
- Error "Box not found" → Problema inicialización ObjectBox
- Error "Converter null" → Problema inicialización converters

**Logs a verificar:**
```
[StorageService] init: Initializing ObjectBox and Hive...
[StorageService] init: ObjectBox + Hive initialized.
[DatabaseService] getInstance: ObjectBox initialized at [path]
```

---

### NIVEL 2: Búsqueda de Productos (ALTA PRIORIDAD)

**Objetivo:** Verificar que búsquedas usen ObjectBox

#### Paso 2.1: Búsqueda por Código de Barras
1. Ir a pantalla Scanner
2. Escanear un código de barras conocido
3. Verificar que encuentra el producto

**✅ Éxito esperado:**
- Producto encontrado en <10ms
- Muestra información correcta

**❌ Fallo esperado:**
- Producto no encontrado → Datos no están en ObjectBox
- App crash → Error en ProductConverterService
- Datos incorrectos → Error conversión optimizedToProduct()

**Método probado:** `getCachedProductByBarcode()`

#### Paso 2.2: Búsqueda por SKU
1. Ir a pantalla de productos
2. Buscar producto por SKU
3. Verificar resultado

**Método probado:** `getProductBySku()`

#### Paso 2.3: Búsqueda por Nombre
1. Escribir nombre parcial de producto
2. Verificar que aparece en resultados

**Método probado:** `searchLocalProductsByNameOrSku()`

---

### NIVEL 3: Gestión de Órdenes (ALTA PRIORIDAD)

**Objetivo:** Verificar que órdenes se guarden en ObjectBox

#### Paso 3.1: Crear Orden Nueva
1. Ir a pantalla de órdenes
2. Agregar productos al carrito
3. Crear orden (modo offline para forzar pending)
4. Verificar que se guarda

**✅ Éxito esperado:**
- Orden aparece en lista de pendientes
- localOrderId generado correctamente
- Items guardados como JSON comprimido

**❌ Fallo esperado:**
- Orden no aparece → Error savePendingOrder()
- Crash al guardar → Error OrderConverterService
- Items vacíos → Error conversión itemsJson

**Métodos probados:**
- `savePendingOrder()`
- `getPendingOrders()`

#### Paso 3.2: Ver Órdenes Completadas
1. Ir a historial de órdenes
2. Verificar que carga lista

**Métodos probados:**
- `getCompletedOrders()`
- `getCompletedOrderById()`

---

### NIVEL 4: Movimientos de Inventario (MEDIA PRIORIDAD)

**Objetivo:** Verificar ajustes de inventario

#### Paso 4.1: Crear Ajuste de Inventario
1. Ir a pantalla de inventario
2. Crear ajuste manual
3. Guardar

**✅ Éxito esperado:**
- Movimiento guardado en ObjectBox
- Tipo de movimiento correcto (enum)
- Items en JSON comprimido

**❌ Fallo esperado:**
- No se guarda → Error saveInventoryMovement()
- Tipo incorrecto → Error parseMovementType()

**Métodos probados:**
- `saveInventoryMovement()`

---

### NIVEL 5: Impresión de Etiquetas (BAJA PRIORIDAD)

**Objetivo:** Verificar cola de impresión

#### Paso 5.1: Agregar Etiqueta a Cola
1. Seleccionar producto
2. Agregar a cola de impresión
3. Verificar que aparece en cola

**Métodos probados:**
- `saveQueue()` (label_notifier.dart)
- `_loadSettingsAndQueue()`

---

## 🔍 PUNTOS DE VERIFICACIÓN EN LOGS

### Logs de Éxito (ObjectBox funcionando)

```
[StorageService.getProductById] ✅ Found product in ObjectBox
[StorageService.savePendingOrder] ✅ Saved pending order local_xxx to ObjectBox
[InventoryRepository.saveInventoryMovement] ✅ Saved to ObjectBox
```

### Logs de Fallback (Usando Hive)

```
[StorageService.getProductById] ⚠️ ObjectBox error, falling back to Hive
[StorageService] Error: [detalle del error]
```

**IMPORTANTE:** Si ves muchos fallbacks, significa que ObjectBox no está funcionando correctamente.

---

## ⚠️ PROBLEMAS POTENCIALES Y SOLUCIONES

### Problema 1: App crashea al iniciar

**Síntoma:**
```
[ERROR:flutter/runtime/dart_vm_initializer.cc] Unhandled Exception
DatabaseService initialization failed
```

**Causa:** ObjectBox no puede crear el directorio o el archivo de BD

**Solución:**
```bash
# Limpiar datos de la app
flutter clean
rm -rf my_pos_app/objectbox-data

# Reinstalar
flutter run
```

---

### Problema 2: Productos no se encuentran

**Síntoma:**
- Búsqueda por barcode retorna null
- Logs muestran fallback a Hive

**Causa:** Datos solo existen en Hive, no migrados a ObjectBox

**Solución:**
- Esperar hasta que se sincronicen nuevos productos
- O ejecutar migración de datos (ver Fase 2 en documento principal)

---

### Problema 3: Órdenes con datos incorrectos

**Síntoma:**
- Items vacíos en orden
- Precios en 0
- Atributos de variaciones perdidos

**Causa:** Error en conversión Order → OrderCompact

**Solución:**
1. Verificar logs de conversión
2. Revisar OrderConverterService.orderToCompact()
3. Verificar que attributes se convierten bien (List<Map> → Map)

---

### Problema 4: Movimientos de inventario con tipo incorrecto

**Síntoma:**
- Tipo aparece como "unknown"
- Enum no se reconoce

**Causa:** Error parseando InventoryMovementType

**Solución:**
1. Verificar InventoryMovementCompact.parseMovementType()
2. Asegurar que enum.toString().split('.').last funciona

---

## 📊 MÉTRICAS A OBSERVAR

### Performance (Esperado con ObjectBox)

| Operación | Tiempo Esperado | Hive (Legacy) |
|-----------|-----------------|---------------|
| Búsqueda por barcode | <10ms | ~300ms |
| Búsqueda por SKU | <10ms | ~250ms |
| Búsqueda por nombre | <50ms | ~400ms |
| Guardar orden | <20ms | ~150ms |
| Cargar historial (20 órdenes) | <30ms | ~200ms |

**Cómo medir:**
- Los logs de debug muestran tiempos en milisegundos
- Buscar en logs: `[...] completed in XXms`

### Almacenamiento (Esperado con ObjectBox)

**Antes de pruebas:**
```bash
du -sh my_pos_app/objectbox-data
```

**Después de agregar 1000 productos:**
- ObjectBox: ~120 KB
- Hive (legacy): ~5.1 MB

**Reducción esperada:** 97%

---

## 🚨 CRITERIOS DE FALLO CRÍTICO

**Si ocurre alguno de estos, DETENER pruebas:**

1. ❌ **App crashea constantemente** (>3 crashes en 10 minutos)
2. ❌ **Datos se pierden** (órdenes desaparecen, stock incorrecto)
3. ❌ **100% fallback a Hive** (ObjectBox nunca se usa)
4. ❌ **Sincronización falla** (no sube órdenes a WooCommerce)

En estos casos, reportar logs completos para análisis.

---

## ✅ CRITERIOS DE ÉXITO

**Prueba exitosa si:**

1. ✅ App inicia sin crashes
2. ✅ Búsquedas funcionan (al menos 80% usando ObjectBox)
3. ✅ Órdenes se crean y guardan correctamente
4. ✅ No hay pérdida de datos
5. ✅ Performance mejora vs. versión anterior
6. ✅ Fallback a Hive funciona cuando ObjectBox falla

---

## 📝 REPORTE DE RESULTADOS

Después de probar, documenta:

**FUNCIONA ✅:**
- [ ] Inicialización
- [ ] Búsqueda por barcode
- [ ] Búsqueda por SKU
- [ ] Búsqueda por nombre
- [ ] Crear orden pendiente
- [ ] Ver historial de órdenes
- [ ] Movimientos de inventario
- [ ] Cola de impresión

**FALLA ❌:**
- [ ] [Describe el problema]
- [ ] [Logs relevantes]

**PERFORMANCE:**
- Búsqueda por barcode: ___ms (esperado <10ms)
- Guardar orden: ___ms (esperado <20ms)
- Cargar historial: ___ms (esperado <30ms)

**FALLBACKS:**
- Total operaciones: ___
- Éxitos ObjectBox: ___
- Fallbacks a Hive: ___
- % éxito ObjectBox: ___% (esperado >80%)

---

## 🔧 COMANDOS ÚTILES

### Ver logs en tiempo real
```bash
# Android
adb logcat | grep -E "(StorageService|DatabaseService|OrderRepository|InventoryRepository)"

# Flutter
flutter run --verbose
```

### Limpiar ObjectBox
```bash
rm -rf my_pos_app/objectbox-data
flutter clean
flutter run
```

### Verificar tamaño de BD
```bash
# Tamaño ObjectBox
du -sh my_pos_app/objectbox-data

# Tamaño Hive
du -sh my_pos_app/hive-data
```

---

## 📞 SOPORTE

Si encuentras problemas, reporta:

1. **Descripción del error**
2. **Logs completos** (últimos 100 líneas)
3. **Pasos para reproducir**
4. **Versión del sistema** (Android/iOS)
5. **Datos de prueba** (cantidad de productos, órdenes, etc.)

---

**Última actualización:** 18/11/2025
**Autor:** Claude Code
**Versión documento:** 1.0
