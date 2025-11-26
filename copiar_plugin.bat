@echo off
echo Copiando plugin corregido a WordPress...
robocopy "C:\Users\blocb\Myposmobile\my-pos-barcode-mobil-plugging" "C:\xampp\htdocs\WEBWP\wp-content\plugins\my-pos-barcode-mobil" /MIR
echo.
echo Plugin copiado exitosamente.
echo Ahora puedes ir a tu WordPress y activar el plugin.
pause
