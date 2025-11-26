<?php
/**
 * MPBM Real-Time Sync - Long Polling System (Sin Firebase)
 *
 * Sistema de sincronización en tiempo real usando Long Polling
 * No requiere dependencias externas ni servicios pagos
 *
 * @since 3.1.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class MPBM_Realtime_Sync {

    /**
     * Timeout máximo para long polling (segundos)
     */
    const MAX_TIMEOUT = 30;

    /**
     * Intervalo de verificación (microsegundos)
     */
    const CHECK_INTERVAL = 500000; // 0.5 segundos

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
        add_action('init', [$this, 'schedule_cleanup']);

        // Hooks para registrar cambios automáticamente
        add_action('woocommerce_update_product', [$this, 'track_product_change'], 10, 1);
        add_action('woocommerce_new_product', [$this, 'track_product_change'], 10, 1);
        add_action('woocommerce_delete_product', [$this, 'track_product_deletion'], 10, 1);
        add_action('woocommerce_new_order', [$this, 'track_order_change'], 10, 1);
        add_action('woocommerce_update_order', [$this, 'track_order_change'], 10, 1);
    }

    /**
     * Crear tabla para cola de cambios
     */
    public function create_changes_queue_table() {
        global $wpdb;
        $charset_collate = $wpdb->get_charset_collate();

        $sql = "CREATE TABLE IF NOT EXISTS {$wpdb->prefix}mpbm_changes_queue (
            id bigint(20) NOT NULL AUTO_INCREMENT,
            change_type varchar(20) NOT NULL,
            entity_type varchar(20) NOT NULL,
            entity_id bigint(20) NOT NULL,
            change_data longtext,
            created_at datetime DEFAULT CURRENT_TIMESTAMP,
            device_notified text,
            PRIMARY KEY (id),
            KEY idx_created (created_at),
            KEY idx_entity (entity_type, entity_id),
            KEY idx_type (change_type)
        ) $charset_collate;";

        require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
        dbDelta($sql);
    }

    /**
     * Registrar endpoints REST
     */
    public function register_endpoints() {
        // Long Polling endpoint
        register_rest_route('mypos/v1', '/poll', [
            'methods' => 'GET',
            'callback' => [$this, 'handle_long_poll'],
            'permission_callback' => 'mpbm_permission_check_jwt',
            'args' => [
                'last_id' => [
                    'default' => 0,
                    'validate_callback' => function($param) {
                        return is_numeric($param);
                    }
                ],
                'timeout' => [
                    'default' => 25,
                    'validate_callback' => function($param) {
                        return is_numeric($param) && $param <= self::MAX_TIMEOUT;
                    }
                ]
            ]
        ]);

        // Endpoint para confirmar recepción de cambios
        register_rest_route('mypos/v1', '/poll/ack', [
            'methods' => 'POST',
            'callback' => [$this, 'acknowledge_changes'],
            'permission_callback' => 'mpbm_permission_check_jwt',
            'args' => [
                'last_id' => ['required' => true]
            ]
        ]);
    }

    /**
     * Manejar Long Polling
     */
    public function handle_long_poll($request) {
        // Aumentar tiempo de ejecución y deshabilitar output buffering
        set_time_limit(self::MAX_TIMEOUT + 10);
        @ini_set('output_buffering', 'off');
        @ini_set('zlib.output_compression', 0);

        $last_id = intval($request->get_param('last_id'));
        $timeout = min(intval($request->get_param('timeout')), self::MAX_TIMEOUT);
        $device_uuid = $this->get_device_from_jwt($request);

        if (!$device_uuid) {
            return new WP_Error('invalid_token', 'Device UUID not found', ['status' => 403]);
        }

        $start_time = time();
        $iteration = 0;

        // Long polling loop
        while ((time() - $start_time) < $timeout) {

            // Buscar cambios nuevos
            $changes = $this->get_pending_changes($last_id, $device_uuid);

            if (!empty($changes)) {
                // Marcar dispositivo como notificado
                $this->mark_as_notified($changes, $device_uuid);

                return new WP_REST_Response([
                    'status' => 'changes',
                    'changes' => $changes,
                    'last_id' => end($changes)['id'],
                    'count' => count($changes),
                    'timestamp' => current_time('mysql'),
                    'server_time' => time()
                ], 200);
            }

            // Verificar si la conexión sigue activa
            if (connection_aborted()) {
                break;
            }

            // Esperar antes de verificar de nuevo
            usleep(self::CHECK_INTERVAL);

            // Limpiar cache cada 10 iteraciones para liberar memoria
            $iteration++;
            if ($iteration % 10 === 0) {
                wp_cache_flush();
            }
        }

        // Timeout alcanzado sin cambios
        return new WP_REST_Response([
            'status' => 'timeout',
            'changes' => [],
            'last_id' => $last_id,
            'timestamp' => current_time('mysql'),
            'server_time' => time()
        ], 200); // 200 OK con status=timeout (más compatible que 204)
    }

    /**
     * Obtener cambios pendientes para un dispositivo
     */
    private function get_pending_changes($last_id, $device_uuid) {
        global $wpdb;

        $changes = $wpdb->get_results($wpdb->prepare(
            "SELECT
                id,
                change_type as type,
                entity_type,
                entity_id,
                change_data as data,
                created_at as timestamp
             FROM {$wpdb->prefix}mpbm_changes_queue
             WHERE id > %d
             AND (device_notified IS NULL OR device_notified NOT LIKE %s)
             ORDER BY id ASC
             LIMIT 50",
            $last_id,
            '%' . $wpdb->esc_like($device_uuid) . '%'
        ), ARRAY_A);

        // Decodificar change_data JSON
        foreach ($changes as &$change) {
            if (!empty($change['data'])) {
                $change['data'] = json_decode($change['data'], true);
            }
        }

        return $changes;
    }

    /**
     * Marcar cambios como notificados para un dispositivo
     */
    private function mark_as_notified($changes, $device_uuid) {
        global $wpdb;

        foreach ($changes as $change) {
            $current_notified = $wpdb->get_var($wpdb->prepare(
                "SELECT device_notified FROM {$wpdb->prefix}mpbm_changes_queue WHERE id = %d",
                $change['id']
            ));

            $notified_devices = !empty($current_notified) ? json_decode($current_notified, true) : [];

            if (!is_array($notified_devices)) {
                $notified_devices = [];
            }

            if (!in_array($device_uuid, $notified_devices)) {
                $notified_devices[] = $device_uuid;

                $wpdb->update(
                    $wpdb->prefix . 'mpbm_changes_queue',
                    ['device_notified' => json_encode($notified_devices)],
                    ['id' => $change['id']],
                    ['%s'],
                    ['%d']
                );
            }
        }
    }

    /**
     * Confirmar recepción de cambios (ACK)
     */
    public function acknowledge_changes($request) {
        $last_id = intval($request->get_param('last_id'));
        $device_uuid = $this->get_device_from_jwt($request);

        if (!$device_uuid) {
            return new WP_Error('invalid_token', 'Device UUID not found', ['status' => 403]);
        }

        // Actualizar última actividad del dispositivo
        global $wpdb;
        $wpdb->update(
            $wpdb->prefix . 'mpbm_devices',
            ['last_seen' => current_time('mysql')],
            ['device_uuid' => $device_uuid],
            ['%s'],
            ['%s']
        );

        return new WP_REST_Response([
            'success' => true,
            'last_id' => $last_id
        ], 200);
    }

    /**
     * Extraer device UUID del JWT
     */
    private function get_device_from_jwt($request) {
        $auth_header = $request->get_header('Authorization');

        if (empty($auth_header)) {
            return null;
        }

        try {
            $token = str_replace('Bearer ', '', $auth_header);
            $auth = MPBM_Auth::get_instance();
            $decoded = $auth->decode_jwt($token);

            return $decoded->data->device_uuid ?? null;

        } catch (Exception $e) {
            return null;
        }
    }

    /**
     * Registrar cambio de producto
     */
    public function track_product_change($product_id) {
        global $wpdb;

        // Verificar si el producto ya tiene un cambio reciente (últimos 5 segundos)
        $recent_change = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_changes_queue
             WHERE entity_type = 'product'
             AND entity_id = %d
             AND created_at > DATE_SUB(NOW(), INTERVAL 5 SECOND)",
            $product_id
        ));

        if ($recent_change > 0) {
            // Ya existe un cambio reciente, no duplicar
            return;
        }

        // Determinar si es creación o actualización
        $exists = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_changes_queue
             WHERE entity_type = 'product'
             AND entity_id = %d
             AND change_type IN ('created', 'updated')",
            $product_id
        ));

        $change_type = ($exists > 0) ? 'updated' : 'created';

        // Obtener datos básicos del producto
        $product = wc_get_product($product_id);
        $change_data = null;

        if ($product) {
            $change_data = json_encode([
                'id' => $product->get_id(),
                'sku' => $product->get_sku(),
                'name' => $product->get_name(),
                'stock' => $product->get_stock_quantity(),
                'price' => $product->get_price()
            ]);
        }

        $wpdb->insert(
            $wpdb->prefix . 'mpbm_changes_queue',
            [
                'change_type' => $change_type,
                'entity_type' => 'product',
                'entity_id' => $product_id,
                'change_data' => $change_data,
                'created_at' => current_time('mysql')
            ],
            ['%s', '%s', '%d', '%s', '%s']
        );

        // Limpiar cache
        wp_cache_delete("product_$product_id", 'mpbm_cache');
    }

    /**
     * Registrar eliminación de producto
     */
    public function track_product_deletion($product_id) {
        global $wpdb;

        $wpdb->insert(
            $wpdb->prefix . 'mpbm_changes_queue',
            [
                'change_type' => 'deleted',
                'entity_type' => 'product',
                'entity_id' => $product_id,
                'change_data' => null,
                'created_at' => current_time('mysql')
            ],
            ['%s', '%s', '%d', '%s', '%s']
        );
    }

    /**
     * Registrar cambio de orden
     */
    public function track_order_change($order_id) {
        global $wpdb;

        $order = wc_get_order($order_id);
        if (!$order) {
            return;
        }

        $change_data = json_encode([
            'id' => $order->get_id(),
            'status' => $order->get_status(),
            'total' => $order->get_total(),
            'date' => $order->get_date_created()->format('Y-m-d H:i:s')
        ]);

        $wpdb->insert(
            $wpdb->prefix . 'mpbm_changes_queue',
            [
                'change_type' => 'updated',
                'entity_type' => 'order',
                'entity_id' => $order_id,
                'change_data' => $change_data,
                'created_at' => current_time('mysql')
            ],
            ['%s', '%s', '%d', '%s', '%s']
        );
    }

    /**
     * Programar limpieza automática de cambios antiguos
     */
    public function schedule_cleanup() {
        if (!wp_next_scheduled('mpbm_cleanup_changes_queue')) {
            wp_schedule_event(time(), 'daily', 'mpbm_cleanup_changes_queue');
        }

        add_action('mpbm_cleanup_changes_queue', [$this, 'cleanup_old_changes']);
    }

    /**
     * Limpiar cambios antiguos (más de 7 días)
     */
    public function cleanup_old_changes() {
        global $wpdb;

        $deleted = $wpdb->query(
            "DELETE FROM {$wpdb->prefix}mpbm_changes_queue
             WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)"
        );

        error_log("MPBM: Cleaned up $deleted old change notifications");
    }
}

// Inicializar
MPBM_Realtime_Sync::get_instance();
