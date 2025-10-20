<?php
/**
 * Endpoints de la API REST para la aplicación MY POS BARCODE MOBIL.
 * Versión 3.0.1 - Corregida con todas las dependencias JWT.
 */

if (!defined('WPINC')) {
    die;
}

// Dependencias de la librería JWT (asegúrate de que estas rutas sean correctas)
require_once MPBM_PLUGIN_PATH . 'includes/jwt/Firebase/JWT/JWTExceptionWithPayloadInterface.php'; // Archivo que faltaba
require_once MPBM_PLUGIN_PATH . 'includes/jwt/Firebase/JWT/ExpiredException.php';
require_once MPBM_PLUGIN_PATH . 'includes/jwt/Firebase/JWT/BeforeValidException.php';
require_once MPBM_PLUGIN_PATH . 'includes/jwt/Firebase/JWT/SignatureInvalidException.php';
require_once MPBM_PLUGIN_PATH . 'includes/jwt/Firebase/JWT/Key.php';
require_once MPBM_PLUGIN_PATH . 'includes/jwt/Firebase/JWT/JWT.php';


use \Firebase\JWT\JWT;
use \Firebase\JWT\Key;

// --- Funciones de Ayuda para JWT ---

/**
 * Obtiene la clave secreta para firmar los tokens.
 * Utiliza la sal AUTH_KEY de wp-config.php para mayor seguridad.
 */
function mpbm_get_jwt_secret() {
    if (defined('AUTH_KEY') && AUTH_KEY !== 'put your unique phrase here') {
        return AUTH_KEY;
    }
    // Fallback MUY importante: si AUTH_KEY no es segura, usa la propia API key.
    return get_option('mpbm_api_key', 'unsecure-fallback-key-please-regenerate');
}

/**
 * Crea un nuevo token JWT para un dispositivo.
 */
function mpbm_create_jwt($device_uuid) {
    $secret_key = mpbm_get_jwt_secret();
    $issuer = home_url();
    $audience = 'my-pos-mobile-app';
    $issuedAt = time();
    $expire = $issuedAt + (DAY_IN_SECONDS * 14); // Token válido por 14 días

    $payload = [
        'iss' => $issuer,
        'aud' => $audience,
        'iat' => $issuedAt,
        'nbf' => $issuedAt,
        'exp' => $expire,
        'data' => ['device_uuid' => $device_uuid]
    ];

    return JWT::encode($payload, $secret_key, 'HS256');
}

/**
 * Callback de permisos para verificar el token JWT en las solicitudes.
 */
function mpbm_permission_check_jwt(WP_REST_Request $request) {
    $auth_header = $request->get_header('Authorization');
    if (!$auth_header) {
        return new WP_Error('rest_unauthorized', 'Falta el encabezado de autorización.', ['status' => 401]);
    }

    list($token) = sscanf($auth_header, 'Bearer %s');
    if (!$token) {
        return new WP_Error('rest_unauthorized', 'Token malformado.', ['status' => 401]);
    }

    try {
        $secret = mpbm_get_jwt_secret();
        $decoded = JWT::decode($token, new Key($secret, 'HS256'));
        
        $device_uuid = $decoded->data->device_uuid ?? null;
        if(!$device_uuid){
            return new WP_Error('rest_invalid_token', 'El token no contiene un identificador de dispositivo.', ['status' => 403]);
        }
        
        $devices = get_option('mpbm_devices', []);
        $is_authorized = false;
        foreach($devices as $device){
            // Usar hash_equals para una comparación segura contra ataques de temporización
            if(isset($device['uuid']) && hash_equals($device['uuid'], $device_uuid)){
                $is_authorized = true;
                break;
            }
        }

        if(!$is_authorized){
             return new WP_Error('rest_device_revoked', 'El acceso para este dispositivo ha sido revocado.', ['status' => 403]);
        }
        
        // Adjuntar el ID de usuario al request para usarlo en los callbacks
        // $request->set_param('user_id', get_current_user_id());

        return true;

    } catch (Exception $e) {
        return new WP_Error('rest_invalid_token', $e->getMessage(), ['status' => 403]);
    }
}


// --- Registro de Endpoints ---

add_action('rest_api_init', function () {
    $numeric_validation = function($param) { return is_numeric($param); };

    // --- ENDPOINT PÚBLICO PARA REGISTRAR DISPOSITIVO Y OBTENER JWT (LA CLAVE DEL ERROR 404) ---
    register_rest_route('mypos/v1', '/register-device', [
        'methods'  => 'POST',
        'callback' => 'mpbm_register_device_callback',
        'permission_callback' => '__return_true', // Público, pero validado por la Master API Key interna.
        'args' => [
            'api_key' => ['required' => true, 'sanitize_callback' => 'sanitize_text_field'],
            'device_uuid' => ['required' => true, 'sanitize_callback' => 'sanitize_text_field'],
            'device_name' => ['required' => true, 'sanitize_callback' => 'sanitize_text_field'],
        ]
    ]);

    // El resto de tus endpoints ahora usan `mpbm_permission_check_jwt`
    $endpoints = [
        '/buscar' => [
            'methods'  => 'GET', 'callback' => 'mpbm_buscar_producto_callback_final',
            'args' => [
                'query' => [ 'required' => true, 'sanitize_callback' => 'sanitize_text_field' ],
                'per_page' => [ 'default' => 20, 'validate_callback' => $numeric_validation ],
                'page' => [ 'default' => 1, 'validate_callback' => $numeric_validation ],
                'only_in_stock' => [ 'default' => false, 'validate_callback' => 'rest_is_boolean' ]
            ]
        ],
        '/producto/(?P<id>[\d]+)' => [
            'methods' => 'GET', 'callback' => 'mpbm_get_producto_por_id_callback',
            'args' => [ 'id' => [ 'validate_callback' => $numeric_validation ] ]
        ],
        '/producto/(?P<id>[\d]+)/variaciones' => [
            'methods'  => 'GET', 'callback' => 'mpbm_get_producto_variaciones_callback',
            'args' => [ 'id' => [ 'validate_callback' => $numeric_validation ] ]
        ],
        '/pedidos' => [
            'methods' => 'GET', 'callback' => 'mpbm_get_pedidos_callback_v2',
            'args' => [ 'per_page' => [ 'default' => 20, 'validate_callback' => $numeric_validation, 'sanitize_callback' => 'absint' ], 'page' => [ 'default' => 1, 'validate_callback' => $numeric_validation, 'sanitize_callback' => 'absint' ], ]
        ],
         '/pedidos/(?P<id>[\d]+)' => [
            'methods' => 'PUT',
            'callback' => 'mpbm_update_order_callback',
            'args' => [ 'id' => [ 'validate_callback' => $numeric_validation ] ]
        ],
        '/productos-gestion-stock' => [
            'methods'  => 'GET', 'callback' => 'mpbm_get_managed_stock_products_callback',
            'args' => [ 'per_page' => [ 'default' => 1000, 'validate_callback' => $numeric_validation, 'sanitize_callback' => 'absint' ], 'page' => [ 'default' => 1, 'validate_callback' => $numeric_validation, 'sanitize_callback' => 'absint' ], ]
        ],
        '/actualizar-stock' => [
            'methods'  => 'POST', 'callback' => 'mpbm_update_stock_callback',
            'args' => [ 'updates' => [ 'required' => true, 'validate_callback' => function($param) { return is_array($param); } ] ]
        ],
        '/inventory-history' => [
            'methods' => 'GET', 'callback' => 'mpbm_get_inventory_history_callback',
        ],
        '/inventory-adjustment' => [
            'methods'  => 'POST', 'callback' => 'mpbm_submit_inventory_adjustment_callback',
            'args' => [
                'movement' => [ 'required' => true, 'validate_callback' => function($param) {
                    return is_array($param) && isset($param['id']) && isset($param['type']) && isset($param['items']) && is_array($param['items']);
                }]
            ]
        ],
        '/activar-gestion-stock-variables' => [
            'methods'  => 'POST', 'callback' => 'mpbm_stock_management_variables_callback', 
            'args' => [ 'activate' => [ 'required' => true, 'validate_callback' => 'is_bool' ] ]
        ],
        '/activar-gestion-stock-padres' => [
            'methods'  => 'POST', 'callback' => 'mpbm_stock_management_parents_callback', 
            'args' => [ 'activate' => [ 'required' => true, 'validate_callback' => 'is_bool' ] ]
        ],
    ];

    foreach ($endpoints as $route => $config) {
        $config['permission_callback'] = 'mpbm_permission_check_jwt';
        register_rest_route('mypos/v1', $route, $config);
    }
});


// --- Callbacks de los Endpoints ---

/**
 * Callback para registrar un dispositivo.
 * Valida la Master API Key y devuelve un JWT si es correcta.
 */
function mpbm_register_device_callback(WP_REST_Request $request) {
    $master_api_key = get_option('mpbm_api_key');
    $provided_key = $request->get_param('api_key');

    if (empty($master_api_key) || !hash_equals($master_api_key, $provided_key)) {
        return new WP_Error('rest_forbidden', 'Clave de API maestra inválida.', ['status' => 403]);
    }

    $device_uuid = sanitize_text_field($request->get_param('device_uuid'));
    $device_name = sanitize_text_field($request->get_param('device_name'));
    
    $devices = get_option('mpbm_devices', []);
    $found_device_index = -1;
    foreach($devices as $index => $device){
        if(isset($device['uuid']) && hash_equals($device['uuid'], $device_uuid)){
            $found_device_index = $index;
            break;
        }
    }

    if($found_device_index !== -1){
        $devices[$found_device_index]['name'] = $device_name;
        $devices[$found_device_index]['date'] = current_time('mysql');
    } else {
        $devices[] = [
            'id' => 'dev_' . substr(wp_generate_uuid4(), 0, 8),
            'name' => $device_name,
            'uuid' => $device_uuid,
            'date' => current_time('mysql')
        ];
    }

    update_option('mpbm_devices', $devices);

    $jwt = mpbm_create_jwt($device_uuid);

    return new WP_REST_Response(['status' => 'success', 'message' => 'Dispositivo registrado exitosamente.', 'jwt' => $jwt], 200);
}

// ... (El resto de tus funciones callback: mpbm_get_inventory_history_callback, etc., van aquí sin cambios)
function mpbm_get_inventory_history_callback(WP_REST_Request $request) {
    global $wpdb;
    $table_name = $wpdb->prefix . 'mpbm_inventory_log';
    $results = $wpdb->get_results("SELECT * FROM $table_name ORDER BY log_date DESC LIMIT 500", ARRAY_A);
    
    if (empty($results)) {
        return new WP_REST_Response([], 200);
    }

    $movements = [];
    foreach ($results as $row) {
        $movement_id = $row['movement_id'];

        if (!isset($movements[$movement_id])) {
            $user_info = get_userdata($row['user_id']);
            $movements[$movement_id] = [
                'id'          => $movement_id,
                'date'        => (new DateTime($row['log_date']))->format(DateTime::ISO8601),
                'type'        => $row['reason'],
                'description' => $row['description'],
                'userId'      => $row['user_id'],
                'userName'    => $user_info ? $user_info->display_name : 'Sistema',
                'isSynced'    => true,
                'items'       => [],
            ];
        }

        $movements[$movement_id]['items'][] = [
            'productId'       => $row['product_id'],
            'variationId'     => $row['variation_id'] > 0 ? $row['variation_id'] : null,
            'productName'     => $row['product_name'],
            'sku'             => $row['sku'],
            'quantityChanged' => (int)$row['quantity_changed'],
            'stockBefore'     => is_numeric($row['stock_before']) ? (int)$row['stock_before'] : null,
            'stockAfter'      => is_numeric($row['stock_after']) ? (int)$row['stock_after'] : null,
        ];
    }
    
    return new WP_REST_Response(array_values($movements), 200);
}

function mpbm_submit_inventory_adjustment_callback(WP_REST_Request $request) {
    $movement_data = $request->get_param('movement');
    if (empty($movement_data) || !is_array($movement_data)) {
        return new WP_Error('bad_request', 'Datos de movimiento inválidos.', ['status' => 400]);
    }
    
    // El user_id vendrá del token JWT si se implementa, sino se usa un admin por defecto
    $user_id = $request->get_param('user_id') ?: 1; 

    $logger = new MPBM_Inventory_Logger();
    $success = $logger->log_batch_movement_from_api($movement_data, $user_id);

    if ($success) {
        return new WP_REST_Response(['status' => 'success', 'message' => 'Ajuste de inventario procesado.'], 200);
    } else {
        return new WP_Error('processing_error', 'No se pudieron procesar todos los ítems del ajuste.', ['status' => 500]);
    }
}

function mpbm_buscar_producto_callback_final(WP_REST_Request $request) {
    global $wpdb;
    $termino = $request->get_param('query');
    $page = $request->get_param('page');
    $per_page = $request->get_param('per_page');
    $only_in_stock = rest_sanitize_boolean($request->get_param('only_in_stock'));

    $product_ids_matched = [];
    if (!empty($termino)) {
        $termino_like = '%' . $wpdb->esc_like($termino) . '%';
        $query = "SELECT DISTINCT p.ID FROM {$wpdb->posts} as p
                 LEFT JOIN {$wpdb->postmeta} as pm ON p.ID = pm.post_id AND pm.meta_key = '_sku'
                 LEFT JOIN {$wpdb->postmeta} as pm_barcode ON p.ID = pm_barcode.post_id AND pm_barcode.meta_key = '_mpbm_barcode'
                 WHERE p.post_status = 'publish' AND p.post_type IN ('product', 'product_variation')
                 AND (p.post_title LIKE %s OR pm.meta_value LIKE %s OR pm_barcode.meta_value LIKE %s)";
        
        if ($only_in_stock) {
            $query .= " AND EXISTS (SELECT 1 FROM {$wpdb->postmeta} pm_stock WHERE pm_stock.post_id = p.ID AND pm_stock.meta_key = '_stock_status' AND pm_stock.meta_value = 'instock')";
        }
        
        $product_ids_matched = $wpdb->get_col($wpdb->prepare($query, $termino_like, $termino_like, $termino_like));

        if (empty($product_ids_matched)) {
            $response = new WP_REST_Response([]);
            $response->header('X-WP-Total', 0);
            $response->header('X-WP-TotalPages', 0);
            return $response;
        }
    }
    
    $args = [
        'status'   => 'publish',
        'limit'    => $per_page,
        'page'     => $page,
        'return'   => 'ids',
        'paginate' => true,
    ];
    
    if ($only_in_stock) {
        $args['stock_status'] = 'instock';
    }

    if (!empty($product_ids_matched)) {
        $args['include'] = $product_ids_matched;
    } else {
        $args['orderby'] = 'title';
        $args['order'] = 'ASC';
    }

    $query = new WC_Product_Query($args);
    $result = $query->get_products();
    
    $product_batch_data = mpbm_get_batch_product_data($result->products, true);

    $response = new WP_REST_Response(array_values($product_batch_data));
    $response->header('X-WP-Total', $result->total);
    $response->header('X-WP-TotalPages', $result->max_num_pages);
    return $response;
}

function mpbm_get_producto_por_id_callback(WP_REST_Request $request) {
    $product_id = (int) $request->get_param('id');
    $product_data = mpbm_get_batch_product_data([$product_id], false);
    if (empty($product_data)) {
        return new WP_Error('not_found', 'Producto no encontrado.', ['status' => 404]);
    }
    return new WP_REST_Response(array_values($product_data)[0]);
}

function mpbm_get_producto_variaciones_callback(WP_REST_Request $request) {
    $product_id = (int) $request->get_param('id');
    $parent_product = wc_get_product($product_id);
    if (!$parent_product || !$parent_product->is_type('variable')) {
        return new WP_Error('not_variable_product', 'El producto no es un producto variable.', ['status' => 404]);
    }
    $variation_ids = $parent_product->get_children();
    if (empty($variation_ids)) {
        return new WP_REST_Response([]);
    }
    $resultados = mpbm_get_batch_product_data($variation_ids, false);
    return new WP_REST_Response(array_values($resultados));
}

function mpbm_get_batch_product_data(array $ids, bool $lightweight = false) {
    if (empty($ids)) return [];
    global $wpdb;
    $results = [];
    $id_placeholders = implode(',', array_fill(0, count($ids), '%d'));

    $sql = $wpdb->prepare("
        SELECT p.ID, p.post_title as name, p.post_parent as parent_id, p.post_type,
               MAX(CASE WHEN pm.meta_key = '_sku' THEN pm.meta_value END) as sku,
               MAX(CASE WHEN pm.meta_key = '_price' THEN pm.meta_value END) as price,
               MAX(CASE WHEN pm.meta_key = '_regular_price' THEN pm.meta_value END) as regular_price,
               MAX(CASE WHEN pm.meta_key = '_sale_price' THEN pm.meta_value END) as sale_price,
               MAX(CASE WHEN pm.meta_key = '_stock' THEN pm.meta_value END) as stock_quantity,
               MAX(CASE WHEN pm.meta_key = '_stock_status' THEN pm.meta_value END) as stock_status,
               MAX(CASE WHEN pm.meta_key = '_manage_stock' THEN pm.meta_value END) as manage_stock,
               MAX(CASE WHEN pm.meta_key = '_thumbnail_id' THEN pm.meta_value END) as image_id,
               MAX(CASE WHEN pm.meta_key = '_mpbm_barcode' THEN pm.meta_value END) as barcode
        FROM {$wpdb->posts} p
        LEFT JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id
        WHERE p.ID IN ($id_placeholders) AND p.post_status = 'publish'
        GROUP BY p.ID
    ", $ids);

    $products_data = $wpdb->get_results($sql, ARRAY_A);
    if (empty($products_data)) return [];

    $parent_ids = array_unique(array_filter(wp_list_pluck($products_data, 'parent_id')));
    $parent_image_ids = [];
    if (!empty($parent_ids)) {
        $parent_id_placeholders = implode(',', array_fill(0, count($parent_ids), '%d'));
        $parent_images_sql = $wpdb->prepare("SELECT post_id, meta_value FROM {$wpdb->postmeta} WHERE meta_key = '_thumbnail_id' AND post_id IN ($parent_id_placeholders)", $parent_ids);
        $parent_images_results = $wpdb->get_results($parent_images_sql, OBJECT_K);
        $parent_image_ids = wp_list_pluck($parent_images_results, 'meta_value', 'post_id');
    }

    foreach ($products_data as $p_data) {
        $product_id = $p_data['ID'];
        $product_obj = wc_get_product($product_id);
        if (!$product_obj) continue;

        $image_id = $p_data['image_id'];
        if (!$image_id && $p_data['parent_id'] > 0 && isset($parent_image_ids[$p_data['parent_id']])) {
            $image_id = $parent_image_ids[$p_data['parent_id']];
        }
        $image_url = $image_id ? wp_get_attachment_image_url($image_id, 'woocommerce_thumbnail') : null;
        
        $price = (float)($p_data['price'] ?? 0);
        $regular_price = !empty($p_data['regular_price']) ? (float)$p_data['regular_price'] : $price;
        $sale_price = !empty($p_data['sale_price']) ? (float)$p_data['sale_price'] : null;

        $data = [
            'id' => (string)$product_id, 'name' => $p_data['name'], 'sku' => $p_data['sku'] ?? '',
            'type' => $product_obj->get_type(), 'price' => $price, 
            'regular_price' => $regular_price, 'sale_price' => $sale_price,
            'on_sale' => $product_obj->is_on_sale(),
            'stock_quantity' => $p_data['stock_quantity'] !== null ? (int)$p_data['stock_quantity'] : null,
            'stock_status' => $p_data['stock_status'] ?? 'instock',
            'manage_stock' => $p_data['manage_stock'] === 'yes',
            'image' => $image_url ? ['src' => $image_url] : null,
            'parent_id' => (int)$p_data['parent_id'],
            'barcode' => $p_data['barcode'] ?: ($p_data['sku'] ?? ''),
            'source' => 'mypos_plugin_v1_search', 'attributes' => [], 'full_attributes_with_options' => []
        ];

        if (!$lightweight) {
            if ($product_obj->is_type('variable')) {
                $data['variations'] = $product_obj->get_children();
                foreach ($product_obj->get_attributes() as $slug => $attribute) {
                    if (!$attribute->get_variation()) continue;
                    $data['full_attributes_with_options'][] = ['name' => wc_attribute_label($slug), 'slug' => $attribute->get_name(), 'options' => $attribute->get_options()];
                }
            } elseif ($product_obj->is_type('variation')) {
                 foreach ($product_obj->get_variation_attributes() as $taxonomy_slug => $option_slug) {
                    $taxonomy = str_replace('attribute_', '', $taxonomy_slug);
                    $term = get_term_by('slug', $option_slug, $taxonomy);
                    $data['attributes'][] = ['name' => wc_attribute_label($taxonomy), 'option' => $term ? $term->name : $option_slug, 'slug' => $taxonomy];
                }
            }
        }
        $results[] = $data;
    }
    return $results;
}

function mpbm_get_pedidos_callback_v2(WP_REST_Request $request) {
    $query_args = [ 
        'limit' => $request['per_page'], 
        'paged' => $request['page'], 
        'orderby' => 'date', 
        'order' => 'DESC', 
        'paginate' => true, 
    ];
    if($request->get_param('search')){
        $query_args['s'] = sanitize_text_field($request->get_param('search'));
    }
    if($request->get_param('status')){
        $query_args['status'] = sanitize_text_field($request->get_param('status'));
    }

    $query = new WC_Order_Query($query_args);
    $result = $query->get_orders();
    $orders_data = array_map(function ($order) {
        $line_items = [];
        foreach ($order->get_items() as $item_id => $item) {
            $product = $item->get_product();
            $line_items[] = [ 
                'id' => $item_id, 
                'product_id' => $item->get_product_id(), 
                'variation_id' => $item->get_variation_id(), 
                'name' => $item->get_name(), 
                'sku' => $product ? $product->get_sku() : '', 
                'quantity' => $item->get_quantity(), 
                'price' => $order->get_item_total($item, false, false), 
                'subtotal' => $order->get_line_subtotal($item, false, false), 
                'meta_data' => array_map(function ($meta) { return ['display_key' => $meta->key, 'display_value' => $meta->value]; }, $item->get_meta_data()), 
            ];
        }
        $customer_name = $order->get_formatted_billing_full_name();
        return [ 
            'id' => $order->get_id(), 
            'number' => $order->get_order_number(), 
            'status' => $order->get_status(), 
            'date_created' => $order->get_date_created()->format('c'), 
            'total' => $order->get_total(), 
            'total_tax' => $order->get_total_tax(), 
            'discount_total' => $order->get_discount_total(), 
            'subtotal' => $order->get_subtotal(), 
            'customer_id' => $order->get_customer_id(), 
            'customerName' => empty($customer_name) ? 'Cliente General' : $customer_name,
            'billing' => $order->get_address('billing'), 
            'line_items' => $line_items, 
        ];
    }, $result->orders);
    
    $response = new WP_REST_Response($orders_data);
    $response->header('X-WP-Total', $result->total);
    $response->header('X-WP-TotalPages', $result->max_num_pages);
    return $response;
}

function mpbm_update_order_callback(WP_REST_Request $request) {
    $order_id = (int)$request['id'];
    $order = wc_get_order($order_id);
    if (!$order) {
        return new WP_Error('not_found', 'Pedido no encontrado.', ['status' => 404]);
    }
    $params = $request->get_json_params();
    if (isset($params['status'])) {
        $order->update_status(sanitize_text_field($params['status']), 'Actualizado desde App Móvil', true);
    }
    $order->save();
    return new WP_REST_Response(['id' => $order->get_id(), 'status' => $order->get_status()]);
}

function mpbm_get_managed_stock_products_callback(WP_REST_Request $request) {
    $args = array(
        'post_type' => array('product', 'product_variation'),
        'posts_per_page' => $request->get_param('per_page'),
        'paged' => $request->get_param('page'),
        'meta_query' => array(
            array(
                'key' => '_manage_stock',
                'value' => 'yes',
            ),
        ),
        'fields' => 'ids',
    );
    $query = new WP_Query($args);
    $product_ids = $query->posts;

    if (empty($product_ids)) {
        return new WP_REST_Response([]);
    }

    $product_batch_data = mpbm_get_batch_product_data($product_ids, true);
    return new WP_REST_Response(array_values($product_batch_data));
}

function mpbm_update_stock_callback(WP_REST_Request $request) {
    $updates = $request->get_param('updates');
    if (empty($updates) || !is_array($updates)) {
        return new WP_Error('bad_request', 'No se proporcionaron datos de actualización válidos.', ['status' => 400]);
    }

    $results = [];
    $errors = [];

    foreach ($updates as $update) {
        $product_id = isset($update['product_id']) ? absint($update['product_id']) : 0;
        $variation_id = isset($update['variation_id']) ? absint($update['variation_id']) : 0;
        $new_stock = isset($update['new_stock']) ? wc_stock_amount($update['new_stock']) : null;
        $force_manage = isset($update['force_manage']) ? (bool)$update['force_manage'] : false;

        $id_to_update = $variation_id > 0 ? $variation_id : $product_id;

        if ($id_to_update <= 0 || is_null($new_stock)) {
            $errors[] = ['id' => $id_to_update, 'error' => 'ID de producto o cantidad de stock no válidos.'];
            continue;
        }

        $product = wc_get_product($id_to_update);

        if (!$product) {
            $errors[] = ['id' => $id_to_update, 'error' => 'Producto no encontrado.'];
            continue;
        }

        try {
            if ($force_manage && !$product->get_manage_stock()) {
                $product->set_manage_stock(true);
            }
            wc_update_product_stock($product, $new_stock);
            $results[] = ['id' => $id_to_update, 'sku' => $product->get_sku(), 'status' => 'success', 'new_stock' => $new_stock];
        } catch (Exception $e) {
            $errors[] = ['id' => $id_to_update, 'sku' => $product->get_sku(), 'error' => 'Error al guardar: ' . $e->getMessage()];
        }
    }

    if (!empty($errors)) {
        return new WP_Error('batch_update_error', 'Ocurrieron errores durante la actualización en lote.', ['status' => 500, 'successes' => $results, 'failures' => $errors]);
    }

    return new WP_REST_Response(['status' => 'completed', 'results' => $results]);
}

function mpbm_stock_management_variables_callback(WP_REST_Request $request) {
    return mpbm_toggle_stock_management('variable', $request['activate']);
}
function mpbm_stock_management_parents_callback(WP_REST_Request $request) {
    return mpbm_toggle_stock_management('parent', $request['activate']);
}

function mpbm_toggle_stock_management($type, $activate) {
    global $wpdb;
    $target_value = $activate ? 'yes' : 'no';
    
    $product_ids_query = "";
    if ($type === 'parent') {
        $product_ids_query = $wpdb->prepare(
            "SELECT ID FROM {$wpdb->posts} p
             LEFT JOIN {$wpdb->term_relationships} tr ON p.ID = tr.object_id
             LEFT JOIN {$wpdb->term_taxonomy} tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
             LEFT JOIN {$wpdb->terms} t ON tt.term_id = t.term_id
             WHERE p.post_type = 'product' AND p.post_status = 'publish' AND tt.taxonomy = 'product_type' AND t.slug = 'variable'
             AND EXISTS (
                SELECT 1 FROM {$wpdb->posts} variations 
                WHERE variations.post_parent = p.ID AND variations.post_type = 'product_variation'
             )"
        );
    } else { // 'variable' (significa variaciones)
        $product_ids_query = "SELECT ID FROM {$wpdb->posts} WHERE post_type = 'product_variation' AND post_status = 'publish'";
    }

    $product_ids = $wpdb->get_col($product_ids_query);

    if (empty($product_ids)) {
        return new WP_REST_Response(['status' => 'no_action', 'message' => 'No se encontraron productos para procesar.']);
    }

    $updated_count = 0;
    foreach ($product_ids as $product_id) {
        $current_value = get_post_meta($product_id, '_manage_stock', true);
        if($current_value !== $target_value){
            update_post_meta($product_id, '_manage_stock', $target_value);
            $updated_count++;
        }
    }

    $action_text = $activate ? 'activado' : 'desactivado';
    return new WP_REST_Response(['status' => 'completed', 'message' => "Se ha $action_text la gestión de stock para $updated_count productos/variaciones."]);
}