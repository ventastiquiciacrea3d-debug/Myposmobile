<?php
if (!defined('WPINC')) { die; }

class MPBM_Ajax_Handler {
    public function __construct() {
        // Hooks de AJAX y de administración
        add_action('wp_ajax_mpbm_regenerate_api_key', [$this, 'regenerate_api_key']);
        add_action('wp_ajax_mpbm_link_device', [$this, 'link_device']);
        add_action('wp_ajax_mpbm_revoke_device', [$this, 'revoke_device']);
        add_action('wp_ajax_mpbm_analyze_missing_skus', [$this, 'analyze_missing_skus']);
        add_action('wp_ajax_mpbm_generate_missing_skus', [$this, 'generate_missing_skus']);
        add_action('wp_ajax_mpbm_analyze_missing_barcodes', [$this, 'analyze_missing_barcodes']);
        add_action('wp_ajax_mpbm_generate_barcodes_from_skus', [$this, 'generate_barcodes_from_skus']);
        add_action('wp_ajax_mpbm_get_inventory_history', [$this, 'ajax_get_inventory_history']);

        // --- LÓGICA DE EXPORTACIÓN E IMPORTACIÓN (CON FUNCIÓN DE PREPARACIÓN OPTIMIZADA) ---
        add_action('wp_ajax_mpbm_prepare_export', [$this, 'prepare_export']); // <-- ACCIÓN OPTIMIZADA
        add_action('wp_ajax_mpbm_preview_csv_import', [$this, 'ajax_preview_csv_import']);
        add_action('admin_post_mpbm_confirm_import', [$this, 'handle_confirm_csv_import']);
        add_action('admin_post_mpbm_export_inventory', [$this, 'export_inventory_csv_hook']);
        add_action('admin_post_mpbm_download_template', [$this, 'download_template_csv_hook']);
    }

    public function start_session() {
        if (!session_id() && !headers_sent()) {
            @session_start();
        }
    }

    private function check_nonce($action, $nonce_key = 'nonce') {
        if (!isset($_REQUEST[$nonce_key]) || !wp_verify_nonce($_REQUEST[$nonce_key], $action)) {
            wp_die('Error de seguridad. El enlace ha expirado o es inválido.');
        }
    }

    public function export_inventory_csv_hook() {
        $this->check_nonce('mpbm_export_inventory_nonce');
        $this->export_inventory_csv();
    }

    public function download_template_csv_hook() {
        $this->check_nonce('mpbm_template_nonce');
        $this->download_template_csv();
    }
    
    /**
     * FUNCIÓN CORREGIDA Y OPTIMIZADA: Usa una consulta SQL directa para ser más eficiente en memoria y tiempo.
     */
    public function prepare_export() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) {
            wp_send_json_error('Nonce inválido.', 403);
        }
        
        global $wpdb;

        // Consulta SQL directa para obtener IDs, es mucho más rápida que WP_Query para grandes volúmenes.
        $product_ids = $wpdb->get_col("
            SELECT ID FROM {$wpdb->posts}
            WHERE post_type IN ('product', 'product_variation')
            AND post_status = 'publish'
        ");
        
        if (empty($product_ids)) {
            wp_send_json_error('No se encontraron productos para exportar.');
        }
        
        // Usar un transitorio para almacenar los IDs de forma temporal y segura.
        $transient_key = 'mpbm_export_' . wp_generate_uuid4();
        set_transient($transient_key, $product_ids, HOUR_IN_SECONDS);
        
        wp_send_json_success([
            'count' => count($product_ids),
            'key'   => $transient_key
        ]);
    }

    // --- El resto de las funciones de esta clase permanecen sin cambios ---
    private function download_template_csv() {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="plantilla_ajuste_inventario.csv"');
        $output = fopen('php://output', 'w');
        fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
        
        fputcsv($output, ['name', 'attribute', 'sku', 'stock_actual', 'conteo_fisico', 'anadir_stock']);
        fputcsv($output, ['Nombre Producto Simple', '', 'SKU-SIMPLE-1', 10, '0', '0']);
        fputcsv($output, ['Nombre Producto Variable - Atributo', 'Color: Rojo', 'SKU-VARIACION-1', 25, '0', '0']);
        
        fclose($output);
        exit();
    }

    private function export_inventory_csv() {
        $export_key = isset($_GET['key']) ? sanitize_key($_GET['key']) : '';
        $product_ids = get_transient($export_key);

        if (false === $product_ids || !is_array($product_ids)) {
            wp_die('Error: Los datos de exportación no son válidos o han expirado.');
        }

        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="exportacion_inventario_'.date('Y-m-d').'.csv"');
        $output = fopen('php://output', 'w');
        fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));

        fputcsv($output, ['name', 'attribute', 'sku', 'stock_actual', 'conteo_fisico', 'anadir_stock', 'manage_stock', 'price', 'type', 'category']);

        foreach ($product_ids as $product_id) {
            $product = wc_get_product($product_id);
            if (!$product || $product->is_type('variable')) continue;
            $parent_product = $product->is_type('variation') ? wc_get_product($product->get_parent_id()) : null;
            $this->write_csv_row($output, $product, $parent_product);
        }
        
        delete_transient($export_key);
        fclose($output);
        exit();
    }
    
    private function write_csv_row($output, $product, $parent = null) {
        $product_for_cats = $parent ? $parent : $product;
        $term_list = wp_get_post_terms($product_for_cats->get_id(), 'product_cat', ['fields' => 'names']);
        $category_names = !is_wp_error($term_list) && !empty($term_list) ? implode(', ', $term_list) : '';
        $attributes_text = '';
        if ($product->is_type('variation')) {
            $attributes = $product->get_variation_attributes();
            $attr_parts = [];
            foreach ($attributes as $taxonomy => $term_slug) {
                $attr_label = wc_attribute_label(str_replace('attribute_', '', $taxonomy));
                $term = get_term_by('slug', $term_slug, $taxonomy);
                $attr_parts[] = $attr_label . ': ' . ($term ? $term->name : $term_slug);
            }
            $attributes_text = implode(' | ', $attr_parts);
        }
        $manage_stock_status = $product->get_manage_stock() ? 'Habilitado' : 'Deshabilitado';
        $stock_display = $product->get_manage_stock() ? ($product->get_stock_quantity() ?? 0) : 'Ilimitado';

        fputcsv($output, [$product->get_name(), $attributes_text, $product->get_sku(), $stock_display, '0', '0', $manage_stock_status, $product->get_price(), $product->get_type(), $category_names]);
    }

    public function ajax_preview_csv_import() {
        check_ajax_referer('mpbm_import_inventory_nonce', 'mpbm_import_nonce');
        
        if (!isset($_FILES['mpbm_csv_file']) || $_FILES['mpbm_csv_file']['error'] !== UPLOAD_ERR_OK) {
            wp_send_json_error(['message' => 'Error al subir el archivo. Inténtalo de nuevo.']);
        }

        $file_path = $_FILES['mpbm_csv_file']['tmp_name'];
        $csv_string = file_get_contents($file_path);
        if (substr($csv_string, 0, 3) == "\xEF\xBB\xBF") { $csv_string = substr($csv_string, 3); }
        $csv_string = str_replace("\r\n", "\n", $csv_string);
        
        $lines = explode("\n", $csv_string);
        if(count($lines) < 2) {
            wp_send_json_error(['message' => 'El archivo CSV está vacío o solo contiene la cabecera.']);
        }

        $first_line = $lines[0];
        $delimiter = strpos($first_line, ';') !== false ? ';' : ',';
        
        $csv_data = array_map(function($line) use ($delimiter) { return str_getcsv($line, $delimiter); }, $lines);

        $header = array_map(fn($h) => strtolower(trim($h)), array_shift($csv_data));
        
        $sku_key = array_search('sku', $header);
        $physical_count_key = array_search('conteo_fisico', $header);
        $add_stock_key = array_search('anadir_stock', $header);

        if ($sku_key === false || ($physical_count_key === false && $add_stock_key === false)) {
             wp_send_json_error(['message' => 'El archivo CSV debe contener la columna "sku" y "conteo_fisico" o "anadir_stock".']);
        }

        $preview_data = [];
        foreach($csv_data as $row) {
            if (empty(array_filter($row))) continue;
            $sku = isset($row[$sku_key]) ? trim($row[$sku_key]) : '';
            if (empty($sku)) continue;

            $physical_count_val = ($physical_count_key !== false && isset($row[$physical_count_key])) ? trim($row[$physical_count_key]) : '';
            $add_stock_val = ($add_stock_key !== false && isset($row[$add_stock_key])) ? trim($row[$add_stock_key]) : '';

            $operation = null; $value = 0;
            if (is_numeric($physical_count_val) && intval($physical_count_val) != 0) {
                $operation = 'physical_count'; $value = intval($physical_count_val);
            } elseif (is_numeric($add_stock_val) && intval($add_stock_val) != 0) {
                $operation = 'add_stock'; $value = intval($add_stock_val);
            }

            if ($operation === null) continue;

            $product_id = wc_get_product_id_by_sku($sku);
            if ($product_id) {
                $product = wc_get_product($product_id);
                if ($product) {
                    $old_stock = $product->get_manage_stock() ? (int)$product->get_stock_quantity() : 0;
                    $new_stock = ($operation === 'physical_count') ? $value : $old_stock + $value;
                    $change = $new_stock - $old_stock;
                    
                    $preview_data[] = ['id' => $product_id, 'sku' => $sku, 'name' => $product->get_name(), 'old_stock' => $old_stock, 'new_stock' => $new_stock, 'change' => $change, 'operation' => $operation];
                }
            }
        }
        
        if (empty($preview_data)) {
            wp_send_json_error(['message' => 'No se encontraron productos válidos para actualizar en el archivo. Verifica los SKUs.']);
        }
        
        wp_send_json_success(['products' => $preview_data]);
    }

    public function handle_confirm_csv_import() {
        if (!session_id()) { @session_start(); }
        $this->check_nonce('mpbm_confirm_import_nonce', 'mpbm_confirm_nonce');
        
        if (!isset($_POST['mpbm_import_data'])) {
             wp_redirect(add_query_arg(['mpbm_error' => 'no_data'], admin_url('admin.php?page=my-pos-barcode-mobil#tab-importar-exportar')));
             exit;
        }
        
        $import_data = json_decode(stripslashes($_POST['mpbm_import_data']), true);
        $updated_count = 0;
        $logger = new MPBM_Inventory_Logger();
        $user_id = get_current_user_id();

        $grouped_items = [];
        foreach ($import_data as $item) {
            $op_type = $item['operation'];
            if (!isset($grouped_items[$op_type])) { $grouped_items[$op_type] = []; }
            $grouped_items[$op_type][] = $item;
        }

        foreach ($grouped_items as $operation => $items) {
            $movement_id = wp_generate_uuid4();
            $reason = ($operation === 'add_stock') ? 'supplierReceipt' : 'stockCorrection';
            $description = 'Ajuste masivo desde CSV (' . (($operation === 'add_stock') ? 'Entrada de Stock' : 'Conteo Físico') . ')';

            foreach($items as $item) {
                $product = wc_get_product($item['id']);
                if ($product) {
                    $old_stock = (int)$item['old_stock'];
                    $new_stock = (int)$item['new_stock'];
                    $quantity_changed = (int)$item['change'];
                    
                    if ($operation === 'physical_count' && !$product->get_manage_stock()) {
                        update_post_meta($product->get_id(), '_manage_stock', 'yes');
                    }
                    
                    if ($quantity_changed !== 0) {
                        wc_update_product_stock($product, $new_stock);
                        $logger->log_movement(
                            $product, 
                            $quantity_changed, 
                            $reason, 
                            $description, 
                            $user_id, 
                            $movement_id, 
                            $old_stock,
                            $new_stock
                        );
                        $updated_count++;
                    }
                }
            }
        }
        
        wp_redirect(add_query_arg(['mpbm_success' => $updated_count], admin_url('admin.php?page=my-pos-barcode-mobil#tab-importar-exportar')));
        exit;
    }
    
    public function regenerate_api_key() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) { wp_send_json_error('Nonce inválido.', 403); }
        $new_key = wp_generate_uuid4();
        update_option('mpbm_api_key', $new_key);
        update_option('mpbm_devices', []);
        wp_send_json_success(['new_key' => $new_key]);
    }

    public function link_device() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) { wp_send_json_error('Nonce inválido.', 403); }
        $device_name = sanitize_text_field($_POST['device_name']);
        if (empty($device_name)) { wp_send_json_error('El nombre del dispositivo es requerido.'); }
        $devices = get_option('mpbm_devices', []);
        $new_device = ['id' => 'dev_' . wp_generate_uuid4(), 'name' => $device_name, 'date' => current_time('Y-m-d')];
        array_unshift($devices, $new_device);
        update_option('mpbm_devices', $devices);
        wp_send_json_success(['devices' => $devices]);
    }

    public function revoke_device() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) { wp_send_json_error('Nonce inválido.', 403); }
        $device_id = sanitize_text_field($_POST['device_id']);
        $devices = get_option('mpbm_devices', []);
        $updated_devices = array_values(array_filter($devices, fn($d) => $d['id'] !== $device_id));
        update_option('mpbm_devices', $updated_devices);
        wp_send_json_success(['devices' => $updated_devices]);
    }

    public function analyze_missing_skus() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) { wp_send_json_error('Nonce inválido.', 403); }
        global $wpdb;
        $results = $wpdb->get_results("SELECT p.ID, p.post_title, p.post_type FROM {$wpdb->posts} p LEFT JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id AND pm.meta_key = '_sku' WHERE p.post_type IN ('product', 'product_variation') AND p.post_status = 'publish' AND (pm.meta_value IS NULL OR pm.meta_value = '') ORDER BY p.post_title");
        wp_send_json_success(['products' => $results]);
    }

    public function generate_missing_skus() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) { wp_send_json_error('Nonce inválido.', 403); }
        global $wpdb;
        $processed_count = 0;
        $updated_products = [];
        $product_ids = $wpdb->get_col("SELECT p.ID FROM {$wpdb->posts} p LEFT JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id AND pm.meta_key = '_sku' WHERE p.post_type IN ('product', 'product_variation') AND p.post_status = 'publish' AND (pm.meta_value IS NULL OR pm.meta_value = '')");
        if (empty($product_ids)) { wp_send_json_success(['message' => '¡Excelente! Todos los productos ya tienen un SKU.']); }
        foreach ($product_ids as $product_id) {
            $product = wc_get_product($product_id);
            if ($product && empty($product->get_sku())) {
                $words = explode(' ', $product->get_name());
                $initials = array_reduce($words, fn($c, $w) => $c . (empty($w) ? '' : strtoupper(substr($w, 0, 1))), '');
                $new_sku = $initials . '-' . $product_id;
                update_post_meta($product_id, '_sku', $new_sku);
                $processed_count++;
                $updated_products[] = ['id' => $product_id, 'name' => $product->get_name(), 'new_sku' => $new_sku];
            }
        }
        wp_send_json_success(['message' => "Proceso completado. Se generaron $processed_count SKUs nuevos.", 'updated_products' => $updated_products]);
    }

    public function analyze_missing_barcodes() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) { wp_send_json_error('Nonce inválido.', 403); }
        global $wpdb;
        $regenerate_all = isset($_POST['regenerate_all']) && $_POST['regenerate_all'] === 'true';
        $query = "SELECT p.ID, p.post_title, p.post_type, pm_sku.meta_value as sku FROM {$wpdb->posts} p INNER JOIN {$wpdb->postmeta} pm_sku ON p.ID = pm_sku.post_id AND pm_sku.meta_key = '_sku' AND pm_sku.meta_value != '' LEFT JOIN {$wpdb->postmeta} pm_barcode ON p.ID = pm_barcode.post_id AND pm_barcode.meta_key = '_mpbm_barcode' WHERE p.post_type IN ('product', 'product_variation') AND p.post_status = 'publish'";
        if (!$regenerate_all) { $query .= " AND pm_barcode.meta_value IS NULL"; }
        $query .= " ORDER BY p.post_title";
        wp_send_json_success(['products' => $wpdb->get_results($query)]);
    }

    public function generate_barcodes_from_skus() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) { wp_send_json_error('Nonce inválido.', 403); }
        global $wpdb;
        $processed_count = 0;
        $updated_products = [];
        $regenerate_all = isset($_POST['regenerate_all']) && $_POST['regenerate_all'] === 'true';
        $query = "SELECT p.ID, pm_sku.meta_value as sku FROM {$wpdb->posts} p INNER JOIN {$wpdb->postmeta} pm_sku ON p.ID = pm_sku.post_id AND pm_sku.meta_key = '_sku' AND pm_sku.meta_value != '' LEFT JOIN {$wpdb->postmeta} pm_barcode ON p.ID = pm_barcode.post_id AND pm_barcode.meta_key = '_mpbm_barcode' WHERE p.post_type IN ('product', 'product_variation') AND p.post_status = 'publish'";
        if (!$regenerate_all) { $query .= " AND pm_barcode.meta_value IS NULL"; }
        $results = $wpdb->get_results($query);
        if (empty($results)) { wp_send_json_success(['message' => '¡Excelente! No había productos para procesar.']); }
        foreach ($results as $result) {
            update_post_meta($result->ID, '_mpbm_barcode', $result->sku);
            $processed_count++;
            $product = wc_get_product($result->ID);
            if($product) {
                $updated_products[] = ['id' => $result->ID, 'name' => $product->get_name(), 'new_barcode' => $result->sku];
            }
        }
        wp_send_json_success(['message' => "Proceso completado. Se generaron/actualizaron $processed_count códigos de barras.", 'updated_products' => $updated_products]);
    }
    
    public function ajax_get_inventory_history() {
        if (!check_ajax_referer('mpbm_ajax_nonce', 'nonce', false)) {
            wp_send_json_error('Nonce inválido.', 403);
        }
        
        global $wpdb;
        $table_name = $wpdb->prefix . 'mpbm_inventory_log';
        $results = $wpdb->get_results("SELECT * FROM $table_name ORDER BY log_date DESC LIMIT 500", ARRAY_A);
        
        if (empty($results)) {
            wp_send_json_success([]);
            return;
        }

        $movements = [];
        foreach ($results as $row) {
            $movement_id = $row['movement_id'];
            if (!isset($movements[$movement_id])) {
                $user_info = get_userdata($row['user_id']);
                $date = new DateTime($row['log_date']);
                $movements[$movement_id] = [
                    'movement_id' => $movement_id,
                    'date'        => $date->format('Y-m-d H:i:s'),
                    'reason'      => $row['reason'],
                    'description' => $row['description'],
                    'user_name'   => $user_info ? $user_info->display_name : 'Sistema',
                    'items'       => []
                ];
            }
            $movements[$movement_id]['items'][] = [
                'product_name'     => $row['product_name'],
                'sku'              => $row['sku'],
                'quantity_changed' => (int)$row['quantity_changed'],
                'stock_before'     => is_numeric($row['stock_before']) ? (int)$row['stock_before'] : 'N/A',
                'stock_after'      => (int)$row['stock_after']
            ];
        }
        
        wp_send_json_success(array_values($movements));
    }
}