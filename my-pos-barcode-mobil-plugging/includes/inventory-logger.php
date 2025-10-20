<?php
if (!defined('WPINC')) { die; }

class MPBM_Inventory_Logger {

    public function __construct() {
        add_action('woocommerce_product_set_stock', [$this, 'log_stock_change_from_product']);
        add_action('woocommerce_variation_set_stock', [$this, 'log_stock_change_from_product']);
    }

    public function log_stock_change_from_product($product) {
        if (!is_a($product, 'WC_Product') || did_action('mpbm_api_stock_update')) {
            return;
        }

        $new_stock = $product->get_stock_quantity();
        $old_stock_value = get_post_meta($product->get_id(), '_stock', true);
        $old_stock = is_numeric($old_stock_value) ? (int)$old_stock_value : 0;
        
        $quantity_changed = $new_stock - $old_stock;
        if ($quantity_changed === 0) return;

        $this->log_movement(
            $product, $quantity_changed, 'manualAdjustment', 'Ajuste manual desde WordPress',
            get_current_user_id(), null, $old_stock, $new_stock
        );
    }
    
    public function log_movement($product, $quantity_changed, $reason, $description, $user_id, $movement_id = null, $stock_before = null, $stock_after = null) {
        global $wpdb;
        $table_name = $wpdb->prefix . 'mpbm_inventory_log';

        $stock_after_val = is_numeric($stock_after) ? (int)$stock_after : $product->get_stock_quantity();
        $stock_before_val = is_numeric($stock_before) ? (int)$stock_before : ($stock_after_val - $quantity_changed);

        $wpdb->insert($table_name, [
            'movement_id' => $movement_id ?: wp_generate_uuid4(),
            'product_id' => $product->is_type('variation') ? $product->get_parent_id() : $product->get_id(),
            'variation_id' => $product->is_type('variation') ? $product->get_id() : 0,
            'product_name' => $product->get_name(), 'sku' => $product->get_sku(),
            'quantity_changed' => $quantity_changed, 'stock_before' => $stock_before_val,
            'stock_after' => $stock_after_val, 'reason' => sanitize_text_field($reason),
            'description' => sanitize_text_field($description), 'user_id' => $user_id,
            'log_date' => current_time('mysql'),
        ]);
    }

    /**
     * Procesa un lote de movimientos desde la API con lógica de transacción simulada.
     * Fase 1: Validar todos los ítems.
     * Fase 2: Ejecutar todas las actualizaciones.
     */
    public function log_batch_movement_from_api($movement_data, $user_id) {
        $movement_id = $movement_data['id'];
        $reason = sanitize_text_field($movement_data['type']);
        $description = sanitize_text_field($movement_data['description']);
        $items = $movement_data['items'];

        // --- FASE 1: VALIDACIÓN ---
        $validated_items = [];
        foreach ($items as $item) {
            $product_id_to_update = !empty($item['variationId']) ? absint($item['variationId']) : absint($item['productId']);
            $product = wc_get_product($product_id_to_update);
            
            if (!$product) {
                return new WP_Error('validation_error', 'Producto no encontrado con ID: ' . $product_id_to_update, ['status' => 404]);
            }
            
            $quantity_changed = (int)$item['quantityChanged'];
            if ($quantity_changed < 0 && $product->get_manage_stock()) {
                $current_stock = (int)$product->get_stock_quantity();
                if ($current_stock + $quantity_changed < 0) {
                    return new WP_Error('validation_error', 'Stock insuficiente para SKU: ' . $product->get_sku() . '. Se necesita: ' . abs($quantity_changed) . ', Disponible: ' . $current_stock, ['status' => 409]);
                }
            }
            $validated_items[] = ['product' => $product, 'data' => $item];
        }

        // --- FASE 2: EJECUCIÓN ---
        foreach ($validated_items as $validated) {
            $product = $validated['product'];
            $item_data = $validated['data'];
            
            if ($reason === 'stockCorrection' && !$product->get_manage_stock()) {
                update_post_meta($product->get_id(), '_manage_stock', 'yes');
                if ($product->is_type('variation')) {
                    $parent_product = wc_get_product($product->get_parent_id());
                    if ($parent_product && !$parent_product->get_manage_stock()) {
                         update_post_meta($parent_product->get_id(), '_manage_stock', 'yes');
                    }
                }
            }
            
            $quantity_changed = (int)$item_data['quantityChanged'];
            
            do_action('mpbm_api_stock_update');
            if ($product->get_manage_stock() || $reason === 'stockCorrection') {
                wc_update_product_stock($product, (int)$item_data['stockAfter']);
            }
            
            $this->log_movement(
                $product, $quantity_changed, $reason, $description, $user_id, 
                $movement_id, (int)$item_data['stockBefore'], (int)$item_data['stockAfter']
            );
        }
        
        return true;
    }
}