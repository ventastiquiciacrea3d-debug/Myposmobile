<?php
/**
 * MY POS BARCODE MOBIL - Delta Sync Tracker
 * Detecta y registra cambios en productos para sincronización incremental
 *
 * @package MPBM
 * @version 3.1.0
 */

if (!defined('WPINC')) {
    die;
}

class MPBM_Delta_Sync_Tracker {

    public function __construct() {
        // Hooks para detectar cambios de stock
        add_action('woocommerce_product_set_stock', [$this, 'track_stock_change'], 10, 1);
        add_action('woocommerce_variation_set_stock', [$this, 'track_stock_change'], 10, 1);

        // Hooks para cambios de precio
        add_action('woocommerce_product_set_regular_price', [$this, 'track_price_change'], 10, 2);
        add_action('woocommerce_product_set_sale_price', [$this, 'track_price_change'], 10, 2);

        // Hooks para actualizaciones generales
        add_action('woocommerce_update_product', [$this, 'track_product_update'], 10, 1);
        add_action('woocommerce_update_product_variation', [$this, 'track_product_update'], 10, 1);

        // Hook para nuevos productos
        add_action('woocommerce_new_product', [$this, 'track_new_product'], 10, 1);
        add_action('woocommerce_new_product_variation', [$this, 'track_new_product'], 10, 1);

        // Hook para productos eliminados
        add_action('woocommerce_before_delete_product', [$this, 'track_product_deletion'], 10, 1);

        // Hook para cuando se completa un pedido (cambio masivo de stock)
        add_action('woocommerce_order_status_completed', [$this, 'track_order_stock_changes'], 10, 1);
        add_action('woocommerce_order_status_processing', [$this, 'track_order_stock_changes'], 10, 1);
    }

    /**
     * Registra cambio de stock
     */
    public function track_stock_change($product) {
        global $wpdb;

        $product_id = $product->get_id();
        $new_stock = $product->get_stock_quantity();

        // Obtener stock anterior
        $old_stock = get_post_meta($product_id, '_stock_before_change', true);

        // Solo registrar si hay cambio real
        if ($old_stock !== '' && (int)$old_stock !== (int)$new_stock) {
            // Determinar prioridad
            $priority = $this->get_change_priority('stock_change', $product, (int)$old_stock, (int)$new_stock);

            $wpdb->insert(
                $wpdb->prefix . 'mpbm_product_changes',
                [
                    'product_id' => $product_id,
                    'change_type' => 'stock_change',
                    'priority' => $priority,
                    'old_stock' => (int)$old_stock,
                    'new_stock' => (int)$new_stock,
                    'changed_at' => current_time('mysql'),
                ],
                ['%d', '%s', '%d', '%d', '%d', '%s']
            );

            // Enviar push notification
            $this->send_push_notification('stock_change', [$product_id], $priority);

            error_log("[MPBM] Stock changed for product $product_id: $old_stock → $new_stock (Priority: $priority)");
        }

        // Guardar stock actual para próxima comparación
        update_post_meta($product_id, '_stock_before_change', $new_stock);
    }

    /**
     * Registra cambios de precio
     */
    public function track_price_change($product_id, $new_price) {
        global $wpdb;

        $product = wc_get_product($product_id);
        if (!$product) return;

        $old_price = get_post_meta($product_id, '_price_before_change', true);

        if ($old_price !== '' && (float)$old_price !== (float)$new_price) {
            $priority = $this->get_change_priority('price_change', $product, null, null);

            $wpdb->insert(
                $wpdb->prefix . 'mpbm_product_changes',
                [
                    'product_id' => $product_id,
                    'change_type' => 'price_change',
                    'priority' => $priority,
                    'old_price' => (float)$old_price,
                    'new_price' => (float)$new_price,
                    'changed_at' => current_time('mysql'),
                ],
                ['%d', '%s', '%d', '%f', '%f', '%s']
            );

            error_log("[MPBM] Price changed for product $product_id: $old_price → $new_price (Priority: $priority)");
        }

        update_post_meta($product_id, '_price_before_change', $new_price);
    }

    /**
     * Registra actualización general de producto
     */
    public function track_product_update($product_id) {
        global $wpdb;

        $product = wc_get_product($product_id);
        if (!$product) return;

        // Solo registrar si no hay cambio de stock/precio reciente (evitar duplicados)
        $recent = $wpdb->get_var($wpdb->prepare("
            SELECT COUNT(*) FROM {$wpdb->prefix}mpbm_product_changes
            WHERE product_id = %d
              AND change_type IN ('stock_change', 'price_change')
              AND changed_at > DATE_SUB(NOW(), INTERVAL 5 SECOND)
        ", $product_id));

        if ($recent > 0) {
            return; // Ya se registró como stock/price change
        }

        $priority = $this->get_change_priority('update', $product, null, null);

        $wpdb->insert(
            $wpdb->prefix . 'mpbm_product_changes',
            [
                'product_id' => $product_id,
                'change_type' => 'update',
                'priority' => $priority,
                'changed_at' => current_time('mysql'),
            ],
            ['%d', '%s', '%d', '%s']
        );

        error_log("[MPBM] Product updated: $product_id (Priority: $priority)");
    }

    /**
     * Registra nuevo producto
     */
    public function track_new_product($product_id) {
        global $wpdb;

        $wpdb->insert(
            $wpdb->prefix . 'mpbm_product_changes',
            [
                'product_id' => $product_id,
                'change_type' => 'new_product',
                'priority' => 1, // ALTA prioridad
                'changed_at' => current_time('mysql'),
            ],
            ['%d', '%s', '%d', '%s']
        );

        $this->send_push_notification('new_product', [$product_id], 1);

        error_log("[MPBM] New product created: $product_id");
    }

    /**
     * Registra eliminación de producto
     */
    public function track_product_deletion($product_id) {
        global $wpdb;

        $wpdb->insert(
            $wpdb->prefix . 'mpbm_product_changes',
            [
                'product_id' => $product_id,
                'change_type' => 'delete',
                'priority' => 0, // CRÍTICA prioridad
                'changed_at' => current_time('mysql'),
            ],
            ['%d', '%s', '%d', '%s']
        );

        $this->send_push_notification('delete', [$product_id], 0);

        error_log("[MPBM] Product deleted: $product_id");
    }

    /**
     * Registra cambios cuando un pedido afecta el stock
     */
    public function track_order_stock_changes($order_id) {
        $order = wc_get_order($order_id);
        if (!$order) return;

        $affected_products = [];

        foreach ($order->get_items() as $item) {
            $product_id = $item->get_product_id();
            $variation_id = $item->get_variation_id();

            $affected_products[] = $variation_id ? $variation_id : $product_id;
        }

        if (!empty($affected_products)) {
            error_log("[MPBM] Order $order_id affected " . count($affected_products) . " products");

            // Enviar notificación con lista de productos afectados
            $this->send_push_notification('order_completed', $affected_products, 0);
        }
    }

    /**
     * Determina prioridad del cambio
     *
     * @return int 0=critical, 1=high, 2=normal, 3=low
     */
    private function get_change_priority($change_type, $product, $old_stock, $new_stock) {
        // CRÍTICO (0)
        if ($change_type === 'delete') {
            return 0;
        }

        if ($change_type === 'stock_change') {
            // Stock agotado
            if ($new_stock == 0 && $old_stock > 0) {
                return 0;
            }

            // Stock crítico (<= 5)
            if ($new_stock > 0 && $new_stock <= 5) {
                return 1; // ALTO
            }
        }

        // ALTO (1)
        if ($change_type === 'price_change') {
            return 1;
        }

        if ($change_type === 'new_product') {
            return 1;
        }

        // NORMAL (2) - default
        return 2;
    }

    /**
     * Envía push notification vía Firebase Cloud Messaging
     *
     * V2: Incluye datos mínimos en el payload para evitar API calls
     */
    private function send_push_notification($change_type, $product_ids, $priority) {
        $fcm_server_key = get_option('mpbm_fcm_server_key', '');
        if (empty($fcm_server_key)) {
            error_log('[MPBM] FCM Server Key not configured');
            return;
        }

        $device_tokens = get_option('mpbm_device_tokens', []);
        if (empty($device_tokens)) {
            error_log('[MPBM] No device tokens registered');
            return;
        }

        // Incluir datos mínimos en el payload
        $products_payload = [];

        if (!is_array($product_ids)) {
            $product_ids = [$product_ids];
        }

        foreach ($product_ids as $product_id) {
            $product = wc_get_product($product_id);
            if (!$product) continue;

            $products_payload[] = [
                'id' => (string)$product_id,
                'sku' => $product->get_sku() ?: '',
                'stock' => $product->get_stock_quantity() ?: 0,
                'price' => (float)$product->get_price(),
                'status' => $product->get_stock_status(),
            ];
        }

        // Limitar payload a 10 productos (FCM límite ~4KB)
        if (count($products_payload) > 10) {
            // Más de 10: solo notificar y usar delta endpoint
            $payload = [
                'registration_ids' => array_values($device_tokens),
                'priority' => $priority == 0 ? 'high' : 'normal',
                'data' => [
                    'type' => 'bulk_sync',
                    'change_type' => $change_type,
                    'count' => count($product_ids),
                    'priority' => $priority,
                    'use_delta' => true,
                    'timestamp' => time(),
                ],
            ];
        } else {
            // Menos de 10: incluir datos completos (CERO API calls en app)
            $payload = [
                'registration_ids' => array_values($device_tokens),
                'priority' => $priority == 0 ? 'high' : 'normal',
                'data' => [
                    'type' => 'stock_change',
                    'change_type' => $change_type,
                    'count' => count($products_payload),
                    'priority' => $priority,
                    'products' => json_encode($products_payload),
                    'timestamp' => time(),
                ],
            ];
        }

        // Enviar a FCM
        $response = wp_remote_post('https://fcm.googleapis.com/fcm/send', [
            'headers' => [
                'Authorization' => 'key=' . $fcm_server_key,
                'Content-Type' => 'application/json',
            ],
            'body' => json_encode($payload),
            'timeout' => 10,
        ]);

        if (is_wp_error($response)) {
            error_log('[MPBM] FCM notification failed: ' . $response->get_error_message());
        } else {
            $body = json_decode(wp_remote_retrieve_body($response), true);
            error_log('[MPBM] FCM notification sent. Success: ' . ($body['success'] ?? 0) . ', Failure: ' . ($body['failure'] ?? 0));
        }
    }

    /**
     * Limpia registros antiguos (> 30 días)
     */
    public function cleanup_old_changes() {
        global $wpdb;

        $deleted = $wpdb->query("
            DELETE FROM {$wpdb->prefix}mpbm_product_changes
            WHERE changed_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
        ");

        if ($deleted > 0) {
            error_log("[MPBM] Cleaned up $deleted old change records");
        }

        return $deleted;
    }
}

// Inicializar tracker
new MPBM_Delta_Sync_Tracker();

// Programar limpieza diaria
if (!wp_next_scheduled('mpbm_cleanup_delta_changes')) {
    wp_schedule_event(time(), 'daily', 'mpbm_cleanup_delta_changes');
}

add_action('mpbm_cleanup_delta_changes', function() {
    $tracker = new MPBM_Delta_Sync_Tracker();
    $tracker->cleanup_old_changes();
});
