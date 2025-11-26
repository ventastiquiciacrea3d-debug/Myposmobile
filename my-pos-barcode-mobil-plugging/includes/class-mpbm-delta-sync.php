<?php
/**
 * MPBM Delta Sync V2 - Sincronización Incremental Optimizada
 *
 * Sistema de sincronización delta que envía solo cambios
 * Reduce transferencia de datos en un 95%
 *
 * @since 3.1.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class MPBM_Delta_Sync_V2 {

    /**
     * Límite de cambios por request
     */
    const MAX_CHANGES = 1000;

    /**
     * Umbral para compresión (bytes)
     */
    const COMPRESSION_THRESHOLD = 5000;

    /**
     * Singleton instance
     */
    private static $instance = null;

    public static function get_instance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        add_action('rest_api_init', [$this, 'register_endpoints']);

        // Hooks para tracking automático
        add_action('woocommerce_update_product', [$this, 'track_product_change'], 10, 1);
        add_action('woocommerce_new_product', [$this, 'track_product_creation'], 10, 1);
        add_action('woocommerce_delete_product', [$this, 'track_product_deletion'], 10, 1);
        add_action('woocommerce_update_product_variation', [$this, 'track_variation_change'], 10, 1);
    }

    /**
     * Crear tabla para tracking de cambios
     */
    public function create_delta_table() {
        global $wpdb;
        $charset_collate = $wpdb->get_charset_collate();

        $sql = "CREATE TABLE IF NOT EXISTS {$wpdb->prefix}mpbm_product_changes (
            id bigint(20) NOT NULL AUTO_INCREMENT,
            product_id bigint(20) NOT NULL,
            change_type ENUM('created', 'updated', 'deleted') NOT NULL,
            change_timestamp int(11) NOT NULL,
            change_data longtext,
            hash varchar(32),
            PRIMARY KEY (id),
            KEY idx_timestamp (change_timestamp),
            KEY idx_product_timestamp (product_id, change_timestamp),
            KEY idx_type_timestamp (change_type, change_timestamp)
        ) $charset_collate;";

        require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
        dbDelta($sql);
    }

    /**
     * Registrar endpoints REST
     */
    public function register_endpoints() {
        // Delta Sync endpoint principal
        register_rest_route('mypos/v1', '/sync/delta', [
            'methods' => 'GET',
            'callback' => [$this, 'get_delta'],
            'permission_callback' => 'mpbm_permission_check_jwt',
            'args' => [
                'since' => [
                    'required' => true,
                    'validate_callback' => function($param) {
                        return is_numeric($param) && $param > 0;
                    }
                ],
                'type' => [
                    'default' => 'compact',
                    'validate_callback' => function($param) {
                        return in_array($param, ['compact', 'full']);
                    }
                ],
                'limit' => [
                    'default' => 100,
                    'validate_callback' => function($param) {
                        return is_numeric($param) && $param > 0 && $param <= self::MAX_CHANGES;
                    }
                ]
            ]
        ]);

        // Endpoint para obtener detalles completos de productos específicos
        register_rest_route('mypos/v1', '/sync/products/batch', [
            'methods' => 'POST',
            'callback' => [$this, 'get_products_batch'],
            'permission_callback' => 'mpbm_permission_check_jwt',
            'args' => [
                'ids' => [
                    'required' => true,
                    'validate_callback' => function($param) {
                        return is_array($param) && count($param) <= 100;
                    }
                ]
            ]
        ]);

        // Stats endpoint
        register_rest_route('mypos/v1', '/sync/stats', [
            'methods' => 'GET',
            'callback' => [$this, 'get_sync_stats'],
            'permission_callback' => 'mpbm_permission_check_jwt'
        ]);
    }

    /**
     * Obtener cambios delta
     */
    public function get_delta($request) {
        global $wpdb;

        $since = (int) $request->get_param('since');
        $type = $request->get_param('type');
        $limit = (int) $request->get_param('limit');

        // Usar cache para queries repetidas
        $cache_key = "delta_{$since}_{$type}_{$limit}";
        $cached = mpbm_cache_get($cache_key);

        if ($cached !== false) {
            return $cached;
        }

        // Query optimizada con índices
        $changes = $wpdb->get_results($wpdb->prepare(
            "SELECT
                id,
                product_id as p_id,
                change_type as c_type,
                change_timestamp as ts,
                change_data as data,
                hash
             FROM {$wpdb->prefix}mpbm_product_changes
             WHERE change_timestamp > %d
             ORDER BY change_timestamp ASC
             LIMIT %d",
            $since,
            $limit
        ), ARRAY_A);

        $has_more = count($changes) >= $limit;
        $response = [];

        if ($type === 'compact') {
            // Formato compacto: solo IDs y metadata
            $response = [
                'changes' => array_map(function($c) {
                    return [
                        'i' => (int) $c['p_id'],          // id
                        't' => $c['c_type'],               // type
                        'ts' => (int) $c['ts'],            // timestamp
                        'h' => $c['hash']                  // hash
                    ];
                }, $changes),
                'server_time' => time(),
                'has_more' => $has_more
            ];
        } else {
            // Formato completo: incluir datos del producto
            $response = [
                'changes' => array_map(function($c) {
                    $change = [
                        'id' => (int) $c['p_id'],
                        'type' => $c['c_type'],
                        'timestamp' => (int) $c['ts'],
                        'hash' => $c['hash']
                    ];

                    // Incluir datos si no es eliminación
                    if ($c['c_type'] !== 'deleted' && !empty($c['data'])) {
                        $change['data'] = json_decode($c['data'], true);
                    }

                    return $change;
                }, $changes),
                'server_time' => time(),
                'has_more' => $has_more
            ];
        }

        // Cachear resultado por 10 segundos
        mpbm_cache_set($cache_key, $response, 10);

        // Comprimir respuesta si es grande
        $json = json_encode($response);
        if (strlen($json) > self::COMPRESSION_THRESHOLD) {
            $this->send_compressed_response($response);
            exit;
        }

        return $response;
    }

    /**
     * Obtener productos en batch (para cambios detectados)
     */
    public function get_products_batch($request) {
        $ids = $request->get_param('ids');

        if (empty($ids) || !is_array($ids)) {
            return new WP_Error('invalid_ids', 'IDs inválidos', ['status' => 400]);
        }

        $products = [];

        foreach ($ids as $product_id) {
            // Usar cache inteligente
            $product = MPBM_Smart_Cache::get_instance()->get_product_cached($product_id);

            if ($product) {
                $products[] = $this->format_product_compact($product);
            }
        }

        $response = [
            'products' => $products,
            'count' => count($products),
            'requested' => count($ids),
            'server_time' => time()
        ];

        // Comprimir si es necesario
        $json = json_encode($response);
        if (strlen($json) > self::COMPRESSION_THRESHOLD) {
            $this->send_compressed_response($response);
            exit;
        }

        return $response;
    }

    /**
     * Formatear producto de forma compacta
     */
    private function format_product_compact($product) {
        $data = [
            'id' => $product->get_id(),
            'name' => $product->get_name(),
            'sku' => $product->get_sku(),
            'price' => $product->get_price(),
            'regular_price' => $product->get_regular_price(),
            'sale_price' => $product->get_sale_price(),
            'stock' => $product->get_stock_quantity(),
            'stock_status' => $product->get_stock_status(),
            'manage_stock' => $product->get_manage_stock(),
            'type' => $product->get_type(),
            'status' => $product->get_status(),
            'updated' => $product->get_date_modified() ? $product->get_date_modified()->getTimestamp() : null
        ];

        // Incluir imagen solo URL (no metadata completa)
        $image_id = $product->get_image_id();
        if ($image_id) {
            $data['image'] = wp_get_attachment_url($image_id);
        }

        // Variaciones (solo IDs)
        if ($product->is_type('variable')) {
            $data['variations'] = $product->get_children();
        }

        return $data;
    }

    /**
     * Tracking de creación de producto
     */
    public function track_product_creation($product_id) {
        $this->track_change($product_id, 'created');
    }

    /**
     * Tracking de actualización de producto
     */
    public function track_product_change($product_id) {
        // Verificar si ya existe un registro de creación/actualización
        global $wpdb;

        $exists = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_product_changes
             WHERE product_id = %d
             AND change_type IN ('created', 'updated')",
            $product_id
        ));

        $change_type = ($exists > 0) ? 'updated' : 'created';
        $this->track_change($product_id, $change_type);
    }

    /**
     * Tracking de eliminación de producto
     */
    public function track_product_deletion($product_id) {
        $this->track_change($product_id, 'deleted', null);

        // Invalidar cache
        MPBM_Smart_Cache::get_instance()->invalidate_product($product_id);
    }

    /**
     * Tracking de cambio en variación
     */
    public function track_variation_change($variation_id) {
        $variation = wc_get_product($variation_id);

        if ($variation && $variation->is_type('variation')) {
            // Trackear tanto la variación como el producto padre
            $this->track_change($variation_id, 'updated');
            $this->track_change($variation->get_parent_id(), 'updated');
        }
    }

    /**
     * Trackear cambio genérico
     */
    private function track_change($product_id, $change_type, $data = null) {
        global $wpdb;

        // Evitar duplicados recientes (últimos 3 segundos)
        $recent = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_product_changes
             WHERE product_id = %d
             AND change_type = %s
             AND change_timestamp > %d",
            $product_id,
            $change_type,
            time() - 3
        ));

        if ($recent > 0) {
            return; // Ya hay un cambio reciente registrado
        }

        // Obtener datos del producto si no se proporcionan
        if ($data === null && $change_type !== 'deleted') {
            $product = wc_get_product($product_id);

            if ($product) {
                $data = $this->format_product_compact($product);
            }
        }

        $data_json = $data ? json_encode($data) : null;
        $hash = $data_json ? md5($data_json) : null;

        // Insertar registro
        $wpdb->insert(
            $wpdb->prefix . 'mpbm_product_changes',
            [
                'product_id' => $product_id,
                'change_type' => $change_type,
                'change_timestamp' => time(),
                'change_data' => $data_json,
                'hash' => $hash
            ],
            ['%d', '%s', '%d', '%s', '%s']
        );

        // Notificar a través del sistema de real-time sync
        do_action('mpbm_product_changed', $product_id, $change_type);
    }

    /**
     * Obtener estadísticas de sincronización
     */
    public function get_sync_stats($request) {
        global $wpdb;

        $stats = [
            'total_changes' => (int) $wpdb->get_var(
                "SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_product_changes"
            ),
            'changes_last_hour' => (int) $wpdb->get_var($wpdb->prepare(
                "SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_product_changes
                 WHERE change_timestamp > %d",
                time() - 3600
            )),
            'changes_last_day' => (int) $wpdb->get_var($wpdb->prepare(
                "SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_product_changes
                 WHERE change_timestamp > %d",
                time() - 86400
            )),
            'oldest_change' => (int) $wpdb->get_var(
                "SELECT MIN(change_timestamp) FROM {$wpdb->prefix}mpbm_product_changes"
            ),
            'newest_change' => (int) $wpdb->get_var(
                "SELECT MAX(change_timestamp) FROM {$wpdb->prefix}mpbm_product_changes"
            ),
            'server_time' => time()
        ];

        // Distribución por tipo
        $type_distribution = $wpdb->get_results(
            "SELECT change_type, COUNT(*) as count
             FROM {$wpdb->prefix}mpbm_product_changes
             GROUP BY change_type",
            ARRAY_A
        );

        $stats['by_type'] = [];
        foreach ($type_distribution as $row) {
            $stats['by_type'][$row['change_type']] = (int) $row['count'];
        }

        return $stats;
    }

    /**
     * Enviar respuesta comprimida
     */
    private function send_compressed_response($data) {
        $json = json_encode($data);
        $compressed = gzencode($json, 6);

        $ratio = round((1 - strlen($compressed) / strlen($json)) * 100, 1);

        header('Content-Encoding: gzip');
        header('Content-Type: application/json; charset=utf-8');
        header('X-Compression-Ratio: ' . $ratio . '%');
        header('X-Original-Size: ' . strlen($json));
        header('X-Compressed-Size: ' . strlen($compressed));

        echo $compressed;
    }

    /**
     * Limpiar cambios antiguos (más de 30 días)
     */
    public function cleanup_old_changes() {
        global $wpdb;

        $deleted = $wpdb->query($wpdb->prepare(
            "DELETE FROM {$wpdb->prefix}mpbm_product_changes
             WHERE change_timestamp < %d",
            time() - (30 * 86400) // 30 días
        ));

        error_log("MPBM Delta Sync: Cleaned up $deleted old changes");

        return $deleted;
    }
}

// Inicializar
MPBM_Delta_Sync_V2::get_instance();
