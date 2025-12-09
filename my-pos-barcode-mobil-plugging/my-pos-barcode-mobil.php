<?php
/**
 * Plugin Name:       MY POS BARCODE MOBIL
 * Plugin URI:        https://tudominio.com
 * Description:       Crea un endpoint de API optimizado con caché para la app móvil y una página de configuración avanzada.
 * Version:           3.2.0
 * Author:            Tu Nombre
 * Author URI:        https://tudominio.com
 * License:           GPL v2 or later
 * License URI:       https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain:       my-pos-barcode-mobil
 * Domain Path:       /languages
 * Requires at least: 5.8
 * Requires PHP:      7.4
 */

if (!defined('WPINC')) {
    die;
}

define('MPBM_PLUGIN_FILE', __FILE__);
define('MPBM_PLUGIN_PATH', plugin_dir_path(MPBM_PLUGIN_FILE));
define('MPBM_PLUGIN_URL', plugin_dir_url(MPBM_PLUGIN_FILE));

// ✅ Cargar auto-installer primero
require_once MPBM_PLUGIN_PATH . 'includes/auto-installer.php';

// ✅ Registrar hooks de activación/desactivación
register_activation_hook(MPBM_PLUGIN_FILE, 'mpbm_activate_plugin');
register_deactivation_hook(MPBM_PLUGIN_FILE, 'mpbm_deactivate_plugin');

function mpbm_run_plugin() {
    if (!class_exists('WooCommerce')) {
        add_action('admin_notices', 'mpbm_woocommerce_not_active_notice');
        return;
    }
    mpbm_include_files_and_init_hooks();
}
add_action('plugins_loaded', 'mpbm_run_plugin');

function mpbm_woocommerce_not_active_notice() {
    ?>
    <div class="notice notice-error is-dismissible">
        <p><strong>MY POS BARCODE MOBIL:</strong> Este plugin requiere que <strong>WooCommerce</strong> esté instalado y activo.</p>
    </div>
    <?php
}

function mpbm_include_files_and_init_hooks() {
    require_once MPBM_PLUGIN_PATH . 'includes/admin-page.php';
    require_once MPBM_PLUGIN_PATH . 'includes/inventory-logger.php';
    require_once MPBM_PLUGIN_PATH . 'includes/api-endpoints.php';
    require_once MPBM_PLUGIN_PATH . 'includes/class-mypos-ajax.php';

    // ✅ DELTA SYNC: Track product changes
    require_once MPBM_PLUGIN_PATH . 'includes/delta-sync-tracker.php';
    require_once MPBM_PLUGIN_PATH . 'includes/api-endpoints-delta.php';

    // ✅ POLLING INTELIGENTE: Endpoints ligeros (reemplaza FCM)
    require_once MPBM_PLUGIN_PATH . 'includes/api-endpoints-polling.php';

    // 🟢 PRIORIDAD 3: Endpoint delta para pedidos
    require_once MPBM_PLUGIN_PATH . 'includes/api-endpoint-orders-only.php';

    // 🟢 NUEVO: Hooks mejorados para detectar TODOS los cambios de inventario
    require_once MPBM_PLUGIN_PATH . 'includes/product-change-hooks.php';

    // ✅ BATCH OPERATIONS: Operaciones en lote para stock, precios y órdenes
    require_once MPBM_PLUGIN_PATH . 'includes/class-mpbm-batch-operations.php';
    MPBM_Batch_Operations_V2::get_instance();

    new MPBM_Ajax_Handler();
    new MPBM_Inventory_Logger();

    add_action('admin_enqueue_scripts', 'mpbm_admin_enqueue_scripts');
    add_filter('plugin_action_links_' . plugin_basename(MPBM_PLUGIN_FILE), 'mpbm_add_settings_link');

    // ✓ OPTIMIZADO: Invalidar cache de búsquedas cuando se actualiza un producto
    add_action('woocommerce_update_product', 'mpbm_clear_search_cache');
    add_action('woocommerce_new_product', 'mpbm_clear_search_cache');
    add_action('woocommerce_delete_product', 'mpbm_clear_search_cache');
    add_action('woocommerce_update_product_variation', 'mpbm_clear_search_cache');
    add_action('woocommerce_new_product_variation', 'mpbm_clear_search_cache');
    add_action('woocommerce_delete_product_variation', 'mpbm_clear_search_cache');
}

/**
 * Limpia el cache de búsquedas cuando se modifica un producto.
 * ✓ OPTIMIZADO: Limpia tanto transients como cache de objetos.
 *
 * @param int $product_id ID del producto modificado
 */
function mpbm_clear_search_cache($product_id = 0) {
    global $wpdb;

    // 1. Eliminar todos los transients de búsqueda
    $wpdb->query("
        DELETE FROM {$wpdb->options}
        WHERE option_name LIKE '_transient_mpbm_search_%'
           OR option_name LIKE '_transient_timeout_mpbm_search_%'
    ");

    // 2. Limpiar cache de objeto para el producto específico
    if ($product_id > 0) {
        wp_cache_delete("mpbm_product_data_{$product_id}_light", 'mpbm_products');
        wp_cache_delete("mpbm_product_data_{$product_id}_full", 'mpbm_products');

        // Si es un producto variable, limpiar también sus variaciones
        $product = wc_get_product($product_id);
        if ($product && $product->is_type('variable')) {
            $variation_ids = $product->get_children();
            foreach ($variation_ids as $variation_id) {
                wp_cache_delete("mpbm_product_data_{$variation_id}_light", 'mpbm_products');
                wp_cache_delete("mpbm_product_data_{$variation_id}_full", 'mpbm_products');
            }
        }

        // Si es una variación, limpiar también el producto padre
        if ($product && $product->is_type('variation')) {
            $parent_id = $product->get_parent_id();
            if ($parent_id > 0) {
                wp_cache_delete("mpbm_product_data_{$parent_id}_light", 'mpbm_products');
                wp_cache_delete("mpbm_product_data_{$parent_id}_full", 'mpbm_products');
            }
        }
    }
}

function mpbm_admin_enqueue_scripts($hook) {
    if ('toplevel_page_my-pos-barcode-mobil' !== $hook) {
        return;
    }
    wp_enqueue_style('mpbm-admin-style', MPBM_PLUGIN_URL . 'assets/css/admin-style.css', array(), '3.0.0');
    wp_enqueue_script('mpbm-qrcode-lib', MPBM_PLUGIN_URL . 'assets/js/qrcode.min.js', array('jquery'), '1.0.0', true);
    wp_enqueue_script('mpbm-jsbarcode-lib', 'https://cdn.jsdelivr.net/npm/jsbarcode@3.11.5/dist/JsBarcode.all.min.js', array(), '3.11.5', true);

    wp_enqueue_script('mpbm-admin-script', MPBM_PLUGIN_URL . 'assets/js/admin-script.js', ['jquery'], '3.0.0', true);
    
    // Objeto con variables para JavaScript
    wp_localize_script('mpbm-admin-script', 'mpbm_ajax_obj', [
        'ajax_url' => admin_url('admin-ajax.php'),
        'admin_post_url' => admin_url('admin-post.php'),
        'nonce'    => wp_create_nonce('mpbm_ajax_nonce'),
        'export_nonce' => wp_create_nonce('mpbm_export_inventory_nonce'),
        'import_nonce' => wp_create_nonce('mpbm_import_inventory_nonce'),
        'template_nonce' => wp_create_nonce('mpbm_template_nonce'),
        'confirm_nonce' => wp_create_nonce('mpbm_confirm_import_nonce')
    ]);
}

function mpbm_add_settings_link($links) {
    $settings_link = '<a href="' . admin_url('admin.php?page=my-pos-barcode-mobil#tab-conexion') . '">' . __('Ajustes') . '</a>';
    array_unshift($links, $settings_link);
    return $links;
}

// ✅ NOTA: Las funciones mpbm_activate_plugin(), mpbm_deactivate_plugin() y
// mpbm_create_performance_indices() ahora están en includes/auto-installer.php
// para evitar duplicación. Se ejecutan automáticamente al activar/desactivar el plugin.