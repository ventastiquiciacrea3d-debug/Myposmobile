<?php
/**
 * API Endpoints para Delta Sync
 *
 * @package MPBM
 * @version 3.1.0
 */

if (!defined('WPINC')) {
    die;
}

/**
 * Endpoint: GET /mypos/v1/productos/delta
 * Retorna solo productos modificados desde un timestamp
 */
add_action('rest_api_init', function() {
    register_rest_route('mypos/v1', '/productos/delta', [
        'methods' => 'GET',
        'callback' => 'mpbm_get_delta_products',
        'permission_callback' => 'mpbm_check_api_key_permission',
        'args' => [
            'since' => [
                'required' => true,
                'validate_callback' => function($param) {
                    return is_numeric($param);
                },
            ],
            'priority' => [
                'required' => false,
                'validate_callback' => function($param) {
                    return in_array((int)$param, [0, 1, 2, 3]);
                },
            ],
            'lightweight' => [
                'required' => false,
                'default' => false,
            ],
        ],
    ]);
});

function mpbm_get_delta_products($request) {
    global $wpdb;

    $since_timestamp = (int) $request->get_param('since');
    $priority_filter = $request->get_param('priority');
    $lightweight = filter_var($request->get_param('lightweight'), FILTER_VALIDATE_BOOLEAN);

    $since_date = date('Y-m-d H:i:s', $since_timestamp);

    // Query base
    $query = "
        SELECT DISTINCT product_id, priority
        FROM {$wpdb->prefix}mpbm_product_changes
        WHERE changed_at > %s
    ";

    $params = [$since_date];

    // Filtro de prioridad (opcional)
    if ($priority_filter !== null) {
        $query .= " AND priority <= %d";
        $params[] = (int)$priority_filter;
    }

    $query .= " ORDER BY priority ASC, changed_at ASC";

    // Obtener productos modificados
    $changed_products = $wpdb->get_results($wpdb->prepare($query, $params));

    if (empty($changed_products)) {
        return new WP_REST_Response([
            'success' => true,
            'count' => 0,
            'products' => [],
            'since' => $since_date,
            'timestamp' => time(),
        ], 200);
    }

    // Obtener datos completos de productos
    $products = [];

    foreach ($changed_products as $row) {
        $product_data = mpbm_get_product_data_compact($row->product_id, $lightweight);

        if ($product_data) {
            $products[(string)$row->product_id] = $product_data;
        }
    }

    // Marcar cambios como sincronizados
    $product_ids = array_map(function($row) {
        return $row->product_id;
    }, $changed_products);

    $wpdb->query($wpdb->prepare("
        UPDATE {$wpdb->prefix}mpbm_product_changes
        SET synced_at = NOW()
        WHERE product_id IN (" . implode(',', array_map('intval', $product_ids)) . ")
          AND changed_at > %s
          AND synced_at IS NULL
    ", $since_date));

    return new WP_REST_Response([
        'success' => true,
        'count' => count($products),
        'products' => $products,
        'since' => $since_date,
        'timestamp' => time(),
    ], 200);
}

/**
 * Obtener datos de producto en formato compacto
 */
function mpbm_get_product_data_compact($product_id, $lightweight = false) {
    $product = wc_get_product($product_id);

    if (!$product) {
        return null;
    }

    // Formato compacto
    $data = [
        'id' => (int)$product_id,
        'n' => mpbm_compress_name($product->get_name()), // name
        's' => mpbm_compress_sku($product->get_sku()), // sku
        'b' => $product->get_meta('_barcode') ?: '', // barcode
        'st' => $product->get_stock_quantity() ?: 0, // stock
        'p' => (int)($product->get_price() * 100), // price in cents
        'ss' => $product->get_stock_status(), // stock_status
        't' => $product->get_type(), // type
    ];

    // Variaciones si es producto variable
    if ($product->is_type('variable') && !$lightweight) {
        $variations = [];
        $variation_ids = $product->get_children();

        foreach ($variation_ids as $var_id) {
            $variation = wc_get_product($var_id);
            if (!$variation) continue;

            $variations[] = [
                'id' => (int)$var_id,
                'sk' => mpbm_compress_sku($variation->get_sku()),
                'st' => $variation->get_stock_quantity() ?: 0,
                'p' => (int)($variation->get_price() * 100),
                'ss' => $variation->get_stock_status(),
            ];
        }

        $data['v'] = $variations;
    }

    return $data;
}

/**
 * Comprimir nombre (máx 50 caracteres)
 */
function mpbm_compress_name($name) {
    $compressed = preg_replace('/\b(producto|product|item)\b/i', '', $name);
    $compressed = preg_replace('/\s+/', ' ', $compressed);
    $compressed = trim($compressed);

    return mb_substr($compressed, 0, 50);
}

/**
 * Comprimir SKU (máx 15 caracteres)
 */
function mpbm_compress_sku($sku) {
    if (empty($sku)) return '';

    $compressed = preg_replace('/^(PROD-|ITEM-|SKU-)/', '', $sku);

    return mb_substr($compressed, 0, 15);
}

/**
 * Endpoint: POST /mypos/v1/device/register
 * Registra un dispositivo para recibir push notifications
 */
add_action('rest_api_init', function() {
    register_rest_route('mypos/v1', '/device/register', [
        'methods' => 'POST',
        'callback' => 'mpbm_register_device',
        'permission_callback' => 'mpbm_check_api_key_permission',
        'args' => [
            'fcm_token' => [
                'required' => true,
                'sanitize_callback' => 'sanitize_text_field',
            ],
            'device_id' => [
                'required' => true,
                'sanitize_callback' => 'sanitize_text_field',
            ],
        ],
    ]);
});

function mpbm_register_device($request) {
    $fcm_token = $request->get_param('fcm_token');
    $device_id = $request->get_param('device_id');

    // Obtener tokens existentes
    $device_tokens = get_option('mpbm_device_tokens', []);

    // Agregar/actualizar token
    $device_tokens[$device_id] = $fcm_token;

    // Guardar
    update_option('mpbm_device_tokens', $device_tokens);

    error_log("[MPBM] Device registered: $device_id");

    return new WP_REST_Response([
        'success' => true,
        'message' => 'Device registered successfully',
        'device_id' => $device_id,
        'total_devices' => count($device_tokens),
    ], 200);
}

/**
 * Endpoint: POST /mypos/v1/device/unregister
 * Des-registra un dispositivo
 */
add_action('rest_api_init', function() {
    register_rest_route('mypos/v1', '/device/unregister', [
        'methods' => 'POST',
        'callback' => 'mpbm_unregister_device',
        'permission_callback' => 'mpbm_check_api_key_permission',
        'args' => [
            'device_id' => [
                'required' => true,
                'sanitize_callback' => 'sanitize_text_field',
            ],
        ],
    ]);
});

function mpbm_unregister_device($request) {
    $device_id = $request->get_param('device_id');

    $device_tokens = get_option('mpbm_device_tokens', []);

    if (isset($device_tokens[$device_id])) {
        unset($device_tokens[$device_id]);
        update_option('mpbm_device_tokens', $device_tokens);

        error_log("[MPBM] Device unregistered: $device_id");

        return new WP_REST_Response([
            'success' => true,
            'message' => 'Device unregistered successfully',
        ], 200);
    }

    return new WP_REST_Response([
        'success' => false,
        'message' => 'Device not found',
    ], 404);
}
