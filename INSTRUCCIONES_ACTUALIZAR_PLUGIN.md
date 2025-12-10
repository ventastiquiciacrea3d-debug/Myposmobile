# 🔧 INSTRUCCIONES: Actualizar Plugin WordPress

## ❌ Problema Actual
El endpoint `/batch/stock` no existe en el servidor porque el archivo `class-mpbm-batch-operations.php` no está siendo cargado.

## ✅ Solución: Actualizar el Plugin en WordPress

### OPCIÓN A: Actualizar por FTP/SFTP (Recomendado)

1. **Conectarse al servidor:**
   - Abre tu cliente FTP (FileZilla, WinSCP, etc.)
   - Conéctate a: `tcrea3d.com`

2. **Localizar el archivo:**
   ```
   /wp-content/plugins/my-pos-barcode-mobil-plugging/my-pos-barcode-mobil.php
   ```

3. **Descargar el archivo como backup:**
   - Descarga `my-pos-barcode-mobil.php` a tu computadora (como respaldo)

4. **Editar el archivo:**
   - Abre el archivo en un editor de texto
   - Busca la línea (aproximadamente línea 66):
   ```php
   require_once MPBM_PLUGIN_PATH . 'includes/product-change-hooks.php';
   ```

5. **Agregar estas 3 líneas DESPUÉS de esa línea:**
   ```php
   // ✅ BATCH OPERATIONS: Operaciones en lote para stock, precios y órdenes
   require_once MPBM_PLUGIN_PATH . 'includes/class-mpbm-batch-operations.php';
   MPBM_Batch_Operations_V2::get_instance();
   ```

6. **Guardar y subir:**
   - Guarda el archivo
   - Sube el archivo modificado al servidor (sobrescribir el existente)

7. **Reactivar el plugin en WordPress:**
   - Entra a WordPress Admin
   - Ve a: Plugins → Plugins Instalados
   - Busca "MY POS BARCODE MOBIL"
   - Desactívalo y vuelve a activarlo

---

### OPCIÓN B: Subir Plugin Completo desde Aquí

1. **Comprimir la carpeta del plugin:**
   - Ve a: `C:\Users\blocb\Myposmobile\my-pos-barcode-mobil-plugging\`
   - Selecciona TODOS los archivos dentro de esta carpeta
   - Clic derecho → Enviar a → Carpeta comprimida
   - Nombra el archivo: `my-pos-barcode-mobil-plugging.zip`

2. **Subir a WordPress:**
   - Entra a WordPress Admin
   - Ve a: Plugins → Añadir nuevo → Subir plugin
   - Selecciona el archivo ZIP que creaste
   - Clic en "Instalar ahora"
   - Reemplaza el plugin existente cuando te lo pregunte

3. **Activar el plugin:**
   - Clic en "Activar plugin"

---

### OPCIÓN C: Usar Editor de WordPress (No Recomendado)

1. **Acceder al editor:**
   - WordPress Admin → Herramientas → Editor de archivos de temas y plugins
   - ⚠️ ADVERTENCIA: Si WordPress tiene el editor deshabilitado, usa Opción A o B

2. **Editar el archivo:**
   - Selecciona el plugin "MY POS BARCODE MOBIL"
   - Busca el archivo `my-pos-barcode-mobil.php`
   - Agrega las 3 líneas mencionadas arriba

---

## 🧪 Verificar que Funcionó

Después de actualizar el plugin, ejecuta este comando en tu computadora:

```bash
dart test_batch_endpoint.dart
```

**Resultado esperado:**
```
✅ SUCCESS: El endpoint existe y responde correctamente
```

**Si ves esto, significa que todo funciona:**
```
📊 STATUS CODE: 200
✅ SUCCESS: El endpoint existe y responde correctamente
```

---

## 📋 Contenido Exacto a Agregar

Copia y pega exactamente esto en el archivo `my-pos-barcode-mobil.php`:

```php
    // 🟢 NUEVO: Hooks mejorados para detectar TODOS los cambios de inventario
    require_once MPBM_PLUGIN_PATH . 'includes/product-change-hooks.php';

    // ✅ BATCH OPERATIONS: Operaciones en lote para stock, precios y órdenes
    require_once MPBM_PLUGIN_PATH . 'includes/class-mpbm-batch-operations.php';
    MPBM_Batch_Operations_V2::get_instance();

    new MPBM_Ajax_Handler();
    new MPBM_Inventory_Logger();
```

---

## 🆘 Si Nada Funciona

Si ninguna de estas opciones funciona, puedes:

1. **Verificar que el archivo existe:**
   - Conéctate por FTP/SFTP
   - Verifica que existe: `/wp-content/plugins/my-pos-barcode-mobil-plugging/includes/class-mpbm-batch-operations.php`
   - Si NO existe, necesitas subir ese archivo al servidor

2. **Revisar los logs de WordPress:**
   - Activa el modo debug de WordPress
   - Revisa los logs en: `/wp-content/debug.log`

3. **Contactar al administrador del servidor:**
   - Si tienes restricciones de permisos, contacta al admin del servidor

---

## 📞 Información de Contacto del Servidor

- **URL:** tcrea3d.com
- **Plugin Path:** `/wp-content/plugins/my-pos-barcode-mobil-plugging/`
- **Archivo a editar:** `my-pos-barcode-mobil.php`
- **Línea aproximada:** 66-70

---

¿Necesitas ayuda adicional? Dime cuál opción vas a usar y te ayudo paso a paso.
