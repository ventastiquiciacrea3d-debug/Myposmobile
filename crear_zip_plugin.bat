@echo off
echo Creando ZIP del plugin para WordPress...

cd /d "%~dp0"

REM Eliminar ZIP anterior si existe
if exist "my-pos-barcode-mobil-plugging.zip" (
    del /F /Q "my-pos-barcode-mobil-plugging.zip"
    echo ZIP anterior eliminado
)

REM Crear ZIP usando PowerShell (método compatible con WordPress)
powershell -Command "& {$ProgressPreference = 'SilentlyContinue'; Compress-Archive -Path 'my-pos-barcode-mobil-plugging' -DestinationPath 'my-pos-barcode-mobil-plugging.zip' -Force -ErrorAction Stop}"

if exist "my-pos-barcode-mobil-plugging.zip" (
    echo.
    echo ===================================
    echo  ZIP CREADO EXITOSAMENTE
    echo ===================================
    echo.
    echo Archivo: my-pos-barcode-mobil-plugging.zip
    echo.
    for %%A in ("my-pos-barcode-mobil-plugging.zip") do echo Tamano: %%~zA bytes
    echo.
    echo Ahora puedes subirlo a WordPress:
    echo 1. Ve a: Plugins - Anadir nuevo - Subir plugin
    echo 2. Selecciona: my-pos-barcode-mobil-plugging.zip
    echo 3. Instalar ahora
    echo 4. Reemplazar plugin actual
    echo 5. Activar plugin
    echo.
) else (
    echo.
    echo ===================================
    echo  ERROR AL CREAR ZIP
    echo ===================================
    echo.
    echo El archivo ZIP no se creo correctamente.
    echo Por favor intenta subirlo manualmente por FTP.
    echo.
)

pause
