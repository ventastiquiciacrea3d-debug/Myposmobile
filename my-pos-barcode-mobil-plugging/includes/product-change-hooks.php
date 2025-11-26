<?php
/**
 * Hooks Mejorados para Detectar TODOS los Cambios de Inventario
 *
 * Este archivo contiene hooks de WordPress/WooCommerce para detectar TODOS
 * los cambios en productos e inventario, no solo la creación de productos.
 *
 * @package MPBM
 * @version 1.0.0
 */

if (!defined('WPINC')) {
    die;
}

/**
 * Marcar producto como modificado en tabla delta
 *
 * @param int $product_id ID del producto
 * @param int $priority Prioridad (0 = crítico, 3 = bajo)
 */
function mpbm_mark_product_changed($product_id, $priority = 2) {
    global $wpdb;

    // Verificar que existe la tabla delta
    $table_name = $wpdb->prefix . 'mpbm_product_changes';

    // Insertar o actualizar registro de cambio
    $wpdb->replace(
        $table_name,
        [
            'product_id' => $product_id,
            'priority' => $priority,
            'changed_at' => current_time('mysql'),
            'synced_at' => null // Resetear sync status
        ],
        ['%d', '%d', '%s', '%s']
    );

    error_log("[MPBM] Product #{$product_id} marked as changed (priority: {$priority})");
}

// ==================== HOOKS PARA CAMBIOS DE STOCK ====================

/**
 * Hook: Cambio de stock manual o por pedido
 * Detecta: wc_update_product_stock(), $product->set_stock_quantity()
 */
add_action('woocommerce_product_set_stock', function($product) {
    if (!is_object($product)) return;

    $product_id = $product->get_id();
    if (!$product_id) return;

    // Prioridad 0 (crítica) - cambios de stock son importantes
    mpbm_mark_product_changed($product_id, 0);

    error_log("[MPBM] Stock changed for product #{$product_id} - New stock: " . $product->get_stock_quantity());
}, 10, 1);

/**
 * Hook: Cambio de estado de stock (instock, outofstock, onbackorder)
 * Detecta: $product->set_stock_status()
 */
add_action('woocommerce_product_set_stock_status', function($product_id, $stock_status) {
    if (!$product_id) return;

    // Prioridad 1 (alta) - estado de stock importante
    mpbm_mark_product_changed($product_id, 1);

    error_log("[MPBM] Stock status changed for product #{$product_id} - New status: {$stock_status}");
}, 10, 2);

// ==================== HOOKS PARA CAMBIOS DE PRECIO ====================

/**
 * Hook: Cambio de precio regular
 * Detecta: $product->set_regular_price()
 */
add_action('woocommerce_product_set_price', function($product) {
    if (!is_object($product)) return;

    $product_id = $product->get_id();
    if (!$product_id) return;

    // Prioridad 1 (alta) - precios son importantes
    mpbm_mark_product_changed($product_id, 1);

    error_log("[MPBM] Price changed for product #{$product_id} - New price: " . $product->get_price());
}, 10, 1);

/**
 * Hook: Cambio de precio de oferta
 * Detecta: $product->set_sale_price()
 */
add_action('woocommerce_product_set_sale_price', function($product_id, $sale_price) {
    if (!$product_id) return;

    // Prioridad 1 (alta)
    mpbm_mark_product_changed($product_id, 1);

    error_log("[MPBM] Sale price changed for product #{$product_id} - New sale price: {$sale_price}");
}, 10, 2);

// ==================== HOOKS PARA CAMBIOS DE SKU/BARCODE ====================

/**
 * Hook: Cambio de SKU
 * Detecta: $product->set_sku()
 */
add_action('woocommerce_product_set_sku', function($product_id, $sku) {
    if (!$product_id) return;

    // Prioridad 2 (media)
    mpbm_mark_product_changed($product_id, 2);

    error_log("[MPBM] SKU changed for product #{$product_id} - New SKU: {$sku}");
}, 10, 2);

/**
 * Hook: Actualización de metadata (detecta cambios de barcode)
 * Detecta: update_post_meta() para barcode
 */
add_action('updated_post_meta', function($meta_id, $object_id, $meta_key, $meta_value) {
    // Solo procesar si es un producto y el meta es barcode
    if (get_post_type($object_id) !== 'product') return;
    if ($meta_key !== '_barcode') return;

    // Prioridad 2 (media)
    mpbm_mark_product_changed($object_id, 2);

    error_log("[MPBM] Barcode changed for product #{$object_id} - New barcode: {$meta_value}");
}, 10, 4);

// ==================== HOOKS PARA CREACIÓN/ACTUALIZACIÓN DE PRODUCTOS ====================

/**
 * Hook: Producto guardado/actualizado (catch-all)
 * Detecta: wp_insert_post(), wp_update_post()
 */
add_action('save_post_product', function($post_id, $post, $update) {
    // Evitar ejecuciones en revisiones, autosaves
    if (wp_is_post_revision($post_id) || wp_is_post_autosave($post_id)) {
        return;
    }

    // Si es actualización, prioridad 2; si es nuevo, prioridad 1
    $priority = $update ? 2 : 1;

    mpbm_mark_product_changed($post_id, $priority);

    error_log("[MPBM] Product " . ($update ? 'updated' : 'created') . " #{$post_id}");
}, 10, 3);

// ==================== HOOKS PARA ELIMINACIÓN DE PRODUCTOS ====================

/**
 * Hook: Producto enviado a papelera
 */
add_action('wp_trash_post', function($post_id) {
    if (get_post_type($post_id) !== 'product') return;

    // Prioridad 0 (crítica) - eliminación es importante
    mpbm_mark_product_changed($post_id, 0);

    error_log("[MPBM] Product trashed #{$post_id}");
}, 10, 1);

/**
 * Hook: Producto eliminado permanentemente
 */
add_action('delete_post', function($post_id) {
    if (get_post_type($post_id) !== 'product') return;

    // Prioridad 0 (crítica)
    mpbm_mark_product_changed($post_id, 0);

    error_log("[MPBM] Product deleted #{$post_id}");
}, 10, 1);

// ==================== HOOKS PARA OPERACIONES MASIVAS ====================

/**
 * Hook: Edición masiva de productos
 * Detecta: Bulk actions en admin de WooCommerce
 */
add_action('woocommerce_product_bulk_edit_save', function($product) {
    if (!is_object($product)) return;

    $product_id = $product->get_id();
    if (!$product_id) return;

    // Prioridad 2 (media)
    mpbm_mark_product_changed($product_id, 2);

    error_log("[MPBM] Product bulk edited #{$product_id}");
}, 10, 1);

/**
 * Hook: Producto importado vía CSV
 * Detecta: WooCommerce Product CSV Import
 */
add_action('woocommerce_product_import_inserted_product_object', function($product, $data) {
    if (!is_object($product)) return;

    $product_id = $product->get_id();
    if (!$product_id) return;

    // Prioridad 1 (alta) - importaciones son importantes
    mpbm_mark_product_changed($product_id, 1);

    error_log("[MPBM] Product imported #{$product_id}");
}, 10, 2);

// ==================== HOOKS PARA VARIACIONES ====================

/**
 * Hook: Variación guardada/actualizada
 */
add_action('save_post_product_variation', function($variation_id, $post, $update) {
    // Evitar ejecuciones en revisiones, autosaves
    if (wp_is_post_revision($variation_id) || wp_is_post_autosave($variation_id)) {
        return;
    }

    // Marcar la variación
    mpbm_mark_product_changed($variation_id, 2);

    // También marcar el producto padre
    $parent_id = wp_get_post_parent_id($variation_id);
    if ($parent_id) {
        mpbm_mark_product_changed($parent_id, 2);
    }

    error_log("[MPBM] Product variation " . ($update ? 'updated' : 'created') . " #{$variation_id}");
}, 10, 3);

/**
 * Hook: Stock de variación cambiado
 */
add_action('woocommerce_variation_set_stock', function($variation) {
    if (!is_object($variation)) return;

    $variation_id = $variation->get_id();
    if (!$variation_id) return;

    // Marcar variación (prioridad 0 - crítica)
    mpbm_mark_product_changed($variation_id, 0);

    // También marcar producto padre
    $parent_id = $variation->get_parent_id();
    if ($parent_id) {
        mpbm_mark_product_changed($parent_id, 0);
    }

    error_log("[MPBM] Variation stock changed #{$variation_id} - New stock: " . $variation->get_stock_quantity());
}, 10, 1);

// ==================== HOOK PARA PEDIDOS (AFECTA STOCK) ====================

/**
 * Hook: Pedido completado (reduce stock)
 * Ya existe en api-endpoint-orders-only.php pero lo reforzamos aquí
 */
add_action('woocommerce_order_status_completed', function($order_id) {
    $order = wc_get_order($order_id);
    if (!$order) return;

    // Marcar todos los productos del pedido como modificados
    foreach ($order->get_items() as $item) {
        $product_id = $item->get_product_id();
        $variation_id = $item->get_variation_id();

        // Marcar producto principal
        if ($product_id) {
            mpbm_mark_product_changed($product_id, 0);
        }

        // Marcar variación si existe
        if ($variation_id) {
            mpbm_mark_product_changed($variation_id, 0);
        }
    }

    error_log("[MPBM] Order completed #{$order_id} - Products marked for sync");
}, 10, 1);

/**
 * Hook: Pedido cancelado (restaura stock)
 */
add_action('woocommerce_order_status_cancelled', function($order_id) {
    $order = wc_get_order($order_id);
    if (!$order) return;

    // Marcar todos los productos del pedido
    foreach ($order->get_items() as $item) {
        $product_id = $item->get_product_id();
        $variation_id = $item->get_variation_id();

        if ($product_id) {
            mpbm_mark_product_changed($product_id, 0);
        }

        if ($variation_id) {
            mpbm_mark_product_changed($variation_id, 0);
        }
    }

    error_log("[MPBM] Order cancelled #{$order_id} - Stock restored, products marked");
}, 10, 1);

// ==================== LIMPIEZA AUTOMÁTICA ====================

/**
 * Limpiar registros muy antiguos (>30 días) de la tabla delta
 * Se ejecuta diariamente
 */
add_action('mpbm_daily_cleanup', function() {
    global $wpdb;

    $table_name = $wpdb->prefix . 'mpbm_product_changes';

    // Eliminar registros sincronizados de más de 30 días
    $deleted = $wpdb->query("
        DELETE FROM {$table_name}
        WHERE synced_at IS NOT NULL
        AND synced_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
    ");

    error_log("[MPBM] Daily cleanup: Removed {$deleted} old synced records");
});

// Programar evento diario si no existe
if (!wp_next_scheduled('mpbm_daily_cleanup')) {
    wp_schedule_event(time(), 'daily', 'mpbm_daily_cleanup');
}