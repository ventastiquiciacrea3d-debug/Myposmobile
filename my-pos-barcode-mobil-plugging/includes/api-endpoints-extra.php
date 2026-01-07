<?php
/**
 * ✅ ENDPOINTS ADICIONALES - MY POS BARCODE MOBIL
 *
 * Este archivo contiene los endpoints faltantes que causan errores 401/404:
 * - /mypos/v1/status - Verificación de conexión
 * - /mypos/v1/ping - Verificación pública (sin auth)
 * - /mypos/v1/customers - CRUD de clientes
 *
 * @package MPBM
 * @version 3.3.0
 */

if (!defined('WPINC')) {
    die;
}

/**
 * Registrar endpoints adicionales
 */
add_action('rest_api_init', function() {

    // =====================================================
    // ENDPOINT: /status - Verificación de conexión
    // =====================================================
    // Este endpoint es llamado por la app para verificar que la API está funcionando
    register_rest_route('mypos/v1', '/status', [
        'methods' => 'GET',
        'callback' => 'mpbm_get_status_callback',
        'permission_callback' => 'mpbm_permission_check_jwt', // Requiere autenticación
    ]);

    // Versión pública del status (solo para ping básico)
    register_rest_route('mypos/v1', '/ping', [
        'methods' => 'GET',
        'callback' => 'mpbm_get_ping_callback',
        'permission_callback' => '__return_true', // Público
    ]);

    // =====================================================
    // ENDPOINT: /customers - Lista de clientes
    // =====================================================
    register_rest_route('mypos/v1', '/customers', [
        'methods' => 'GET',
        'callback' => 'mpbm_get_customers_callback',
        'permission_callback' => 'mpbm_permission_check_jwt',
        'args' => [
            'page' => [
                'default' => 1,
                'validate_callback' => function($param) { return is_numeric($param); },
                'sanitize_callback' => 'absint',
            ],
            'per_page' => [
                'default' => 20,
                'validate_callback' => function($param) { return is_numeric($param); },
                'sanitize_callback' => 'absint',
            ],
            'search' => [
                'default' => '',
                'sanitize_callback' => 'sanitize_text_field',
            ],
            'orderby' => [
                'default' => 'registered',
                'sanitize_callback' => 'sanitize_text_field',
            ],
            'order' => [
                'default' => 'desc',
                'sanitize_callback' => 'sanitize_text_field',
            ],
        ],
    ]);

    // =====================================================
    // ENDPOINT: /customers/{id} - Obtener un cliente
    // =====================================================
    register_rest_route('mypos/v1', '/customers/(?P<id>[\d]+)', [
        'methods' => 'GET',
        'callback' => 'mpbm_get_customer_by_id_callback',
        'permission_callback' => 'mpbm_permission_check_jwt',
        'args' => [
            'id' => [
                'validate_callback' => function($param) { return is_numeric($param); },
                'sanitize_callback' => 'absint',
            ],
        ],
    ]);

    // =====================================================
    // ENDPOINT: /customers (POST) - Crear cliente
    // =====================================================
    register_rest_route('mypos/v1', '/customers', [
        'methods' => 'POST',
        'callback' => 'mpbm_create_customer_callback',
        'permission_callback' => 'mpbm_permission_check_jwt',
        'args' => [
            'email' => [
                'required' => true,
                'sanitize_callback' => 'sanitize_email',
            ],
            'first_name' => [
                'default' => '',
                'sanitize_callback' => 'sanitize_text_field',
            ],
            'last_name' => [
                'default' => '',
                'sanitize_callback' => 'sanitize_text_field',
            ],
            'billing' => [
                'default' => [],
            ],
        ],
    ]);

    // =====================================================
    // ENDPOINT: /customers/search - Buscar clientes
    // =====================================================
    register_rest_route('mypos/v1', '/customers/search', [
        'methods' => 'GET',
        'callback' => 'mpbm_search_customers_callback',
        'permission_callback' => 'mpbm_permission_check_jwt',
        'args' => [
            'query' => [
                'required' => true,
                'sanitize_callback' => 'sanitize_text_field',
            ],
            'limit' => [
                'default' => 20,
                'validate_callback' => function($param) { return is_numeric($param); },
                'sanitize_callback' => 'absint',
            ],
        ],
    ]);
});

// =====================================================
// CALLBACKS
// =====================================================

/**
 * Callback para /status - Verificación de conexión autenticada
 */
function mpbm_get_status_callback(WP_REST_Request $request) {
    global $wpdb;

    // Contar productos
    $product_count = $wpdb->get_var(
        "SELECT COUNT(*) FROM {$wpdb->posts}
         WHERE post_type IN ('product', 'product_variation')
         AND post_status = 'publish'"
    );

    // Contar órdenes recientes (últimos 30 días)
    $recent_orders = $wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM {$wpdb->posts}
         WHERE post_type = 'shop_order'
         AND post_date > %s",
        date('Y-m-d', strtotime('-30 days'))
    ));

    // Contar clientes
    $customer_count = $wpdb->get_var(
        "SELECT COUNT(*) FROM {$wpdb->users} u
         INNER JOIN {$wpdb->usermeta} um ON u.ID = um.user_id
         WHERE um.meta_key = '{$wpdb->prefix}capabilities'
         AND um.meta_value LIKE '%customer%'"
    );

    return new WP_REST_Response([
        'status' => 'ok',
        'message' => 'API MyPOS funcionando correctamente',
        'version' => '3.3.0',
        'woocommerce_active' => class_exists('WooCommerce'),
        'woocommerce_version' => defined('WC_VERSION') ? WC_VERSION : 'N/A',
        'wordpress_version' => get_bloginfo('version'),
        'site_name' => get_bloginfo('name'),
        'site_url' => home_url(),
        'timestamp' => current_time('c'),
        'timezone' => wp_timezone_string(),
        'stats' => [
            'products' => (int) $product_count,
            'recent_orders' => (int) $recent_orders,
            'customers' => (int) $customer_count,
        ],
    ], 200);
}

/**
 * Callback para /ping - Verificación pública (sin auth)
 */
function mpbm_get_ping_callback(WP_REST_Request $request) {
    return new WP_REST_Response([
        'status' => 'ok',
        'timestamp' => current_time('c'),
        'woocommerce_active' => class_exists('WooCommerce'),
    ], 200);
}

/**
 * Callback para /customers - Lista de clientes
 */
function mpbm_get_customers_callback(WP_REST_Request $request) {
    if (!class_exists('WooCommerce')) {
        return new WP_Error('woocommerce_not_found', 'WooCommerce no está activo.', ['status' => 500]);
    }

    $page = $request->get_param('page') ?: 1;
    $per_page = min($request->get_param('per_page') ?: 10, 100); // Máximo 100
    $search = $request->get_param('search');
    $orderby = $request->get_param('orderby') ?: 'registered_date';
    $order = strtolower($request->get_param('order')) === 'asc' ? 'asc' : 'desc';

    // 🔍 DEBUG: Log de parámetros recibidos
    error_log('[MPBM Customers] Parámetros: page=' . $page . ', per_page=' . $per_page . ', orderby=' . $orderby . ', order=' . $order);

    // ✅ SIMPLIFICADO: Obtener todos los usuarios con órdenes de WooCommerce
    global $wpdb;

    // Escapar el término de búsqueda una sola vez
    $search_term = !empty($search) ? $wpdb->esc_like($search) : '';

    // 🔍 Query simplificada: Buscar usuarios que tienen el role 'customer'
    // O que tienen meta_data de billing (típico de clientes WooCommerce)
    $sql = "SELECT DISTINCT u.ID, u.user_registered
            FROM {$wpdb->users} u
            LEFT JOIN {$wpdb->usermeta} um_cap ON (u.ID = um_cap.user_id AND um_cap.meta_key = '{$wpdb->prefix}capabilities')
            LEFT JOIN {$wpdb->usermeta} um_billing ON (u.ID = um_billing.user_id AND um_billing.meta_key = 'billing_email')
            WHERE (
                um_cap.meta_value LIKE '%customer%'
                OR um_billing.meta_value IS NOT NULL
                OR EXISTS (
                    SELECT 1 FROM {$wpdb->posts} p
                    WHERE p.post_type = 'shop_order'
                    AND (
                        p.post_author = u.ID
                        OR EXISTS (
                            SELECT 1 FROM {$wpdb->postmeta} pm
                            WHERE pm.post_id = p.ID
                            AND pm.meta_key = '_customer_user'
                            AND pm.meta_value = u.ID
                        )
                    )
                )
            )";

    // Agregar búsqueda si existe
    if (!empty($search_term)) {
        $sql .= " AND (
            u.user_email LIKE '%{$search_term}%'
            OR u.user_login LIKE '%{$search_term}%'
            OR u.display_name LIKE '%{$search_term}%'
            OR EXISTS (
                SELECT 1 FROM {$wpdb->usermeta} um2
                WHERE um2.user_id = u.ID
                AND (
                    (um2.meta_key = 'first_name' AND um2.meta_value LIKE '%{$search_term}%')
                    OR (um2.meta_key = 'last_name' AND um2.meta_value LIKE '%{$search_term}%')
                    OR (um2.meta_key = 'billing_first_name' AND um2.meta_value LIKE '%{$search_term}%')
                    OR (um2.meta_key = 'billing_last_name' AND um2.meta_value LIKE '%{$search_term}%')
                )
            )
        )";
    }

    // Ordenamiento
    $order_clause = 'u.user_registered DESC';
    if ($orderby === 'name') {
        $order_clause = "u.display_name {$order}";
    } elseif ($orderby === 'email') {
        $order_clause = "u.user_email {$order}";
    } elseif ($orderby === 'registered' || $orderby === 'registered_date') {
        $order_clause = "u.user_registered {$order}";
    }

    // Contar total (usar la misma query base simplificada)
    $count_sql = "SELECT COUNT(DISTINCT u.ID)
            FROM {$wpdb->users} u
            LEFT JOIN {$wpdb->usermeta} um_cap ON (u.ID = um_cap.user_id AND um_cap.meta_key = '{$wpdb->prefix}capabilities')
            LEFT JOIN {$wpdb->usermeta} um_billing ON (u.ID = um_billing.user_id AND um_billing.meta_key = 'billing_email')
            WHERE (
                um_cap.meta_value LIKE '%customer%'
                OR um_billing.meta_value IS NOT NULL
                OR EXISTS (
                    SELECT 1 FROM {$wpdb->posts} p
                    WHERE p.post_type = 'shop_order'
                    AND (
                        p.post_author = u.ID
                        OR EXISTS (
                            SELECT 1 FROM {$wpdb->postmeta} pm
                            WHERE pm.post_id = p.ID
                            AND pm.meta_key = '_customer_user'
                            AND pm.meta_value = u.ID
                        )
                    )
                )
            )";

    // Agregar el mismo filtro de búsqueda al conteo
    if (!empty($search_term)) {
        $count_sql .= " AND (
            u.user_email LIKE '%{$search_term}%'
            OR u.user_login LIKE '%{$search_term}%'
            OR u.display_name LIKE '%{$search_term}%'
            OR EXISTS (
                SELECT 1 FROM {$wpdb->usermeta} um2
                WHERE um2.user_id = u.ID
                AND (
                    (um2.meta_key = 'first_name' AND um2.meta_value LIKE '%{$search_term}%')
                    OR (um2.meta_key = 'last_name' AND um2.meta_value LIKE '%{$search_term}%')
                    OR (um2.meta_key = 'billing_first_name' AND um2.meta_value LIKE '%{$search_term}%')
                    OR (um2.meta_key = 'billing_last_name' AND um2.meta_value LIKE '%{$search_term}%')
                )
            )
        )";
    }

    $total = (int) $wpdb->get_var($count_sql);

    // Agregar paginación
    $offset = ($page - 1) * $per_page;
    $sql .= " ORDER BY {$order_clause} LIMIT {$per_page} OFFSET {$offset}";

    // Obtener IDs
    $customer_ids = $wpdb->get_col($sql);

    // 🔍 DEBUG: Log de resultados de query
    error_log('[MPBM Customers] Total clientes encontrados: ' . $total);
    error_log('[MPBM Customers] IDs obtenidos: ' . count($customer_ids));
    if (count($customer_ids) > 0) {
        error_log('[MPBM Customers] Primeros 3 IDs: ' . implode(', ', array_slice($customer_ids, 0, 3)));
    }

    // Formatear clientes
    $customers = [];
    foreach ($customer_ids as $customer_id) {
        $user = get_user_by('ID', $customer_id);
        if ($user) {
            $customers[] = mpbm_format_customer($user);
        }
    }

    // 🔍 DEBUG: Log de clientes formateados
    error_log('[MPBM Customers] Clientes formateados: ' . count($customers));

    $total_pages = ceil($total / $per_page);

    $response = new WP_REST_Response($customers);
    $response->header('X-WP-Total', $total);
    $response->header('X-WP-TotalPages', $total_pages);

    return $response;
}

/**
 * Callback para /customers/{id} - Obtener un cliente
 */
function mpbm_get_customer_by_id_callback(WP_REST_Request $request) {
    $customer_id = $request->get_param('id');

    // ID 0 es "Cliente General" - retornar datos vacíos
    if ($customer_id === 0) {
        return new WP_REST_Response([
            'id' => 0,
            'email' => '',
            'first_name' => 'Cliente',
            'last_name' => 'General',
            'username' => 'guest',
            'billing' => [
                'first_name' => 'Cliente',
                'last_name' => 'General',
                'email' => '',
                'phone' => '',
                'address_1' => '',
                'address_2' => '',
                'city' => '',
                'state' => '',
                'postcode' => '',
                'country' => '',
            ],
            'shipping' => [],
            'date_created' => null,
            'date_modified' => null,
        ], 200);
    }

    $user = get_user_by('ID', $customer_id);

    if (!$user) {
        return new WP_Error('customer_not_found', 'Cliente no encontrado.', ['status' => 404]);
    }

    return new WP_REST_Response(mpbm_format_customer($user), 200);
}

/**
 * Callback para /customers (POST) - Crear cliente
 */
function mpbm_create_customer_callback(WP_REST_Request $request) {
    $email = $request->get_param('email');
    $first_name = $request->get_param('first_name');
    $last_name = $request->get_param('last_name');
    $billing = $request->get_param('billing');

    // Verificar si el email ya existe
    if (email_exists($email)) {
        return new WP_Error('email_exists', 'Ya existe un cliente con este email.', ['status' => 400]);
    }

    // Crear el usuario
    $username = sanitize_user(current(explode('@', $email)), true);
    $counter = 1;
    $original_username = $username;
    while (username_exists($username)) {
        $username = $original_username . $counter;
        $counter++;
    }

    $password = wp_generate_password(12, true, true);

    $user_id = wp_create_user($username, $password, $email);

    if (is_wp_error($user_id)) {
        return new WP_Error('create_failed', $user_id->get_error_message(), ['status' => 500]);
    }

    // Asignar rol de customer
    $user = new WP_User($user_id);
    $user->set_role('customer');

    // Guardar nombre
    update_user_meta($user_id, 'first_name', $first_name);
    update_user_meta($user_id, 'last_name', $last_name);

    // Guardar datos de facturación
    if (!empty($billing) && is_array($billing)) {
        $billing_fields = ['first_name', 'last_name', 'company', 'address_1', 'address_2', 'city', 'state', 'postcode', 'country', 'email', 'phone'];
        foreach ($billing_fields as $field) {
            if (isset($billing[$field])) {
                update_user_meta($user_id, 'billing_' . $field, sanitize_text_field($billing[$field]));
            }
        }
    }

    // Si no se proporcionó billing_first_name, usar first_name
    if (empty(get_user_meta($user_id, 'billing_first_name', true))) {
        update_user_meta($user_id, 'billing_first_name', $first_name);
    }
    if (empty(get_user_meta($user_id, 'billing_last_name', true))) {
        update_user_meta($user_id, 'billing_last_name', $last_name);
    }
    if (empty(get_user_meta($user_id, 'billing_email', true))) {
        update_user_meta($user_id, 'billing_email', $email);
    }

    // Obtener el usuario actualizado
    $user = get_user_by('ID', $user_id);

    return new WP_REST_Response(mpbm_format_customer($user), 201);
}

/**
 * Callback para /customers/search - Buscar clientes
 */
function mpbm_search_customers_callback(WP_REST_Request $request) {
    global $wpdb;

    $query = $request->get_param('query');
    $limit = min($request->get_param('limit'), 50);

    // Buscar en email, nombre, apellido y teléfono
    $search_term = '%' . $wpdb->esc_like($query) . '%';

    $user_ids = $wpdb->get_col($wpdb->prepare(
        "SELECT DISTINCT u.ID
         FROM {$wpdb->users} u
         LEFT JOIN {$wpdb->usermeta} um_fn ON u.ID = um_fn.user_id AND um_fn.meta_key = 'first_name'
         LEFT JOIN {$wpdb->usermeta} um_ln ON u.ID = um_ln.user_id AND um_ln.meta_key = 'last_name'
         LEFT JOIN {$wpdb->usermeta} um_phone ON u.ID = um_phone.user_id AND um_phone.meta_key = 'billing_phone'
         LEFT JOIN {$wpdb->usermeta} um_role ON u.ID = um_role.user_id AND um_role.meta_key = '{$wpdb->prefix}capabilities'
         WHERE um_role.meta_value LIKE %s
         AND (
             u.user_email LIKE %s
             OR u.display_name LIKE %s
             OR um_fn.meta_value LIKE %s
             OR um_ln.meta_value LIKE %s
             OR um_phone.meta_value LIKE %s
             OR CONCAT(um_fn.meta_value, ' ', um_ln.meta_value) LIKE %s
         )
         LIMIT %d",
        '%customer%',
        $search_term,
        $search_term,
        $search_term,
        $search_term,
        $search_term,
        $search_term,
        $limit
    ));

    $customers = [];
    foreach ($user_ids as $user_id) {
        $user = get_user_by('ID', $user_id);
        if ($user) {
            $customers[] = mpbm_format_customer($user);
        }
    }

    return new WP_REST_Response($customers, 200);
}

/**
 * Helper: Formatear datos de cliente
 */
function mpbm_format_customer($user) {
    $user_id = $user->ID;

    return [
        'id' => $user_id,
        'email' => $user->user_email,
        'first_name' => get_user_meta($user_id, 'first_name', true),
        'last_name' => get_user_meta($user_id, 'last_name', true),
        'username' => $user->user_login,
        'date_created' => $user->user_registered,
        'date_modified' => null, // WordPress no trackea esto por defecto
        'billing' => [
            'first_name' => get_user_meta($user_id, 'billing_first_name', true),
            'last_name' => get_user_meta($user_id, 'billing_last_name', true),
            'company' => get_user_meta($user_id, 'billing_company', true),
            'address_1' => get_user_meta($user_id, 'billing_address_1', true),
            'address_2' => get_user_meta($user_id, 'billing_address_2', true),
            'city' => get_user_meta($user_id, 'billing_city', true),
            'state' => get_user_meta($user_id, 'billing_state', true),
            'postcode' => get_user_meta($user_id, 'billing_postcode', true),
            'country' => get_user_meta($user_id, 'billing_country', true),
            'email' => get_user_meta($user_id, 'billing_email', true) ?: $user->user_email,
            'phone' => get_user_meta($user_id, 'billing_phone', true),
        ],
        'shipping' => [
            'first_name' => get_user_meta($user_id, 'shipping_first_name', true),
            'last_name' => get_user_meta($user_id, 'shipping_last_name', true),
            'company' => get_user_meta($user_id, 'shipping_company', true),
            'address_1' => get_user_meta($user_id, 'shipping_address_1', true),
            'address_2' => get_user_meta($user_id, 'shipping_address_2', true),
            'city' => get_user_meta($user_id, 'shipping_city', true),
            'state' => get_user_meta($user_id, 'shipping_state', true),
            'postcode' => get_user_meta($user_id, 'shipping_postcode', true),
            'country' => get_user_meta($user_id, 'shipping_country', true),
        ],
        'avatar_url' => get_avatar_url($user_id, ['size' => 96]),
        'orders_count' => mpbm_get_customer_orders_count($user_id),
        'total_spent' => mpbm_get_customer_total_spent($user_id),
    ];
}

/**
 * Helper: Obtener cantidad de órdenes de un cliente
 */
function mpbm_get_customer_orders_count($user_id) {
    if (!class_exists('WooCommerce')) return 0;

    $customer = new WC_Customer($user_id);
    return $customer->get_order_count();
}

/**
 * Helper: Obtener total gastado por un cliente
 */
function mpbm_get_customer_total_spent($user_id) {
    if (!class_exists('WooCommerce')) return '0.00';

    $customer = new WC_Customer($user_id);
    return $customer->get_total_spent();
}
