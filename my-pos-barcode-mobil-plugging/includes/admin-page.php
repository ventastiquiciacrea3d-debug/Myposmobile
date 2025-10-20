<?php
if (!defined('WPINC')) { die; }

add_action('admin_menu', 'mpbm_add_admin_menu');
function mpbm_add_admin_menu() {
    add_menu_page('MY POS BARCODE MOBIL', 'POS Mobil App', 'manage_options', 'my-pos-barcode-mobil', 'mpbm_admin_page_html', 'dashicons-smartphone', 25);
}

function mpbm_handle_save_settings() {
    if (isset($_POST['mpbm_save_settings_nonce']) && wp_verify_nonce($_POST['mpbm_save_settings_nonce'], 'mpbm_save_action')) {
        if (current_user_can('manage_options')) {
            update_option('mpbm_cache_duration', intval($_POST['cache_duration']) > 0 ? intval($_POST['cache_duration']) : 60);
            if (isset($_POST['barcode_type'])) {
                update_option('mpbm_barcode_type', sanitize_text_field($_POST['barcode_type']));
            }
            add_action('admin_notices', function() {
                echo '<div class="notice notice-success is-dismissible"><p>Ajustes guardados.</p></div>';
            });
        }
    }
}

function mpbm_admin_page_html() {
    mpbm_handle_save_settings();
    
    // Mover la lógica de notificaciones aquí para que se muestren siempre
    if (isset($_GET['mpbm_success'])) {
        $count = intval($_GET['mpbm_success']);
        add_action('admin_notices', function() use ($count) {
            echo '<div class="notice notice-success is-dismissible"><p>' . sprintf(esc_html__('Se actualizaron %d productos correctamente.', 'my-pos-barcode-mobil'), $count) . '</p></div>';
        });
    }
    if (isset($_GET['mpbm_error'])) {
        $error_code = sanitize_key($_GET['mpbm_error']);
        $error_messages = ['no_data' => 'No se encontraron datos de importación para confirmar.'];
        $message = isset($error_messages[$error_code]) ? $error_messages[$error_code] : 'Ha ocurrido un error desconocido durante la confirmación.';
        add_action('admin_notices', function() use ($message) {
             echo '<div class="notice notice-error is-dismissible"><p>' . esc_html($message) . '</p></div>';
        });
    }

    $api_key = get_option('mpbm_api_key', false);
    if ($api_key === false) { 
        $api_key = wp_generate_uuid4();
        update_option('mpbm_api_key', $api_key); 
    }
    $cache_duration = get_option('mpbm_cache_duration', 60);
    $devices = get_option('mpbm_devices', []);
    $barcode_type = get_option('mpbm_barcode_type', 'CODE128');
    $barcode_types = ['CODE128' => 'Code 128 (Recomendado)', 'EAN13' => 'EAN-13', 'UPC' => 'UPC-A', 'CODE39' => 'Code 39'];
    ?>
    <div class="wrap mpbm-wrap">
        <div class="mpbm-header">
            <div class="mpbm-header-icon"><span class="dashicons dashicons-smartphone"></span></div>
            <div>
                <h1><?php echo esc_html(get_admin_page_title()); ?></h1>
                <p class="mpbm-subtitle">Configuración de conexión para la aplicación móvil y herramientas de inventario.</p>
            </div>
        </div>

        <?php do_action('admin_notices'); ?>

        <nav class="nav-tab-wrapper">
            <a href="#tab-conexion" class="nav-tab">Conexión App</a>
            <a href="#tab-herramientas" class="nav-tab">Herramientas</a>
            <a href="#tab-importar-exportar" class="nav-tab">Importar/Exportar</a>
            <a href="#tab-historial-inventario" class="nav-tab">Historial de Inventario</a>
            <a href="#tab-ayuda" class="nav-tab">Ayuda y Dispositivos</a>
        </nav>

        <div class="mpbm-tab-content" id="tab-importar-exportar">
            <div class="mpbm-grid">
                <div class="mpbm-card" id="export-card">
                    <h2>Exportar Inventario</h2>
                    <p>Descarga un archivo CSV con tu inventario actual para realizar un conteo físico o tener una copia de seguridad.</p>
                    <div id="export-controls">
                        <button id="prepare-export-btn" class="button button-secondary">
                            <span class="dashicons dashicons-update-alt"></span>
                            Paso 1: Recopilar Productos
                        </button>
                        <a href="#" id="download-export-btn" class="button button-primary disabled" style="display:none;">
                            <span class="dashicons dashicons-download"></span>
                            Paso 2: Descargar Archivo
                        </a>
                        <div id="export-feedback" style="margin-top: 10px;"></div>
                    </div>
                </div>
                 <div class="mpbm-card">
                    <h2>Importar Ajuste de Stock</h2>
                    <p>Actualiza el stock masivamente subiendo un archivo CSV. El sistema detectará automáticamente la operación (Conteo o Añadir) por cada fila.</p>
                    
                    <form id="mpbm-import-form" method="POST" enctype="multipart/form-data">
                        <?php wp_nonce_field('mpbm_import_inventory_nonce', 'mpbm_import_nonce'); ?>
                        
                        <p><label for="mpbm_csv_file">Selecciona el archivo CSV:</label><br>
                        <input type="file" id="mpbm_csv_file" name="mpbm_csv_file" accept=".csv"></p>
                        
                        <p><button type="submit" class="button button-primary">
                            <span class="dashicons dashicons-upload"></span>
                            Subir y Previsualizar Ajuste
                        </button></p>
                    </form>
                     <a href="<?php echo esc_url(admin_url('admin-post.php?action=mpbm_download_template&nonce=' . wp_create_nonce('mpbm_template_nonce'))); ?>" class="button button-secondary">
                        <span class="dashicons dashicons-media-text"></span>
                        Descargar Plantilla
                    </a>
                </div>
            </div>
            
            <div id="mpbm-import-feedback" style="margin-top: 20px;"></div>
            <div id="mpbm-import-preview-container" style="margin-top: 20px;">
                </div>
        </div>

        <div class="mpbm-tab-content" id="tab-conexion">
             <div class="mpbm-card">
                <h2>Vincular un Nuevo Dispositivo</h2>
                <p>Sigue estos pasos para conectar un nuevo teléfono o scanner a tu tienda.</p>
                <div class="mpbm-grid">
                    <div>
                        <label for="device_name">Paso 1: Nombra tu dispositivo</label>
                        <input type="text" id="device_name" placeholder="Ej: Caja 1, Scanner Bodega" class="regular-text"/>
                        <button id="generate-qr-btn" class="button button-primary button-large">Paso 2: Generar QR de Vinculación</button>
                    </div>
                    <div id="qr-code-container" class="mpbm-qr-container"><p>El QR aparecerá aquí.</p></div>
                </div>
            </div>
             <div class="mpbm-card">
                    <h2>Ajustes Generales de Conexión</h2>
                    <form method="POST" action="">
                        <?php wp_nonce_field('mpbm_save_action', 'mpbm_save_settings_nonce'); ?>
                        <h3 class="title">Clave de API</h3>
                        <div class="mpbm-api-key-wrapper">
                            <input type="text" id="api_key_field" value="<?php echo esc_attr($api_key); ?>" readonly class="regular-text"/>
                            <button type="button" id="copy-api-key-btn" class="button">Copiar</button>
                        </div>
                        <button type="button" id="regenerate-api-key-btn" class="button button-secondary">Generar Nueva Clave de API</button>
                        <hr>
                        <h3 class="title">Caché</h3>
                        <label for="cache_duration">Duración del caché de búsqueda (en minutos)</label>
                        <input type="number" id="cache_duration" name="cache_duration" value="<?php echo esc_attr($cache_duration); ?>" class="small-text"/>
                        <p><button type="submit" class="button button-primary">Guardar Ajustes</button></p>
                    </form>
                </div>
        </div>
        <div class="mpbm-tab-content" id="tab-herramientas">
             <div class="mpbm-card">
                <h2>Gestión de Productos</h2>
                <p>Herramientas para analizar y generar identificadores para tus productos y variaciones.</p>
                <div class="mpbm-tool-section">
                    <h4>Generador de SKUs</h4>
                    <p class="description">Busca productos y variaciones que no tengan un SKU asignado y genera uno automáticamente.</p>
                    <button type="button" id="analyze-skus-btn" class="button button-secondary">
                        <span class="dashicons dashicons-search" style="vertical-align: middle;"></span>
                        Analizar Productos sin SKU
                    </button>
                    <div id="sku-generation-area" class="mpbm-generation-area" style="display:none;">
                        <div class="mpbm-feedback notice"></div>
                        <ul class="mpbm-product-list"></ul>
                        <button type="button" id="generate-skus-confirm-btn" class="button button-primary">Generar SKUs para los productos listados</button>
                    </div>
                </div>
                <hr style="margin: 25px 0;">
                <div class="mpbm-tool-section">
                    <h4>Generador de Códigos de Barras</h4>
                    <p class="description">Busca productos/variaciones con SKU pero sin código de barras y genera uno nuevo.</p>
                    <form method="POST" action="">
                         <?php wp_nonce_field('mpbm_save_action', 'mpbm_save_settings_nonce'); ?>
                        <label for="barcode_type">Tipo de Código de Barras a generar:</label>
                        <select id="barcode_type" name="barcode_type">
                            <?php foreach ($barcode_types as $key => $name) : ?>
                                <option value="<?php echo esc_attr($key); ?>" <?php selected($barcode_type, $key); ?>>
                                    <?php echo esc_html($name); ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                         <button type="submit" class="button">Guardar Tipo</button>
                    </form>
                    <p><label><input type="checkbox" id="regenerate-all-barcodes-checkbox"> Incluir productos que ya tienen código de barras (regenerar todo).</label></p>
                    <button type="button" id="analyze-barcodes-btn" class="button button-secondary">
                        <span class="dashicons dashicons-search" style="vertical-align: middle;"></span>
                        Analizar Productos para Código de Barras
                    </button>
                    <div id="barcode-generation-area" class="mpbm-generation-area" style="display:none;">
                        <div class="mpbm-feedback notice"></div>
                        <ul class="mpbm-product-list"></ul>
                        <button type="button" id="generate-barcodes-confirm-btn" class="button button-primary">Generar Códigos de Barras para los productos listados</button>
                    </div>
                </div>
            </div>
        </div>
        <div class="mpbm-tab-content" id="tab-historial-inventario">
            <div class="mpbm-card">
                <h2>Historial de Movimientos de Inventario</h2>
                <p>Aquí se registran todos los cambios de stock realizados desde la aplicación móvil y desde WordPress.</p>
                <div id="inventory-history-container">
                    <p class="loading">Cargando historial...</p>
                </div>
            </div>
        </div>
        <div class="mpbm-tab-content" id="tab-ayuda">
             <div class="mpbm-grid">
                <div class="mpbm-card">
                     <h2>Guía de Inicio Rápido</h2>
                     <ol>
                        <li><strong>Descarga la App:</strong> Instala "MY POS BARCODE MOBIL" en tu dispositivo.</li>
                        <li><strong>Ve a la pestaña "Conexión App"</strong> y nombra tu dispositivo.</li>
                        <li><strong>Genera y Escanea el QR:</strong> Presiona "Generar QR" y escanea el código con la app.</li>
                        <li><strong>¡Listo!</strong> La app se configurará automáticamente.</li>
                     </ol>
                </div>
                <div class="mpbm-card">
                    <h2>Dispositivos Vinculados</h2>
                    <div id="devices-list"></div>
                </div>
            </div>
        </div>
        
        <input type="hidden" id="mpbm_site_url" value="<?php echo esc_url(home_url()); ?>">
        <textarea id="mpbm_devices_json" style="display: none;"><?php echo esc_textarea(json_encode($devices)); ?></textarea>
    </div>
    <?php
}