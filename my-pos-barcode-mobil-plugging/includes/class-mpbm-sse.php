<?php
/**
 * MPBM Server-Sent Events (SSE)
 *
 * Sistema de notificaciones push en tiempo real usando SSE
 * Más eficiente que long polling para conexiones persistentes
 *
 * @since 3.1.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class MPBM_Server_Sent_Events {

    /**
     * Intervalo de heartbeat (segundos)
     */
    const HEARTBEAT_INTERVAL = 20;

    /**
     * Intervalo de verificación (segundos)
     */
    const CHECK_INTERVAL = 1;

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
    }

    /**
     * Registrar endpoints REST
     */
    public function register_endpoints() {
        register_rest_route('mypos/v1', '/stream', [
            'methods' => 'GET',
            'callback' => [$this, 'handle_sse_stream'],
            'permission_callback' => 'mpbm_permission_check_jwt'
        ]);
    }

    /**
     * Manejar stream SSE
     */
    public function handle_sse_stream($request) {
        // Configurar headers SSE
        header('Content-Type: text/event-stream');
        header('Cache-Control: no-cache');
        header('Connection: keep-alive');
        header('X-Accel-Buffering: no'); // Nginx
        header('Access-Control-Allow-Origin: *'); // CORS

        // Deshabilitar compresión y buffering
        @ini_set('output_buffering', 'off');
        @ini_set('zlib.output_compression', 0);
        @apache_setenv('no-gzip', 1);

        // Aumentar tiempo de ejecución
        set_time_limit(0);

        // Obtener device UUID
        $device_uuid = $this->get_device_from_jwt($request);

        if (!$device_uuid) {
            $this->send_sse_error('authentication_failed', 'Device UUID not found');
            exit;
        }

        // ID del último evento recibido por el cliente (si reconecta)
        $last_event_id = isset($_SERVER['HTTP_LAST_EVENT_ID'])
            ? intval($_SERVER['HTTP_LAST_EVENT_ID'])
            : 0;

        $this->send_sse_event('connected', [
            'device_uuid' => $device_uuid,
            'last_event_id' => $last_event_id,
            'server_time' => time()
        ], $last_event_id);

        $last_heartbeat = time();
        $iteration = 0;

        // Mantener conexión abierta
        while (true) {

            // Verificar si cliente desconectó
            if (connection_aborted()) {
                error_log("MPBM SSE: Client $device_uuid disconnected");
                break;
            }

            // Verificar cambios nuevos
            $changes = $this->get_new_changes($last_event_id, $device_uuid);

            if (!empty($changes)) {
                // Enviar eventos de cambios
                foreach ($changes as $change) {
                    $this->send_sse_event('change', $change, $change['id']);
                    $last_event_id = $change['id'];
                }

                // Flush inmediato
                $this->flush_output();
            }

            // Heartbeat periódico
            if ((time() - $last_heartbeat) >= self::HEARTBEAT_INTERVAL) {
                $this->send_sse_comment('heartbeat');
                $last_heartbeat = time();
                $this->flush_output();
            }

            // Esperar antes de siguiente verificación
            sleep(self::CHECK_INTERVAL);

            // Limpiar cache cada 60 segundos
            $iteration++;
            if ($iteration % 60 === 0) {
                wp_cache_flush();
            }
        }
    }

    /**
     * Obtener cambios nuevos desde un ID
     */
    private function get_new_changes($last_id, $device_uuid) {
        global $wpdb;

        $changes = $wpdb->get_results($wpdb->prepare(
            "SELECT
                id,
                change_type as type,
                entity_type,
                entity_id,
                change_data as data,
                UNIX_TIMESTAMP(created_at) as timestamp
             FROM {$wpdb->prefix}mpbm_changes_queue
             WHERE id > %d
             AND (device_notified IS NULL OR device_notified NOT LIKE %s)
             ORDER BY id ASC
             LIMIT 50",
            $last_id,
            '%' . $wpdb->esc_like($device_uuid) . '%'
        ), ARRAY_A);

        // Marcar como notificados
        foreach ($changes as &$change) {
            $this->mark_as_notified($change['id'], $device_uuid);

            // Decodificar change_data JSON
            if (!empty($change['data'])) {
                $change['data'] = json_decode($change['data'], true);
            }
        }

        return $changes;
    }

    /**
     * Marcar cambio como notificado
     */
    private function mark_as_notified($change_id, $device_uuid) {
        global $wpdb;

        $current_notified = $wpdb->get_var($wpdb->prepare(
            "SELECT device_notified FROM {$wpdb->prefix}mpbm_changes_queue WHERE id = %d",
            $change_id
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
                ['id' => $change_id],
                ['%s'],
                ['%d']
            );
        }
    }

    /**
     * Enviar evento SSE
     */
    private function send_sse_event($event_name, $data, $id = null) {
        if ($id !== null) {
            echo "id: $id\n";
        }

        echo "event: $event_name\n";
        echo "data: " . json_encode($data) . "\n\n";
    }

    /**
     * Enviar comentario SSE (para heartbeat)
     */
    private function send_sse_comment($message) {
        echo ": $message\n\n";
    }

    /**
     * Enviar error SSE
     */
    private function send_sse_error($error_code, $message) {
        $this->send_sse_event('error', [
            'error' => $error_code,
            'message' => $message
        ]);
        $this->flush_output();
    }

    /**
     * Flush output buffer
     */
    private function flush_output() {
        if (ob_get_level() > 0) {
            ob_flush();
        }
        flush();
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
}

// Inicializar
MPBM_Server_Sent_Events::get_instance();
