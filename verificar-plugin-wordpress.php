<?php
/**
 * Script de Verificación del Plugin MY POS BARCODE MOBIL
 *
 * INSTRUCCIONES:
 * 1. Sube este archivo a la raíz de tu sitio WordPress
 * 2. Accede a: https://tcrea3d.com/verificar-plugin-wordpress.php
 * 3. Lee el reporte completo
 * 4. Elimina este archivo después de usarlo (por seguridad)
 */

// Cargar WordPress
require_once(__DIR__ . '/wp-load.php');

// Verificar que somos admin
if (!current_user_can('manage_options')) {
    die('❌ Debes estar logueado como administrador');
}

header('Content-Type: text/html; charset=UTF-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>Verificación Plugin MY POS</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #f5f5f5; }
        .success { color: #28a745; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .section { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #007bff; }
        pre { background: #f8f9fa; padding: 10px; overflow-x: auto; }
        code { background: #e9ecef; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>🔍 Verificación del Plugin MY POS BARCODE MOBIL</h1>
    <p><strong>Fecha:</strong> <?php echo date('Y-m-d H:i:s'); ?></p>
    <hr>

    <div class="section">
        <h2>1️⃣ Verificación de Archivos</h2>
        <?php
        $plugin_dir = WP_PLUGIN_DIR . '/my-pos-barcode-mobil-plugging';
        $main_file = $plugin_dir . '/my-pos-barcode-mobil.php';
        $batch_file = $plugin_dir . '/includes/class-mpbm-batch-operations.php';

        echo "<p><strong>Directorio del plugin:</strong> <code>$plugin_dir</code></p>";

        if (is_dir($plugin_dir)) {
            echo "<p class='success'>✅ Directorio del plugin existe</p>";
        } else {
            echo "<p class='error'>❌ Directorio del plugin NO existe</p>";
            echo "<p>El plugin no está instalado correctamente.</p>";
            die('</div></body></html>');
        }

        if (file_exists($main_file)) {
            echo "<p class='success'>✅ Archivo principal existe</p>";
            $main_size = filesize($main_file);
            $main_mod = date('Y-m-d H:i:s', filemtime($main_file));
            echo "<p>Tamaño: " . number_format($main_size) . " bytes | Modificado: $main_mod</p>";
        } else {
            echo "<p class='error'>❌ Archivo principal NO existe</p>";
        }

        if (file_exists($batch_file)) {
            echo "<p class='success'>✅ Archivo batch-operations existe</p>";
            $batch_size = filesize($batch_file);
            $batch_mod = date('Y-m-d H:i:s', filemtime($batch_file));
            echo "<p>Tamaño: " . number_format($batch_size) . " bytes | Modificado: $batch_mod</p>";
        } else {
            echo "<p class='error'>❌ Archivo batch-operations NO existe</p>";
            echo "<p>Este es probablemente el problema. El archivo no se subió correctamente.</p>";
        }
        ?>
    </div>

    <div class="section">
        <h2>2️⃣ Verificación del Código</h2>
        <?php
        if (file_exists($main_file)) {
            $content = file_get_contents($main_file);

            if (strpos($content, 'class-mpbm-batch-operations.php') !== false) {
                echo "<p class='success'>✅ El include de batch-operations SÍ está en el código</p>";
            } else {
                echo "<p class='error'>❌ El include de batch-operations NO está en el código</p>";
                echo "<p>El plugin necesita ser actualizado.</p>";
            }

            if (strpos($content, 'MPBM_Batch_Operations_V2::get_instance()') !== false) {
                echo "<p class='success'>✅ La inicialización de batch-operations SÍ está en el código</p>";
            } else {
                echo "<p class='error'>❌ La inicialización de batch-operations NO está en el código</p>";
            }
        }
        ?>
    </div>

    <div class="section">
        <h2>3️⃣ Estado del Plugin en WordPress</h2>
        <?php
        if (!function_exists('get_plugins')) {
            require_once ABSPATH . 'wp-admin/includes/plugin.php';
        }

        $all_plugins = get_plugins();
        $plugin_key = 'my-pos-barcode-mobil-plugging/my-pos-barcode-mobil.php';

        if (isset($all_plugins[$plugin_key])) {
            echo "<p class='success'>✅ WordPress reconoce el plugin</p>";
            echo "<pre>" . print_r($all_plugins[$plugin_key], true) . "</pre>";

            if (is_plugin_active($plugin_key)) {
                echo "<p class='success'>✅ Plugin está ACTIVADO</p>";
            } else {
                echo "<p class='error'>❌ Plugin está DESACTIVADO</p>";
                echo "<p><strong>ACCIÓN:</strong> Ve a Plugins y actívalo.</p>";
            }
        } else {
            echo "<p class='error'>❌ WordPress NO reconoce el plugin</p>";
            echo "<p>Clave buscada: <code>$plugin_key</code></p>";
        }
        ?>
    </div>

    <div class="section">
        <h2>4️⃣ Verificación de Rutas REST API</h2>
        <?php
        $rest_server = rest_get_server();
        $routes = $rest_server->get_routes();

        $batch_stock_exists = isset($routes['/mypos/v1/batch/stock']);

        if ($batch_stock_exists) {
            echo "<p class='success'>✅ La ruta /mypos/v1/batch/stock EXISTE</p>";
            echo "<pre>" . print_r($routes['/mypos/v1/batch/stock'], true) . "</pre>";
        } else {
            echo "<p class='error'>❌ La ruta /mypos/v1/batch/stock NO EXISTE</p>";
            echo "<p><strong>PROBLEMA:</strong> El endpoint no se registró correctamente.</p>";

            echo "<h3>Posibles Causas:</h3>";
            echo "<ul>";
            echo "<li>El archivo class-mpbm-batch-operations.php no existe</li>";
            echo "<li>El plugin no está activado</li>";
            echo "<li>Hay un error de sintaxis en el archivo</li>";
            echo "<li>La función mpbm_permission_check_jwt no existe</li>";
            echo "</ul>";
        }

        echo "<h3>Otras rutas mypos disponibles:</h3>";
        echo "<ul>";
        foreach ($routes as $route => $handlers) {
            if (strpos($route, '/mypos/') !== false) {
                echo "<li><code>$route</code></li>";
            }
        }
        echo "</ul>";
        ?>
    </div>

    <div class="section">
        <h2>5️⃣ Verificación de Clases PHP</h2>
        <?php
        if (class_exists('MPBM_Batch_Operations_V2')) {
            echo "<p class='success'>✅ La clase MPBM_Batch_Operations_V2 está cargada</p>";

            $instance = MPBM_Batch_Operations_V2::get_instance();
            if ($instance) {
                echo "<p class='success'>✅ Se puede crear una instancia de la clase</p>";
            }
        } else {
            echo "<p class='error'>❌ La clase MPBM_Batch_Operations_V2 NO está cargada</p>";
            echo "<p><strong>PROBLEMA:</strong> El archivo no se está incluyendo correctamente.</p>";
        }
        ?>
    </div>

    <div class="section">
        <h2>6️⃣ Log de Errores de WordPress</h2>
        <?php
        if (defined('WP_DEBUG_LOG') && WP_DEBUG_LOG) {
            $log_file = WP_CONTENT_DIR . '/debug.log';
            if (file_exists($log_file)) {
                echo "<p class='success'>✅ Log de errores está habilitado</p>";
                echo "<p><strong>Ubicación:</strong> <code>$log_file</code></p>";

                $log_content = file_get_contents($log_file);
                $lines = explode("\n", $log_content);
                $recent_lines = array_slice($lines, -50); // Últimas 50 líneas

                echo "<h3>Últimas 50 líneas del log:</h3>";
                echo "<pre style='max-height: 300px; overflow-y: scroll;'>";
                foreach ($recent_lines as $line) {
                    if (stripos($line, 'mpbm') !== false || stripos($line, 'batch') !== false) {
                        echo "<strong>$line</strong>\n";
                    } else {
                        echo "$line\n";
                    }
                }
                echo "</pre>";
            } else {
                echo "<p class='warning'>⚠️ Log de errores no encontrado</p>";
            }
        } else {
            echo "<p class='warning'>⚠️ WP_DEBUG_LOG no está habilitado</p>";
            echo "<p>Para habilitar el log de errores, agrega esto a wp-config.php:</p>";
            echo "<pre>define('WP_DEBUG', true);\ndefine('WP_DEBUG_LOG', true);\ndefine('WP_DEBUG_DISPLAY', false);</pre>";
        }
        ?>
    </div>

    <div class="section">
        <h2>📋 Resumen y Recomendaciones</h2>
        <?php
        echo "<h3>Estado General:</h3>";

        $all_good = true;

        if (!file_exists($batch_file)) {
            echo "<p class='error'>❌ CRÍTICO: El archivo class-mpbm-batch-operations.php NO existe</p>";
            echo "<p><strong>SOLUCIÓN:</strong> Sube el plugin completo nuevamente.</p>";
            $all_good = false;
        }

        if (!is_plugin_active($plugin_key)) {
            echo "<p class='error'>❌ CRÍTICO: El plugin NO está activado</p>";
            echo "<p><strong>SOLUCIÓN:</strong> Ve a Plugins → Plugins instalados → MY POS BARCODE MOBIL → Activar</p>";
            $all_good = false;
        }

        if (!$batch_stock_exists) {
            echo "<p class='error'>❌ CRÍTICO: El endpoint /batch/stock NO está registrado</p>";
            echo "<p><strong>SOLUCIÓN:</strong> Desactiva y reactiva el plugin para forzar el registro de rutas.</p>";
            $all_good = false;
        }

        if ($all_good) {
            echo "<p class='success'>✅ TODO ESTÁ BIEN - El endpoint debería funcionar</p>";
            echo "<p>Si aún no funciona, revisa el log de errores arriba.</p>";
        }
        ?>
    </div>

    <hr>
    <p><strong>⚠️ IMPORTANTE:</strong> Elimina este archivo después de usarlo por seguridad.</p>
    <p><code>rm verificar-plugin-wordpress.php</code></p>
</body>
</html>
<?php
// Fin del script
?>
