<?php
/**
 * 🟢 PRIORIDAD 3: Endpoint Delta para Pedidos
 *
 * Endpoint ligero para obtener pedidos nuevos/modificados
 * Usado por UltraOptimizedPollingService
 *
 * @package MPBM
 * @version 3.3.0
 */

if (!defined('WPINC')) {
    die;
}

/**
 * Registrar endpoint /orders/delta
 */
add_action('rest_api_init', function() {
    register_rest_route('mypos/v1', '/orders/delta', [
        'methods' => 'GET',
        'callback' => 'mpbm_get_orders_delta',
        'permission_callback' => 'mpbm_check_api_key_permission',
        'args' => [
            'since' => [
                'required' => true,
                'validate_callback' => function($param) {
                    return is_numeric($param);
                },
                'sanitize_callback' => 'absint',
            ],
            'device_id' => [
                'required' => false,
                'sanitize_callback' => 'sanitize_text_field',
            ],
        ],
    ]);
});

/**
 * 🟢 PRIORIDAD 3: Obtener pedidos delta
 */
function mpbm_get_orders_delta($request) {
    global $wpdb;

    $since_timestamp = (int) $request->get_param('since');
    $since_date = date('Y-m-d H:i:s', $since_timestamp);

    $order_ids = $wpdb->get_col($wpdb->prepare(
        "SELECT ID
         FROM {$wpdb->prefix}posts
         WHERE post_type = 'shop_order'
         AND post_modified > %s
         ORDER BY post_modified DESC
         LIMIT 100",
        $since_date
    ));

    $orders = [];
    $products_stock = [];

    if (!empty($order_ids)) {
        foreach ($order_ids as $order_id) {
            $order = wc_get_order($order_id);
            if (!$order) continue;

            $order_data = [
                'id' => $order->get_id(),
                'status' => $order->get_status(),
                'total' => $order->get_total(),
                'date_modified' => $order->get_date_modified()->getTimestamp(),
                'items' => [],
            ];

            foreach ($order->get_items() as $item) {
                $product = $item->get_product();
                if (!$product) continue;

                $product_id = $product->get_id();
                $order_data['items'][] = [
                    'product_id' => $product_id,
                    'quantity' => $item->get_quantity(),
                ];

                $products_stock[$product_id] = [
                    'id' => $product_id,
                    'stock_quantity' => $product->get_stock_quantity(),
                ];
            }

            $orders[] = $order_data;
        }
    }

    return rest_ensure_response([
        'success' => true,
        'orders' => $orders,
        'products_stock' => $products_stock,
    ]);
}

add_action('woocommerce_new_order', function($order_id) {
    wp_update_post([
        'ID' => $order_id,
        'post_modified' => current_time('mysql'),
    ]);
}, 10, 1);
