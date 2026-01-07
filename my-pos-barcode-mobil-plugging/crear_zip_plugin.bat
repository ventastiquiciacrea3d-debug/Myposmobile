@echo off
echo ========================================
echo Creando ZIP del plugin MY POS BARCODE MOBIL v3.3.0
echo ========================================
echo.

REM Eliminar ZIP anterior si existe
if exist my-pos-barcode-mobil.zip del /F /Q my-pos-barcode-mobil.zip

REM Crear archivo ZIP usando PowerShell
powershell -Command "Compress-Archive -Path '.\*' -DestinationPath '.\my-pos-barcode-mobil.zip' -CompressionLevel Optimal -Force"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo ✓ ZIP creado exitosamente
    echo ========================================
    echo.
    echo Archivo: my-pos-barcode-mobil.zip
    echo.
    echo Ahora puedes:
    echo 1. Subir este ZIP al admin de WordPress (Plugins - Anadir nuevo - Subir plugin^)
    echo 2. O descomprimir en wp-content/plugins/ via FTP
    echo.
) else (
    echo.
    echo ========================================
    echo ✗ Error al crear el ZIP
    echo ========================================
    echo.
)

pause
