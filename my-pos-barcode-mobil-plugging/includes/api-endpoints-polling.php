<?php
/**
 * API Endpoints para Polling Inteligente (Sin FCM)
 *
 * Endpoints ultra ligeros para reemplazar Firebase Cloud Messaging
 * Response times: <50ms
 * Response sizes: 50-500 bytes
 *
 * @package MY_POS_Barcode_Mobil
 * @version 3.2.0
 */

if (!defined('WPINC')) {
    die;
}

/**
 * Registrar rutas REST API
 */
add_action('rest_api_init', function() {
    // Endpoint 1: Check new orders (ultra ligero: ~50 bytes)
    register_rest_route('mypos/v1', '/check-new-orders', [
        'methods' => 'GET',
        'callback' => 'mpbm_check_new_orders_endpoint',
        'permission_callback' => 'mpbm_verify_api_key_light',
        'args' => [
            'since' => [
                'required' => false,
                'validate_callback' => function($param) {
                    return is_numeric($param);
                }
            ],
            'device_id' => [
                'required' => true,
                'sanitize_callback' => 'sanitize_text_field'
            ]
        ]
    ]);

    // Endpoint 2: Check critical stock (ligero: ~200 bytes)
    register_rest_route('mypos/v1', '/check-critical-stock', [
        'methods' => 'GET',
        'callback' => 'mpbm_check_critical_stock_endpoint',
        'permission_callback' => 'mpbm_verify_api_key_light',
        'args' => [
            'since' => [
                'required' => false,
                'validate_callback' => function($param) {
                    return is_numeric($param);
                }
            ]
        ]
    ]);

    // Endpoint 3: Register device (para stats)
    register_rest_route('mypos/v1', '/device/heartbeat', [
        'methods' => 'POST',
        'callback' => 'mpbm_device_heartbeat_endpoint',
        'permission_callback' => 'mpbm_verify_api_key_light',
        'args' => [
            'device_id' => [
                'required' => true,
                'sanitize_callback' => 'sanitize_text_field'
            ],
            'device_name' => [
                'required' => false,
                'sanitize_callback' => 'sanitize_text_field'
            ],
            'platform' => [
                'required' => false,
                'sanitize_callback' => 'sanitize_text_field'
            ],
            'app_version' => [
                'required' => false,
                'sanitize_callback' => 'sanitize_text_field'
            ]
        ]
    ]);

    // Endpoint 4: Get polling config (configuración dinámica)
    register_rest_route('mypos/v1', '/polling-config', [
        'methods' => 'GET',
        'callback' => 'mpbm_polling_config_endpoint',
        'permission_callback' => 'mpbm_verify_api_key_light'
    ]);
});

/**
 * Endpoint 1: Check New Orders
 * Response: ~50 bytes
 * Time: <50ms
 */
function mpbm_check_new_orders_endpoint($request) {
    global $wpdb;

    $device_id = $request->get_param('device_id');
    $since = $request->get_param('since');

    // Default: últimos 5 minutos
    if (!$since) {
        $since = time() - 300;
    }

    // Cache key
    $cache_key = 'mpbm_new_orders_' . $since;
    $cached = get_transient($cache_key);

    if ($cached !== false) {
        return rest_ensure_response($cached);
    }

    // Query ultra rápida: solo COUNT
    $count = $wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*)
         FROM {$wpdb->prefix}posts
         WHERE post_type = 'shop_order'
         AND post_status IN ('wc-processing', 'wc-pending', 'wc-on-hold')
         AND post_date > FROM_UNIXTIME(%d)",
        $since
    ));

    $response = [
        'has_new' => (int)$count > 0,
        'count' => (int)$count,
        'timestamp' => time(),
        'next_check' => time() + 300 // 5 minutos
    ];

    // Cache por 30 segundos
    set_transient($cache_key, $response, 30);

    // Actualizar heartbeat del dispositivo
    mpbm_update_device_heartbeat($device_id);

    return rest_ensure_response($response);
}

/**
 * Endpoint 2: Check Critical Stock
 * Response: ~200 bytes (hasta 20 productos)
 * Time: <100ms
 */
function mpbm_check_critical_stock_endpoint($request) {
    global $wpdb;

    $since = $request->get_param('since');

    // Default: últimos 10 minutos
    if (!$since) {
        $since = time() - 600;
    }

    // Cache key
    $cache_key = 'mpbm_critical_stock_' . $since;
    $cached = get_transient($cache_key);

    if ($cached !== false) {
        return rest_ensure_response($cached);
    }

    $table_changes = $wpdb->prefix . 'mpbm_product_changes';
    $critical_threshold = get_option('mpbm_critical_stock_threshold', 5);

    // Solo cambios críticos (priority=0 o stock <= threshold)
    $changes = $wpdb->get_results($wpdb->prepare(
        "SELECT DISTINCT product_id, new_stock, changed_at
         FROM $table_changes
         WHERE changed_at > FROM_UNIXTIME(%d)
         AND (priority = 0 OR new_stock <= %d)
         AND synced_at IS NULL
         ORDER BY priority ASC, changed_at DESC
         LIMIT 20",
        $since,
        $critical_threshold
    ));

    $critical_products = [];
    foreach ($changes as $change) {
        $critical_products[] = [
            'id' => (int)$change->product_id,
            'stock' => (int)$change->new_stock,
            'changed_at' => strtotime($change->changed_at)
        ];
    }

    $response = [
        'has_critical' => count($critical_products) > 0,
        'products' => $critical_products,
        'count' => count($critical_products),
        'timestamp' => time(),
        'next_check' => time() + 600 // 10 minutos
    ];

    // Cache por 60 segundos
    set_transient($cache_key, $response, 60);

    return rest_ensure_response($response);
}

/**
 * Endpoint 3: Device Heartbeat
 * Registra/actualiza dispositivo activo
 */
function mpbm_device_heartbeat_endpoint($request) {
    global $wpdb;

    $device_id = $request->get_param('device_id');
    $device_name = $request->get_param('device_name');
    $platform = $request->get_param('platform');
    $app_version = $request->get_param('app_version');

    $table_devices = $wpdb->prefix . 'mpbm_devices';

    // Verificar si el dispositivo existe
    $existing = $wpdb->get_var($wpdb->prepare(
        "SELECT id FROM $table_devices WHERE device_id = %s",
        $device_id
    ));

    if ($existing) {
        // Actualizar dispositivo existente
        $wpdb->update(
            $table_devices,
            [
                'device_name' => $device_name,
                'platform' => $platform,
                'app_version' => $app_version,
                'last_active' => current_time('mysql')
            ],
            ['device_id' => $device_id],
            ['%s', '%s', '%s', '%s'],
            ['%s']
        );
    } else {
        // Insertar nuevo dispositivo
        $wpdb->insert(
            $table_devices,
            [
                'device_id' => $device_id,
                'device_name' => $device_name,
                'platform' => $platform,
                'app_version' => $app_version,
                'last_active' => current_time('mysql'),
                'registered_at' => current_time('mysql')
            ],
            ['%s', '%s', '%s', '%s', '%s', '%s']
        );
    }

    return rest_ensure_response([
        'success' => true,
        'message' => 'Device heartbeat recorded',
        'timestamp' => time()
    ]);
}

/**
 * Endpoint 4: Polling Config
 * Retorna configuración dinámica para la app
 */
function mpbm_polling_config_endpoint($request) {
    $config = [
        'intervals' => [
            'orders' => (int)get_option('mpbm_polling_interval_orders', 5) * 60,      // segundos
            'stock' => (int)get_option('mpbm_polling_interval_stock', 10) * 60,       // segundos
            'delta' => (int)get_option('mpbm_polling_interval_delta', 30) * 60        // segundos
        ],
        'thresholds' => [
            'critical_stock' => (int)get_option('mpbm_critical_stock_threshold', 5),
            'low_stock' => (int)get_option('mpbm_low_stock_threshold', 10)
        ],
        'features' => [
            'polling_enabled' => true,
            'push_notifications' => false, // Cambiar a true si se implementa FCM opcional
            'delta_sync' => true,
            'offline_mode' => true
        ],
        'timestamp' => time()
    ];

    return rest_ensure_response($config);
}

/**
 * Verificación ligera de API Key
 * Sin logging excesivo para no afectar performance
 */
function mpbm_verify_api_key_light($request) {
    $api_key = $request->get_header('X-MYPOS-API-KEY');

    if (!$api_key) {
        $api_key = $request->get_param('api_key');
    }

    if (!$api_key) {
        return new WP_Error(
            'missing_api_key',
            'API Key is required',
            ['status' => 401]
        );
    }

    $stored_key = get_option('mypos_api_key');

    if (!$stored_key || $api_key !== $stored_key) {
        return new WP_Error(
            'invalid_api_key',
            'Invalid API Key',
            ['status' => 403]
        );
    }

    return true;
}

/**
 * Helper: Actualizar heartbeat del dispositivo
 * (Versión ligera, sin bloqueo)
 */
function mpbm_update_device_heartbeat($device_id) {
    if (!$device_id) {
        return;
    }

    global $wpdb;
    $table_devices = $wpdb->prefix . 'mpbm_devices';

    // Solo actualizar si no se actualizó en los últimos 5 minutos
    $last_update = get_transient('mpbm_heartbeat_' . $device_id);

    if ($last_update === false) {
        $wpdb->query($wpdb->prepare(
            "UPDATE $table_devices
             SET last_active = NOW()
             WHERE device_id = %s",
            $device_id
        ));

        // Guardar transient por 5 minutos
        set_transient('mpbm_heartbeat_' . $device_id, time(), 300);
    }
}

/**
 * Hook para marcar cambios como sincronizados
 * Se llama después de que la app confirma la sincronización
 */
add_action('rest_api_init', function() {
    register_rest_route('mypos/v1', '/mark-synced', [
        'methods' => 'POST',
        'callback' => 'mpbm_mark_changes_synced',
        'permission_callback' => 'mpbm_verify_api_key_light',
        'args' => [
            'product_ids' => [
                'required' => true,
                'validate_callback' => function($param) {
                    return is_array($param);
                },
                'sanitize_callback' => function($param) {
                    return array_map('absint', $param);
                }
            ]
        ]
    ]);
});

function mpbm_mark_changes_synced($request) {
    global $wpdb;

    $product_ids = $request->get_param('product_ids');

    if (empty($product_ids)) {
        return rest_ensure_response(['success' => false, 'message' => 'No product IDs provided']);
    }

    $table_changes = $wpdb->prefix . 'mpbm_product_changes';
    $placeholders = implode(',', array_fill(0, count($product_ids), '%d'));

    $updated = $wpdb->query($wpdb->prepare(
        "UPDATE $table_changes
         SET synced_at = NOW()
         WHERE product_id IN ($placeholders)
         AND synced_at IS NULL",
        ...$product_ids
    ));

    return rest_ensure_response([
        'success' => true,
        'marked' => $updated,
        'timestamp' => time()
    ]);
}

/**
 * Agregar headers CORS para permitir peticiones desde la app
 */
add_action('rest_api_init', function() {
    remove_filter('rest_pre_serve_request', 'rest_send_cors_headers');
    add_filter('rest_pre_serve_request', function($value) {
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
        header('Access-Control-Allow-Headers: X-MYPOS-API-KEY, Content-Type');
        return $value;
    });
});
