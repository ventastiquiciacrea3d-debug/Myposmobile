<?php
/**
 * ✅ GESTIÓN AUTOMÁTICA DE STOCK EN PEDIDOS - MY POS BARCODE MOBIL
 *
 * Este archivo maneja:
 * 1. Reducción automática de stock al crear/procesar pedidos
 * 2. Aumento de stock en devoluciones/cancelaciones
 * 3. Notificaciones a la app de nuevos pedidos desde WooCommerce
 *
 * @package MPBM
 * @version 3.3.0
 */

if (!defined('WPINC')) {
    die;
}

// =====================================================
// TABLA DE NOTIFICACIONES DE PEDIDOS
// =====================================================

/**
 * Crear tabla para cola de notificaciones de pedidos
 */
function mpbm_create_order_notifications_table() {
    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_order_notifications';
    $charset_collate = $wpdb->get_charset_collate();

    $sql = "CREATE TABLE IF NOT EXISTS $table_name (
        id bigint(20) NOT NULL AUTO_INCREMENT,
        order_id bigint(20) NOT NULL,
        order_number varchar(50) NOT NULL,
        order_status varchar(20) NOT NULL,
        order_total decimal(10,2) NOT NULL,
        customer_id bigint(20) DEFAULT 0,
        customer_name varchar(255) DEFAULT '',
        created_at datetime NOT NULL,
        notified tinyint(1) DEFAULT 0,
        notified_at datetime DEFAULT NULL,
        source varchar(20) DEFAULT 'woocommerce',
        PRIMARY KEY  (id),
        KEY order_id (order_id),
        KEY notified (notified),
        KEY created_at (created_at)
    ) $charset_collate;";

    require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
    dbDelta($sql);
}

// Crear tabla al activar el plugin
add_action('mpbm_activate_plugin', 'mpbm_create_order_notifications_table');

// =====================================================
// HOOKS DE WOOCOMMERCE PARA GESTIÓN DE STOCK
// =====================================================

/**
 * Hook: Reducir stock automáticamente cuando un pedido se crea
 * Se ejecuta cuando el pedido pasa a estado 'processing' o 'completed'
 */
add_action('woocommerce_order_status_processing', 'mpbm_auto_reduce_stock_on_order', 10, 2);
add_action('woocommerce_order_status_completed', 'mpbm_auto_reduce_stock_on_order', 10, 2);

function mpbm_auto_reduce_stock_on_order($order_id, $order) {
    // Verificar si ya se redujo el stock (evitar duplicados)
    $stock_reduced = get_post_meta($order_id, '_mpbm_stock_reduced', true);
    if ($stock_reduced === 'yes') {
        error_log("[MPBM] Stock ya reducido para pedido #{$order_id}, skip");
        return;
    }

    error_log("[MPBM] 🔽 Reduciendo stock para pedido #{$order_id}");

    $items_processed = [];

    foreach ($order->get_items() as $item_id => $item) {
        $product = $item->get_product();
        if (!$product) continue;

        $product_id = $product->get_id();
        $quantity = $item->get_quantity();

        // Solo reducir si el producto gestiona stock
        if (!$product->managing_stock()) {
            error_log("[MPBM]   - Producto #{$product_id} no gestiona stock, skip");
            continue;
        }

        // Verificar stock actual
        $current_stock = $product->get_stock_quantity();
        if ($current_stock === null) {
            error_log("[MPBM]   - Producto #{$product_id} no tiene stock numérico, skip");
            continue;
        }

        // Reducir stock
        $new_stock = $current_stock - $quantity;
        wc_update_product_stock($product, $new_stock, 'set');

        error_log("[MPBM]   ✅ Producto #{$product_id}: {$current_stock} → {$new_stock} (-{$quantity})");

        $items_processed[] = [
            'product_id' => $product_id,
            'product_name' => $product->get_name(),
            'quantity' => $quantity,
            'stock_before' => $current_stock,
            'stock_after' => $new_stock,
        ];
    }

    // Marcar como procesado
    update_post_meta($order_id, '_mpbm_stock_reduced', 'yes');
    update_post_meta($order_id, '_mpbm_stock_reduction_date', current_time('mysql'));
    update_post_meta($order_id, '_mpbm_stock_items_processed', json_encode($items_processed));

    error_log("[MPBM] ✅ Stock reducido para pedido #{$order_id} (" . count($items_processed) . " productos)");
}

/**
 * Hook: Aumentar stock automáticamente en devoluciones/cancelaciones
 */
add_action('woocommerce_order_status_cancelled', 'mpbm_auto_restore_stock_on_cancellation', 10, 2);
add_action('woocommerce_order_status_refunded', 'mpbm_auto_restore_stock_on_refund', 10, 2);
add_action('woocommerce_order_status_failed', 'mpbm_auto_restore_stock_on_failed', 10, 2);

function mpbm_auto_restore_stock_on_cancellation($order_id, $order) {
    mpbm_restore_stock_for_order($order_id, $order, 'cancelado');
}

function mpbm_auto_restore_stock_on_refund($order_id, $order) {
    mpbm_restore_stock_for_order($order_id, $order, 'reembolsado');
}

function mpbm_auto_restore_stock_on_failed($order_id, $order) {
    mpbm_restore_stock_for_order($order_id, $order, 'fallido');
}

function mpbm_restore_stock_for_order($order_id, $order, $reason) {
    // Verificar si se había reducido el stock
    $stock_reduced = get_post_meta($order_id, '_mpbm_stock_reduced', true);
    if ($stock_reduced !== 'yes') {
        error_log("[MPBM] Stock no se había reducido para pedido #{$order_id}, skip");
        return;
    }

    // Verificar si ya se restauró (evitar duplicados)
    $stock_restored = get_post_meta($order_id, '_mpbm_stock_restored', true);
    if ($stock_restored === 'yes') {
        error_log("[MPBM] Stock ya restaurado para pedido #{$order_id}, skip");
        return;
    }

    error_log("[MPBM] 🔼 Restaurando stock para pedido #{$order_id} (razón: {$reason})");

    $items_processed = [];

    foreach ($order->get_items() as $item_id => $item) {
        $product = $item->get_product();
        if (!$product) continue;

        $product_id = $product->get_id();
        $quantity = $item->get_quantity();

        // Solo restaurar si el producto gestiona stock
        if (!$product->managing_stock()) {
            continue;
        }

        // Obtener stock actual
        $current_stock = $product->get_stock_quantity();
        if ($current_stock === null) {
            continue;
        }

        // Aumentar stock
        $new_stock = $current_stock + $quantity;
        wc_update_product_stock($product, $new_stock, 'set');

        error_log("[MPBM]   ✅ Producto #{$product_id}: {$current_stock} → {$new_stock} (+{$quantity})");

        $items_processed[] = [
            'product_id' => $product_id,
            'product_name' => $product->get_name(),
            'quantity' => $quantity,
            'stock_before' => $current_stock,
            'stock_after' => $new_stock,
        ];
    }

    // Marcar como restaurado
    update_post_meta($order_id, '_mpbm_stock_restored', 'yes');
    update_post_meta($order_id, '_mpbm_stock_restoration_date', current_time('mysql'));
    update_post_meta($order_id, '_mpbm_stock_restoration_reason', $reason);
    update_post_meta($order_id, '_mpbm_stock_items_restored', json_encode($items_processed));

    error_log("[MPBM] ✅ Stock restaurado para pedido #{$order_id} (" . count($items_processed) . " productos)");
}

// =====================================================
// NOTIFICACIONES DE NUEVOS PEDIDOS A LA APP
// =====================================================

/**
 * Hook: Registrar nuevo pedido para notificar a la app
 * Se ejecuta cuando se crea un pedido desde WooCommerce (no desde la app)
 */
add_action('woocommerce_new_order', 'mpbm_register_new_order_notification', 10, 2);
add_action('woocommerce_order_status_changed', 'mpbm_register_order_status_change_notification', 10, 4);

function mpbm_register_new_order_notification($order_id, $order) {
    // Verificar si el pedido fue creado desde la app (tiene metadata especial)
    $created_by_app = get_post_meta($order_id, '_created_by_mypos_app', true);
    if ($created_by_app === 'yes') {
        error_log("[MPBM] Pedido #{$order_id} creado desde la app, no notificar");
        return;
    }

    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_order_notifications';

    // Obtener datos del pedido
    $customer_id = $order->get_customer_id();
    $customer_name = trim($order->get_billing_first_name() . ' ' . $order->get_billing_last_name());
    if (empty($customer_name)) {
        $customer_name = $order->get_billing_email();
    }

    // Insertar notificación
    $inserted = $wpdb->insert(
        $table_name,
        [
            'order_id' => $order_id,
            'order_number' => $order->get_order_number(),
            'order_status' => $order->get_status(),
            'order_total' => $order->get_total(),
            'customer_id' => $customer_id,
            'customer_name' => $customer_name,
            'created_at' => current_time('mysql'),
            'source' => 'woocommerce',
            'notified' => 0,
        ],
        ['%d', '%s', '%s', '%f', '%d', '%s', '%s', '%s', '%d']
    );

    if ($inserted) {
        error_log("[MPBM] 🔔 Notificación registrada para pedido #{$order_id}");
    } else {
        error_log("[MPBM] ❌ Error registrando notificación para pedido #{$order_id}: " . $wpdb->last_error);
    }
}

function mpbm_register_order_status_change_notification($order_id, $old_status, $new_status, $order) {
    // Solo notificar cambios importantes
    $important_statuses = ['processing', 'completed', 'cancelled', 'refunded', 'failed'];
    if (!in_array($new_status, $important_statuses)) {
        return;
    }

    // Verificar si fue creado desde la app
    $created_by_app = get_post_meta($order_id, '_created_by_mypos_app', true);
    if ($created_by_app === 'yes') {
        return;
    }

    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_order_notifications';

    // Verificar si ya existe notificación para este pedido
    $exists = $wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM $table_name WHERE order_id = %d AND order_status = %s",
        $order_id,
        $new_status
    ));

    if ($exists > 0) {
        return; // Ya existe notificación para este estado
    }

    // Obtener datos del pedido
    $customer_id = $order->get_customer_id();
    $customer_name = trim($order->get_billing_first_name() . ' ' . $order->get_billing_last_name());
    if (empty($customer_name)) {
        $customer_name = $order->get_billing_email();
    }

    // Insertar notificación
    $wpdb->insert(
        $table_name,
        [
            'order_id' => $order_id,
            'order_number' => $order->get_order_number(),
            'order_status' => $new_status,
            'order_total' => $order->get_total(),
            'customer_id' => $customer_id,
            'customer_name' => $customer_name,
            'created_at' => current_time('mysql'),
            'source' => 'status_change',
            'notified' => 0,
        ],
        ['%d', '%s', '%s', '%f', '%d', '%s', '%s', '%s', '%d']
    );

    error_log("[MPBM] 🔔 Notificación de cambio de estado registrada para pedido #{$order_id} ({$old_status} → {$new_status})");
}

// =====================================================
// ENDPOINTS REST API PARA LA APP
// =====================================================

/**
 * Endpoint para que la app obtenga notificaciones pendientes
 */
add_action('rest_api_init', function() {
    register_rest_route('mypos/v1', '/order-notifications', [
        'methods' => 'GET',
        'callback' => 'mpbm_get_order_notifications_callback',
        'permission_callback' => 'mpbm_permission_check_jwt',
        'args' => [
            'limit' => [
                'default' => 10,
                'validate_callback' => function($param) { return is_numeric($param); },
                'sanitize_callback' => 'absint',
            ],
            'mark_as_read' => [
                'default' => false,
                'validate_callback' => function($param) { return is_bool($param) || $param === 'true' || $param === 'false'; },
            ],
        ],
    ]);

    // Endpoint para marcar notificaciones como leídas
    register_rest_route('mypos/v1', '/order-notifications/mark-read', [
        'methods' => 'POST',
        'callback' => 'mpbm_mark_notifications_read_callback',
        'permission_callback' => 'mpbm_permission_check_jwt',
        'args' => [
            'notification_ids' => [
                'required' => true,
                'validate_callback' => function($param) { return is_array($param); },
            ],
        ],
    ]);
});

function mpbm_get_order_notifications_callback(WP_REST_Request $request) {
    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_order_notifications';

    $limit = $request->get_param('limit');
    $mark_as_read = $request->get_param('mark_as_read') === 'true' || $request->get_param('mark_as_read') === true;

    // Obtener notificaciones no leídas
    $notifications = $wpdb->get_results($wpdb->prepare(
        "SELECT * FROM $table_name
         WHERE notified = 0
         ORDER BY created_at DESC
         LIMIT %d",
        $limit
    ), ARRAY_A);

    $count = count($notifications);

    // Formatear notificaciones con datos completos del pedido
    $formatted_notifications = [];
    foreach ($notifications as $notification) {
        $order = wc_get_order($notification['order_id']);

        if (!$order) {
            continue;
        }

        // Obtener items del pedido
        $items = [];
        foreach ($order->get_items() as $item) {
            $product = $item->get_product();
            $items[] = [
                'product_id' => $item->get_product_id(),
                'variation_id' => $item->get_variation_id(),
                'product_name' => $item->get_name(),
                'sku' => $product ? $product->get_sku() : '',
                'quantity' => $item->get_quantity(),
                'price' => floatval($item->get_total() / max(1, $item->get_quantity())),
                'total' => floatval($item->get_total()),
            ];
        }

        $formatted_notifications[] = [
            'notification_id' => (int) $notification['id'],
            'order_id' => (int) $notification['order_id'],
            'order_number' => $notification['order_number'],
            'order_status' => $notification['order_status'],
            'order_total' => floatval($notification['order_total']),
            'customer_id' => (int) $notification['customer_id'],
            'customer_name' => $notification['customer_name'],
            'created_at' => $notification['created_at'],
            'source' => $notification['source'],
            'items' => $items,
            'billing' => [
                'first_name' => $order->get_billing_first_name(),
                'last_name' => $order->get_billing_last_name(),
                'email' => $order->get_billing_email(),
                'phone' => $order->get_billing_phone(),
                'address_1' => $order->get_billing_address_1(),
                'city' => $order->get_billing_city(),
            ],
        ];
    }

    // Marcar como leídas si se solicita
    if ($mark_as_read && $count > 0) {
        $notification_ids = array_column($notifications, 'id');
        $ids_string = implode(',', array_map('intval', $notification_ids));

        $wpdb->query(
            "UPDATE $table_name
             SET notified = 1, notified_at = NOW()
             WHERE id IN ($ids_string)"
        );

        error_log("[MPBM] 📬 Marcadas {$count} notificaciones como leídas");
    }

    return new WP_REST_Response([
        'success' => true,
        'count' => $count,
        'notifications' => $formatted_notifications,
    ], 200);
}

function mpbm_mark_notifications_read_callback(WP_REST_Request $request) {
    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_order_notifications';

    $notification_ids = $request->get_param('notification_ids');

    if (empty($notification_ids)) {
        return new WP_Error('invalid_data', 'No se proporcionaron IDs de notificaciones', ['status' => 400]);
    }

    $ids_string = implode(',', array_map('intval', $notification_ids));

    $updated = $wpdb->query(
        "UPDATE $table_name
         SET notified = 1, notified_at = NOW()
         WHERE id IN ($ids_string)"
    );

    return new WP_REST_Response([
        'success' => true,
        'marked' => $updated,
    ], 200);
}

// =====================================================
// LIMPIEZA AUTOMÁTICA DE NOTIFICACIONES ANTIGUAS
// =====================================================

/**
 * Limpiar notificaciones leídas con más de 30 días
 */
add_action('mpbm_daily_cleanup', 'mpbm_cleanup_old_notifications');

function mpbm_cleanup_old_notifications() {
    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_order_notifications';

    $deleted = $wpdb->query(
        "DELETE FROM $table_name
         WHERE notified = 1
         AND notified_at < DATE_SUB(NOW(), INTERVAL 30 DAY)"
    );

    if ($deleted > 0) {
        error_log("[MPBM] 🧹 Limpiadas {$deleted} notificaciones antiguas");
    }
}

// Programar tarea diaria si no existe
if (!wp_next_scheduled('mpbm_daily_cleanup')) {
    wp_schedule_event(time(), 'daily', 'mpbm_daily_cleanup');
}
