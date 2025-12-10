# 🚀 CÓMO SUBIR EL PLUGIN A WORDPRESS - PASO A PASO

## ✅ Archivo Listo para Subir

**Ubicación del archivo ZIP:**
```
C:\Users\blocb\Myposmobile\my-pos-barcode-mobil-plugging.zip
```

---

## 📤 PASOS PARA SUBIR A WORDPRESS

### Paso 1: Acceder a WordPress Admin

1. Abre tu navegador
2. Ve a: **https://tcrea3d.com/wp-admin**
3. Inicia sesión con tus credenciales

---

### Paso 2: Ir a la Sección de Plugins

1. En el menú lateral izquierdo, busca **"Plugins"**
2. Haz clic en **"Plugins"** → **"Añadir nuevo"**

---

### Paso 3: Subir el Plugin

1. En la parte superior de la página, verás un botón **"Subir plugin"**
2. Haz clic en **"Subir plugin"**
3. Se abrirá un formulario de carga

---

### Paso 4: Seleccionar el Archivo ZIP

1. Haz clic en **"Elegir archivo"** o **"Seleccionar archivo"**
2. Navega hasta: `C:\Users\blocb\Myposmobile\`
3. Selecciona el archivo: **my-pos-barcode-mobil-plugging.zip**
4. Haz clic en **"Abrir"**

---

### Paso 5: Instalar el Plugin

1. Haz clic en el botón **"Instalar ahora"**
2. WordPress te preguntará si quieres **reemplazar** el plugin existente
3. Haz clic en **"Reemplazar plugin actual"** o **"Sí, reemplazar"**
4. Espera a que termine la instalación (10-30 segundos)

---

### Paso 6: Activar el Plugin

1. Cuando termine la instalación, verás un mensaje de éxito
2. Haz clic en **"Activar plugin"**
3. ✅ ¡Listo! El plugin está actualizado

---

### Paso 7: Verificar que Funcionó (IMPORTANTE)

Después de activar el plugin, vuelve aquí y ejecuta este comando:

```bash
dart test_batch_endpoint.dart
```

**Deberías ver:**
```
✅ SUCCESS: El endpoint existe y responde correctamente
```

Si ves eso, **¡TODO FUNCIONÓ!** 🎉

---

## ⚠️ PROBLEMAS COMUNES

### Problema 1: "No tienes permisos para instalar plugins"

**Solución:**
- Necesitas ser **Administrador** de WordPress
- Pide ayuda al administrador del sitio

---

### Problema 2: "El archivo no es válido"

**Solución:**
- Asegúrate de seleccionar el archivo **my-pos-barcode-mobil-plugging.zip**
- NO descomprimas el archivo antes de subirlo
- Sube el archivo ZIP tal como está

---

### Problema 3: "Error al reemplazar el plugin"

**Solución:**
1. Primero **desactiva** el plugin antiguo:
   - Plugins → Plugins instalados
   - Busca "MY POS BARCODE MOBIL"
   - Clic en "Desactivar"
2. Luego **elimina** el plugin antiguo:
   - Clic en "Eliminar"
3. Ahora sube el nuevo plugin siguiendo los pasos anteriores

---

### Problema 4: WordPress no muestra el botón "Subir plugin"

**Solución:**
- Tu WordPress puede tener restringida esta función
- Usa **Opción B** (ver abajo)

---

## 🔄 OPCIÓN B: Subir por FTP (Si Opción A no funciona)

### 1. Descomprimir el ZIP
- Clic derecho en `my-pos-barcode-mobil-plugging.zip`
- Seleccionar "Extraer aquí" o "Descomprimir"

### 2. Conectarse por FTP
- Abre FileZilla (o tu cliente FTP)
- Conecta a: `tcrea3d.com`

### 3. Ir a la carpeta de plugins
```
/wp-content/plugins/
```

### 4. Eliminar el plugin viejo
- Busca la carpeta: `my-pos-barcode-mobil-plugging`
- Clic derecho → Eliminar

### 5. Subir el plugin nuevo
- Arrastra la carpeta descomprimida `my-pos-barcode-mobil-plugging`
- Espera a que termine de subir todos los archivos

### 6. Activar en WordPress
- Ve a: Plugins → Plugins instalados
- Busca "MY POS BARCODE MOBIL"
- Clic en "Activar"

---

## ✅ CHECKLIST FINAL

Después de subir el plugin, verifica:

- [ ] El plugin está **activado** en WordPress
- [ ] No hay errores en la página de plugins
- [ ] Ejecutaste `dart test_batch_endpoint.dart` y viste **SUCCESS**
- [ ] La app Flutter puede hacer ajustes de inventario sin error 404

---

## 🆘 ¿Necesitas Ayuda?

Si algo no funciona:

1. Toma una captura de pantalla del error
2. Dime en qué paso te quedaste atascado
3. Te ayudaré a resolverlo

---

**¡Empieza con el Paso 1 y avísame cuando termines!** 👍
