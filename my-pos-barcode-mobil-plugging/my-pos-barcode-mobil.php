<?php
/**
 * Plugin Name:       MY POS BARCODE MOBIL
 * Plugin URI:        https://tudominio.com
 * Description:       Crea un endpoint de API optimizado con caché para la app móvil y una página de configuración avanzada.
 * Version:           3.0.0
 * Author:            Tu Nombre
 * Author URI:        https://tudominio.com
 * License:           GPL v2 or later
 * License URI:       https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain:       my-pos-barcode-mobil
 * Domain Path:       /languages
 */

if (!defined('WPINC')) {
    die;
}

define('MPBM_PLUGIN_FILE', __FILE__);
define('MPBM_PLUGIN_PATH', plugin_dir_path(MPBM_PLUGIN_FILE));
define('MPBM_PLUGIN_URL', plugin_dir_url(MPBM_PLUGIN_FILE));

register_activation_hook(MPBM_PLUGIN_FILE, 'mpbm_activate_plugin');

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

    new MPBM_Ajax_Handler();
    new MPBM_Inventory_Logger();

    add_action('admin_enqueue_scripts', 'mpbm_admin_enqueue_scripts');
    add_filter('plugin_action_links_' . plugin_basename(MPBM_PLUGIN_FILE), 'mpbm_add_settings_link');
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

function mpbm_activate_plugin() {
    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_inventory_log';
    $charset_collate = $wpdb->get_charset_collate();

    $sql = "CREATE TABLE $table_name (
        id bigint(20) NOT NULL AUTO_INCREMENT,
        movement_id varchar(36) NOT NULL,
        product_id bigint(20) NOT NULL,
        variation_id bigint(20) DEFAULT 0,
        product_name varchar(255) NOT NULL,
        sku varchar(100) DEFAULT '' NOT NULL,
        quantity_changed int(11) NOT NULL,
        stock_before int(11) NULL,
        stock_after int(11) NULL,
        reason varchar(255) NOT NULL,
        description text,
        user_id bigint(20) NOT NULL,
        log_date datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (id),
        KEY movement_id (movement_id)
    ) $charset_collate;";

    require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
    dbDelta($sql);

    // Generar una clave de API inicial si no existe
    if (get_option('mpbm_api_key') === false) {
        update_option('mpbm_api_key', wp_generate_uuid4());
    }
}