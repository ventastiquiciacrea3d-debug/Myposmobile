<?php
if (!defined('WPINC')) { die; }

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

class MPBM_Auth {

    const JWT_ALGORITHM = 'HS256';

    public function __construct() {
        // No se necesitan ganchos aquí, los endpoints lo llamarán directamente.
    }

    public function get_jwt_secret() {
        $secret = get_option('mpbm_jwt_secret');
        if (empty($secret)) {
            $secret = wp_generate_password(64, true, true);
            update_option('mpbm_jwt_secret', $secret);
        }
        return $secret;
    }

    public function register_device($request) {
        $master_key = get_option('mpbm_api_key');
        $sent_key = $request->get_param('api_key');
        $device_uuid = sanitize_text_field($request->get_param('device_uuid'));
        $device_name = sanitize_text_field($request->get_param('device_name'));

        if (empty($sent_key) || !hash_equals($master_key, $sent_key)) {
            return new WP_Error('rest_forbidden', 'Clave de API maestra inválida.', ['status' => 401]);
        }
        if (empty($device_uuid) || empty($device_name)) {
            return new WP_Error('bad_request', 'UUID y nombre del dispositivo son requeridos.', ['status' => 400]);
        }

        $jti = wp_generate_uuid4();
        $issued_at = time();
        $token = JWT::encode(
            [
                'iss' => get_bloginfo('url'),
                'iat' => $issued_at,
                'jti' => $jti,
                'data' => [
                    'device_uuid' => $device_uuid
                ]
            ],
            $this->get_jwt_secret(),
            self::JWT_ALGORITHM
        );

        global $wpdb;
        $table_name = $wpdb->prefix . 'mpbm_devices';
        $now = current_time('mysql');

        $result = $wpdb->replace(
            $table_name,
            [
                'device_uuid'   => $device_uuid,
                'device_name'   => $device_name,
                'jti'           => $jti,
                'last_login'    => $now,
                'registered_at' => $now,
            ],
            ['%s', '%s', '%s', '%s', '%s']
        );

        if ($result === false) {
             return new WP_Error('db_error', 'No se pudo registrar el dispositivo en la base de datos.', ['status' => 500]);
        }

        return new WP_REST_Response([
            'status' => 'success',
            'message' => 'Dispositivo registrado. Utiliza este token para futuras solicitudes.',
            'jwt' => $token
        ], 200);
    }

    public function permission_check($request) {
        $auth_header = $request->get_header('Authorization');
        if (!$auth_header) {
            return new WP_Error('rest_unauthorized', 'Falta el encabezado de autorización.', ['status' => 401]);
        }

        list($token) = sscanf($auth_header, 'Bearer %s');
        if (!$token) {
            return new WP_Error('rest_unauthorized', 'Token malformado.', ['status' => 401]);
        }
        
        try {
            $decoded = JWT::decode($token, new Key($this->get_jwt_secret(), self::JWT_ALGORITHM));
        } catch (Exception $e) {
            return new WP_Error('rest_invalid_token', $e->getMessage(), ['status' => 403]);
        }

        $device_uuid = $decoded->data->device_uuid ?? null;
        $jti = $decoded->jti ?? null;
        if (empty($device_uuid) || empty($jti)) {
             return new WP_Error('rest_invalid_token', 'Token inválido: faltan datos del dispositivo.', ['status' => 403]);
        }

        global $wpdb;
        $table_name = $wpdb->prefix . 'mpbm_devices';
        $stored_jti = $wpdb->get_var($wpdb->prepare("SELECT jti FROM $table_name WHERE device_uuid = %s", $device_uuid));

        if (!$stored_jti || !hash_equals($stored_jti, $jti)) {
            return new WP_Error('rest_token_revoked', 'El token ha sido revocado o el dispositivo no está registrado.', ['status' => 403]);
        }
        
        // Asignar el ID de usuario del administrador principal para los logs
        wp_set_current_user(1); 
        return true;
    }
}