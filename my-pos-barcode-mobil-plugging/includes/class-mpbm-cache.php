<?php
/**
 * Clase para gestionar la conexión y operaciones con Redis para el caché de objetos.
 * Versión 3.1.0
 */

if (!defined('WPINC')) {
    die;
}

class MPBM_Cache {

    private static $redis = null;
    private static $is_connected = false;
    private static $prefix = 'mpbm_';

    /**
     * Intenta establecer la conexión con Redis.
     */
    private static function connect() {
        if (self::$redis !== null) {
            return;
        }

        if (!class_exists('Redis')) {
            self::$is_connected = false;
            return;
        }

        try {
            self::$redis = new Redis();
            // Intenta conectar al host y puerto por defecto.
            // Para configuraciones personalizadas, se pueden usar constantes de wp-config.php
            // como WP_REDIS_HOST y WP_REDIS_PORT.
            $host = defined('WP_REDIS_HOST') ? WP_REDIS_HOST : '127.0.0.1';
            $port = defined('WP_REDIS_PORT') ? WP_REDIS_PORT : 6379;
            
            self::$redis->connect($host, $port, 0.5); // Timeout de 0.5 segundos
            self::$is_connected = true;
            
            // Usar un prefijo basado en el hash del salt de WordPress para evitar colisiones
            if (defined('AUTH_KEY')) {
                self::$prefix = 'mpbm_' . substr(md5(AUTH_KEY), 0, 8) . '_';
            }

        } catch (Exception $e) {
            self::$redis = null;
            self::$is_connected = false;
            // Opcional: registrar el error de conexión en los logs de PHP.
            // error_log('MPBM Redis Connection Error: ' . $e->getMessage());
        }
    }

    /**
     * Obtiene un valor del caché de Redis.
     *
     * @param string $key La clave del objeto a obtener.
     * @return mixed|false Los datos decodificados o false si no se encuentra.
     */
    public static function get($key) {
        self::connect();
        if (!self::$is_connected || self::$redis === null) {
            return false;
        }
        
        $value = self::$redis->get(self::$prefix . $key);
        if ($value === false) {
            return false;
        }
        
        // Los datos se guardan como JSON, así que los decodificamos.
        return json_decode($value, true);
    }

    /**
     * Guarda un valor en el caché de Redis.
     *
     * @param string $key La clave del objeto a guardar.
     * @param mixed $data Los datos a guardar.
     * @param int $expiration Tiempo de expiración en segundos. 60 minutos por defecto.
     */
    public static function set($key, $data, $expiration = 3600) {
        self::connect();
        if (!self::$is_connected || self::$redis === null) {
            return;
        }
        
        // Guardamos los datos como una cadena JSON.
        self::$redis->setex(self::$prefix . $key, $expiration, json_encode($data));
    }

    /**
     * Elimina un valor del caché de Redis.
     *
     * @param string $key La clave a eliminar.
     */
    public static function delete($key) {
        self::connect();
        if (!self::$is_connected || self::$redis === null) {
            return;
        }
        
        self::$redis->del(self::$prefix . $key);
    }

    /**
     * Invalida el caché para un producto específico. Se usa en hooks.
     *
     * @param int $post_id ID del producto o variación.
     */
    public static function invalidate_product_cache($post_id) {
        if (get_post_type($post_id) === 'product_variation') {
            $variation = wc_get_product($post_id);
            if ($variation) {
                $parent_id = $variation->get_parent_id();
                self::delete('product_' . $parent_id);
                self::delete('variations_' . $parent_id);
            }
        } else {
             self::delete('product_' . $post_id);
        }
       
        self::delete('product_' . $post_id);
    }
}