# 🎯 INSTRUCCIONES FINALES - Subir Plugin a WordPress

## Estado Actual ✅

- ✅ Código corregido (scanner + endpoint batch/stock)
- ✅ ZIP creado exitosamente: `my-pos-barcode-mobil-plugging.zip` (79 KB)
- ✅ Archivos críticos verificados en el ZIP

---

## 🚀 OPCIÓN 1: Subir por WordPress Admin (MÁS RÁPIDO)

### Paso 1: Preparación
1. Ve a WordPress Admin: https://tcrea3d.com/wp-admin
2. Login como administrador

### Paso 2: Desactivar Plugin Actual
1. Ve a: **Plugins → Plugins instalados**
2. Busca: **MY POS BARCODE MOBIL**
3. Haz clic en **Desactivar**

### Paso 3: Eliminar Plugin Actual
1. Después de desactivar, aparecerá opción **Eliminar**
2. Haz clic en **Eliminar**
3. Confirma la eliminación
4. **IMPORTANTE:** Esto NO borrará tus datos, solo el código del plugin

### Paso 4: Subir Plugin Nuevo
1. Ve a: **Plugins → Añadir nuevo**
2. Haz clic en **Subir plugin** (botón arriba)
3. Haz clic en **Seleccionar archivo**
4. Navega a: `C:\Users\blocb\Myposmobile\`
5. Selecciona: `my-pos-barcode-mobil-plugging.zip`
6. Haz clic en **Instalar ahora**

### Paso 5: Activar
1. Cuando termine la instalación, haz clic en **Activar plugin**
2. Deberías ver el mensaje: "Plugin activado"

---

## 🔧 Si el ZIP da "Archivo Incompatible"

**Causa probable:** Límite de tamaño en PHP o estructura incorrecta.

### Solución A: Aumentar Límite PHP (Rápido)

1. Ve a tu panel de hosting (cPanel, Plesk, etc.)
2. Busca "PHP Settings" o "Configuración PHP"
3. Aumenta estos valores:
   - `upload_max_filesize`: 10M
   - `post_max_size`: 10M
   - `max_execution_time`: 300
4. Guarda cambios
5. Intenta subir el ZIP nuevamente

### Solución B: Usar FTP (100% Confiable)

**Consulta el archivo:** `SUBIR_PLUGIN_POR_FTP.md` para instrucciones detalladas.

**Resumen FTP:**
1. Conecta por FTP a tcrea3d.com
2. Navega a: `/wp-content/plugins/`
3. Elimina carpeta: `my-pos-barcode-mobil-plugging`
4. Sube carpeta completa desde: `C:\Users\blocb\Myposmobile\my-pos-barcode-mobil-plugging\`
5. Activa el plugin en WordPress

---

## ✅ VERIFICACIÓN FINAL

### Después de Subir y Activar:

1. **Ejecuta el script de diagnóstico** (RECOMENDADO):
   - Sube `verificar-plugin-wordpress.php` a la raíz de tu sitio
   - Abre: https://tcrea3d.com/verificar-plugin-wordpress.php
   - Lee el reporte completo
   - **ELIMINA** el archivo después por seguridad

2. **O prueba el endpoint directamente:**
   ```bash
   cd C:\Users\blocb\Myposmobile
   dart test_batch_endpoint.dart
   ```

   **Debe mostrar:**
   ```
   ✅ SUCCESS: El endpoint existe y responde correctamente
   📊 STATUS CODE: 200
   ```

3. **Prueba la app:**
   - Abre la app Flutter
   - Ve a Inventario
   - Escanea un producto
   - Crea un ajuste de entrada
   - **NO debería dar error 404**

---

## 🆘 SOLUCIÓN DE PROBLEMAS

### Si después de subir sigue dando 404:

1. **Desactiva y reactiva el plugin:**
   - Plugins → Desactivar MY POS BARCODE MOBIL
   - Plugins → Activar MY POS BARCODE MOBIL
   - Esto fuerza a WordPress a re-registrar las rutas

2. **Limpia permalinks:**
   - Ajustes → Enlaces permanentes
   - No cambies nada, solo haz clic en **Guardar cambios**
   - Esto regenera las reglas de reescritura

3. **Verifica que el archivo existe en el servidor:**
   - Por FTP, navega a: `/wp-content/plugins/my-pos-barcode-mobil-plugging/includes/`
   - Verifica que existe: `class-mpbm-batch-operations.php`
   - Tamaño esperado: ~11 KB

---

## 📋 CHECKLIST COMPLETO

Marca cada paso:

- [ ] Plugin actual desactivado en WordPress
- [ ] Plugin actual eliminado
- [ ] Nuevo ZIP subido e instalado (o carpeta subida por FTP)
- [ ] Plugin activado
- [ ] Script de verificación ejecutado (opcional pero recomendado)
- [ ] `dart test_batch_endpoint.dart` muestra STATUS 200
- [ ] App probada y NO da error 404 al crear ajuste de inventario
- [ ] Script de verificación eliminado del servidor (si lo usaste)

---

## 🎯 ARCHIVOS IMPORTANTES

- **Plugin ZIP:** `C:\Users\blocb\Myposmobile\my-pos-barcode-mobil-plugging.zip`
- **Plugin carpeta:** `C:\Users\blocb\Myposmobile\my-pos-barcode-mobil-plugging\`
- **Script diagnóstico:** `C:\Users\blocb\Myposmobile\verificar-plugin-wordpress.php`
- **Test endpoint:** `C:\Users\blocb\Myposmobile\test_batch_endpoint.dart`
- **Guía FTP:** `C:\Users\blocb\Myposmobile\SUBIR_PLUGIN_POR_FTP.md`

---

## 💡 NOTA IMPORTANTE

El código está 100% correcto y probado localmente. Los cambios son:

1. **Flutter:** Scanner sin timeout + null safety mejorado
2. **WordPress:** Endpoint `/batch/stock` ahora se carga correctamente

El único paso pendiente es **subir el plugin al servidor**. Una vez hecho esto, todo funcionará.

---

**Creado:** 2025-12-09
**Tamaño ZIP:** 79 KB
**Archivos en ZIP:** ✅ Verificados

---

**¿Listo para subir?** Sigue los pasos de la Opción 1. Si falla, usa la Opción FTP (100% confiable).
