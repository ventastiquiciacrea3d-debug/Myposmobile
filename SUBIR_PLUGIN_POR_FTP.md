# 🚀 SUBIR PLUGIN POR FTP - Método Más Confiable

## ❌ Problema: ZIP "Incompatible"

WordPress dice que el archivo es incompatible. Esto pasa cuando:
- El ZIP tiene archivos corruptos (como el archivo "nul")
- La estructura del ZIP no es correcta
- El tamaño es demasiado grande

## ✅ SOLUCIÓN: Subir Directamente por FTP

Este método **siempre funciona** y es más rápido.

---

## 📋 PASO A PASO (10 Minutos)

### PASO 1: Prepara tu Cliente FTP

Necesitas uno de estos programas (descarga si no tienes):
- **FileZilla** (recomendado, gratis)
- **WinSCP**
- **Cyberduck**

**Descargar FileZilla:**
https://filezilla-project.org/download.php?type=client

---

### PASO 2: Conecta a tu Servidor

**Datos de conexión** (deberías tenerlos):
```
Host: tcrea3d.com (o ftp.tcrea3d.com)
Usuario: [tu usuario FTP]
Contraseña: [tu contraseña FTP]
Puerto: 21 (o 22 si es SFTP)
```

**Si no tienes los datos:**
- Revisa el email de tu hosting
- O contacta a tu proveedor de hosting

---

### PASO 3: Navega a la Carpeta de Plugins

En el panel derecho de FileZilla, navega a:

```
/public_html/wp-content/plugins/
```

O si tu estructura es diferente:
```
/htdocs/wp-content/plugins/
/www/wp-content/plugins/
/wp-content/plugins/
```

---

### PASO 4: Respalda el Plugin Actual (Importante)

1. **Busca** la carpeta `my-pos-barcode-mobil-plugging`

2. **Clic derecho** sobre ella

3. **Descargar** - Esto la descarga como respaldo

4. **Espera** a que termine la descarga

---

### PASO 5: Elimina el Plugin Actual del Servidor

1. **IMPORTANTE:** Primero desactiva el plugin en WordPress:
   - Ve a: Plugins → Plugins instalados
   - Desactiva "MY POS BARCODE MOBIL"

2. **En FileZilla**, clic derecho sobre la carpeta:
   ```
   my-pos-barcode-mobil-plugging
   ```

3. **Eliminar** → Confirmar

4. **Espera** a que termine de eliminarse

---

### PASO 6: Sube la Carpeta Nueva

1. **En tu PC** (panel izquierdo de FileZilla), navega a:
   ```
   C:\Users\blocb\Myposmobile\
   ```

2. **Localiza** la carpeta:
   ```
   my-pos-barcode-mobil-plugging
   ```

3. **Arrastra** la carpeta completa al panel derecho (a `/wp-content/plugins/`)

4. **Espera** a que termine de subir TODOS los archivos
   - Esto puede tomar 2-5 minutos
   - Verás una barra de progreso abajo

5. **IMPORTANTE:** Asegúrate que dice "Transferencia finalizada" o "100%"

---

### PASO 7: Verifica que se Subió Correctamente

En FileZilla, abre la carpeta que acabas de subir:
```
/wp-content/plugins/my-pos-barcode-mobil-plugging/
```

**Verifica que ESTOS archivos existen:**
- ✅ `my-pos-barcode-mobil.php`
- ✅ `includes/class-mpbm-batch-operations.php` ← **ESTE ES CRÍTICO**
- ✅ `includes/api-endpoints.php`
- ✅ `assets/`
- ✅ `admin/`

**Si falta `class-mpbm-batch-operations.php`:**
- Sube manualmente solo ese archivo
- Está en: `C:\Users\blocb\Myposmobile\my-pos-barcode-mobil-plugging\includes\`
- Súbelo a: `/wp-content/plugins/my-pos-barcode-mobil-plugging/includes/`

---

### PASO 8: Activa el Plugin en WordPress

1. **Ve a WordPress Admin:**
   ```
   https://tcrea3d.com/wp-admin/plugins.php
   ```

2. **Busca** "MY POS BARCODE MOBIL"

3. **Clic en "Activar"**

4. **Espera** el mensaje de confirmación

---

### PASO 9: Verificar que Funcionó

Abre una terminal/PowerShell y ejecuta:

```bash
dart test_batch_endpoint.dart
```

**Resultado esperado:**
```
✅ SUCCESS: El endpoint existe y responde correctamente
📊 STATUS CODE: 200
```

**Si todavía da error 404:**
Ejecuta el script de diagnóstico (sigue las instrucciones anteriores)

---

## 🆘 PROBLEMAS COMUNES

### ❌ "No puedo conectarme por FTP"

**Solución:**
- Verifica que usas el puerto correcto (21 para FTP, 22 para SFTP)
- Intenta con el host alternativo: `ftp.tcrea3d.com`
- Contacta a tu hosting para obtener los datos correctos

---

### ❌ "No encuentro la carpeta wp-content/plugins"

**Solución:**
Tu estructura puede ser diferente. Busca:
```
/public_html/
/htdocs/
/www/
/web/
```

Dentro de alguna de esas debería estar `wp-content/plugins/`

---

### ❌ "La transferencia se interrumpe"

**Solución:**
- Revisa tu conexión a Internet
- Intenta subir menos archivos a la vez
- Usa "Transfer → Resume" en FileZilla si se corta

---

### ❌ "Subí todo pero sigue dando error 404"

**Solución:**
1. Desactiva el plugin en WordPress
2. Activa el plugin de nuevo
3. Esto fuerza a WordPress a re-registrar las rutas
4. Ejecuta el script de diagnóstico

---

## 📊 CHECKLIST DE VERIFICACIÓN

Después de subir, verifica TODOS estos puntos:

- [ ] La carpeta `my-pos-barcode-mobil-plugging` existe en `/wp-content/plugins/`
- [ ] El archivo `my-pos-barcode-mobil.php` existe en esa carpeta
- [ ] El archivo `includes/class-mpbm-batch-operations.php` **EXISTE** ← **CRÍTICO**
- [ ] El plugin está **ACTIVADO** en WordPress
- [ ] Ejecuté `dart test_batch_endpoint.dart` y vi SUCCESS
- [ ] Probé la app y ya no da error 404

---

## 🎯 VENTAJAS DE SUBIR POR FTP

1. ✅ **Más confiable** - No depende del límite de tamaño de WordPress
2. ✅ **Más rápido** - Subes directamente al servidor
3. ✅ **Más control** - Ves exactamente qué archivos se suben
4. ✅ **Sin restricciones** - No hay límites de tamaño o tipo de archivo
5. ✅ **Debugging fácil** - Puedes ver si faltan archivos

---

## 📞 ¿Necesitas Ayuda?

Si después de esto sigue sin funcionar:

1. Ejecuta el script de diagnóstico:
   ```
   https://tcrea3d.com/verificar-plugin-wordpress.php
   ```

2. Toma screenshot de los resultados

3. Avísame qué dice el script

---

**Tiempo estimado:** 10 minutos
**Dificultad:** Fácil
**Tasa de éxito:** 99%

---

Generated: 2025-12-09
Method: FTP Direct Upload (más confiable que ZIP)
