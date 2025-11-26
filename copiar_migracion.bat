@echo off
REM Script para copiar archivos de migración ObjectBox
REM Uso: copiar_migracion.bat [RUTA_PROYECTO_ORIGINAL]

SET ORIGEN=C:\Users\blocb\Myposmobile\my_pos_app
SET DESTINO=%1

IF "%DESTINO%"=="" (
    echo Error: Debes especificar la ruta del proyecto original
    echo Uso: copiar_migracion.bat C:\ruta\a\tu\proyecto
    exit /b 1
)

echo ========================================
echo COPIANDO MIGRACION OBJECTBOX
echo ========================================
echo.
echo Origen: %ORIGEN%
echo Destino: %DESTINO%
echo.

REM Crear backup
echo [1/7] Creando backup...
IF NOT EXIST "%DESTINO%\backup_pre_objectbox" (
    mkdir "%DESTINO%\backup_pre_objectbox"
    xcopy "%DESTINO%\lib" "%DESTINO%\backup_pre_objectbox\lib\" /E /I /Y
    xcopy "%DESTINO%\pubspec.yaml" "%DESTINO%\backup_pre_objectbox\" /Y
    echo     Backup creado en: %DESTINO%\backup_pre_objectbox
) ELSE (
    echo     Backup ya existe, saltando...
)
echo.

REM Copiar archivos nuevos de ObjectBox
echo [2/7] Copiando modelos ObjectBox...
xcopy "%ORIGEN%\lib\models\product_optimized.dart" "%DESTINO%\lib\models\" /Y
xcopy "%ORIGEN%\lib\models\order_compact.dart" "%DESTINO%\lib\models\" /Y
xcopy "%ORIGEN%\lib\models\inventory_movement_compact.dart" "%DESTINO%\lib\models\" /Y
xcopy "%ORIGEN%\lib\models\label_print_item_compact.dart" "%DESTINO%\lib\models\" /Y
xcopy "%ORIGEN%\lib\models\dictionaries.dart" "%DESTINO%\lib\models\" /Y
xcopy "%ORIGEN%\lib\models\shared_dictionaries.dart" "%DESTINO%\lib\models\" /Y
echo.

echo [3/7] Copiando servicios de conversión...
xcopy "%ORIGEN%\lib\services\database_service.dart" "%DESTINO%\lib\services\" /Y
xcopy "%ORIGEN%\lib\services\product_converter_service.dart" "%DESTINO%\lib\services\" /Y
xcopy "%ORIGEN%\lib\services\order_converter_service.dart" "%DESTINO%\lib\services\" /Y
xcopy "%ORIGEN%\lib\services\inventory_converter_service.dart" "%DESTINO%\lib\services\" /Y
xcopy "%ORIGEN%\lib\services\label_converter_service.dart" "%DESTINO%\lib\services\" /Y
echo.

echo [4/7] Copiando archivos modificados...
xcopy "%ORIGEN%\lib\services\storage_service.dart" "%DESTINO%\lib\services\" /Y
xcopy "%ORIGEN%\lib\repositories\order_repository.dart" "%DESTINO%\lib\repositories\" /Y
xcopy "%ORIGEN%\lib\repositories\inventory_repository.dart" "%DESTINO%\lib\repositories\" /Y
xcopy "%ORIGEN%\lib\providers\label_notifier.dart" "%DESTINO%\lib\providers\" /Y
xcopy "%ORIGEN%\lib\locator.dart" "%DESTINO%\lib\" /Y
echo.

echo [5/7] Copiando archivos generados de ObjectBox...
xcopy "%ORIGEN%\lib\objectbox.g.dart" "%DESTINO%\lib\" /Y
xcopy "%ORIGEN%\lib\objectbox-model.json" "%DESTINO%\lib\" /Y
echo.

echo [6/7] Copiando configuración Android...
xcopy "%ORIGEN%\android\app\build.gradle.kts" "%DESTINO%\android\app\" /Y
echo.

echo [7/7] Copiando documentación...
xcopy "%ORIGEN%\MIGRACION_OBJECTBOX_COMPLETADA.md" "%DESTINO%\" /Y
xcopy "%ORIGEN%\GUIA_PRUEBAS_OBJECTBOX.md" "%DESTINO%\" /Y
echo.

echo ========================================
echo MIGRACION COPIADA EXITOSAMENTE
echo ========================================
echo.
echo SIGUIENTES PASOS:
echo.
echo 1. Actualizar pubspec.yaml con dependencias ObjectBox
echo 2. Ejecutar: flutter pub get
echo 3. Ejecutar: flutter pub run build_runner build --delete-conflicting-outputs
echo 4. Probar la app: flutter run
echo.
echo Ver GUIA_PRUEBAS_OBJECTBOX.md para instrucciones detalladas
echo.

pause
