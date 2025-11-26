<?php
/**
 * MPBM Smart Cache - Sistema de Cache sin Redis
 *
 * Cache inteligente usando WordPress Transients API
 * Funciona con cualquier hosting sin necesidad de Redis
 * Incluye compresión automática para datos grandes
 *
 * @since 3.1.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class MPBM_Smart_Cache {

    /**
     * Prefijo para claves de cache
     */
    const CACHE_PREFIX = 'mpbm_cache_';

    /**
     * Prefijo para cache comprimido
     */
    const CACHE_GZ_PREFIX = 'mpbm_gz_';

    /**
     * Umbral de compresión (bytes)
     */
    const COMPRESSION_THRESHOLD = 1000;

    /**
     * TTL por defecto (1 hora)
     */
    const DEFAULT_TTL = 3600;

    /**
     * Singleton instance
     */
    private static $instance = null;

    /**
     * Cache en memoria (para múltiples accesos en la misma request)
     */
    private $memory_cache = [];

    public static function get_instance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Registrar hook para limpiar cache expirado
        add_action('init', [$this, 'schedule_cleanup']);
        add_action('mpbm_cache_cleanup', [$this, 'cleanup_expired_cache']);
    }

    /**
     * Guardar datos en cache
     *
     * @param string $key Clave única
     * @param mixed $data Datos a cachear
     * @param int $expiration Tiempo de expiración (segundos)
     * @return bool
     */
    public function set($key, $data, $expiration = self::DEFAULT_TTL) {
        // Guardar en memoria para esta request
        $this->memory_cache[$key] = $data;

        $serialized = serialize($data);
        $size = strlen($serialized);

        // Si los datos son grandes, comprimir
        if ($size > self::COMPRESSION_THRESHOLD) {
            $compressed = gzcompress($serialized, 9);

            // Solo comprimir si realmente reduce el tamaño
            if (strlen($compressed) < $size) {
                $success = set_transient(
                    self::CACHE_GZ_PREFIX . $key,
                    $compressed,
                    $expiration
                );

                // Guardar metadata de compresión
                set_transient(
                    self::CACHE_PREFIX . $key . '_meta',
                    ['compressed' => true, 'size' => $size],
                    $expiration
                );

                return $success;
            }
        }

        // Guardar sin comprimir
        return set_transient(
            self::CACHE_PREFIX . $key,
            $data,
            $expiration
        );
    }

    /**
     * Obtener datos del cache
     *
     * @param string $key Clave única
     * @return mixed|false Datos cacheados o false si no existe
     */
    public function get($key) {
        // Verificar cache en memoria primero
        if (isset($this->memory_cache[$key])) {
            return $this->memory_cache[$key];
        }

        // Verificar si está comprimido
        $compressed = get_transient(self::CACHE_GZ_PREFIX . $key);
        if ($compressed !== false) {
            $data = unserialize(gzuncompress($compressed));
            $this->memory_cache[$key] = $data;
            return $data;
        }

        // Obtener sin comprimir
        $data = get_transient(self::CACHE_PREFIX . $key);

        if ($data !== false) {
            $this->memory_cache[$key] = $data;
        }

        return $data;
    }

    /**
     * Eliminar dato del cache
     *
     * @param string $key Clave única
     * @return bool
     */
    public function delete($key) {
        // Eliminar de memoria
        unset($this->memory_cache[$key]);

        // Eliminar transients
        delete_transient(self::CACHE_PREFIX . $key);
        delete_transient(self::CACHE_GZ_PREFIX . $key);
        delete_transient(self::CACHE_PREFIX . $key . '_meta');

        return true;
    }

    /**
     * Limpiar cache por patrón
     *
     * @param string $pattern Patrón regex (ej: 'product_*')
     * @return int Número de claves eliminadas
     */
    public function delete_by_pattern($pattern) {
        global $wpdb;

        $pattern = str_replace('*', '%', $pattern);
        $like_pattern = '%' . $wpdb->esc_like(self::CACHE_PREFIX . $pattern) . '%';

        // Obtener todas las transients que coinciden
        $transients = $wpdb->get_col($wpdb->prepare(
            "SELECT option_name FROM {$wpdb->options}
             WHERE option_name LIKE '_transient_timeout_%s'",
            $like_pattern
        ));

        $deleted = 0;

        foreach ($transients as $transient) {
            // Extraer nombre de transient
            $key = str_replace('_transient_timeout_', '', $transient);
            delete_transient($key);
            $deleted++;
        }

        // Limpiar memoria cache
        $this->memory_cache = [];

        return $deleted;
    }

    /**
     * Obtener o establecer cache (callback pattern)
     *
     * @param string $key Clave única
     * @param callable $callback Función que genera los datos
     * @param int $expiration Tiempo de expiración
     * @return mixed Datos cacheados
     */
    public function remember($key, $callback, $expiration = self::DEFAULT_TTL) {
        $cached = $this->get($key);

        if ($cached !== false) {
            return $cached;
        }

        // Generar datos si no hay cache
        $data = $callback();

        // Guardar en cache
        $this->set($key, $data, $expiration);

        return $data;
    }

    /**
     * Cache de productos con SWR
     *
     * @param array $args Argumentos de WooCommerce
     * @return array Productos
     */
    public function get_products_cached($args) {
        $cache_key = 'products_' . md5(serialize($args));

        return $this->remember($cache_key, function() use ($args) {
            return wc_get_products($args);
        }, 300); // 5 minutos
    }

    /**
     * Cache de producto individual
     *
     * @param int $product_id ID del producto
     * @return WC_Product|false
     */
    public function get_product_cached($product_id) {
        $cache_key = 'product_' . $product_id;

        return $this->remember($cache_key, function() use ($product_id) {
            return wc_get_product($product_id);
        }, 900); // 15 minutos
    }

    /**
     * Cache de búsqueda de productos
     *
     * @param string $search Término de búsqueda
     * @param int $limit Límite de resultados
     * @return array IDs de productos
     */
    public function search_products_cached($search, $limit = 20) {
        $cache_key = 'search_' . md5($search . '_' . $limit);

        return $this->remember($cache_key, function() use ($search, $limit) {
            $data_store = WC_Data_Store::load('product');
            return $data_store->search_products($search, '', true, true, $limit);
        }, 300); // 5 minutos
    }

    /**
     * Invalidar cache de producto
     *
     * @param int $product_id ID del producto
     */
    public function invalidate_product($product_id) {
        $this->delete('product_' . $product_id);

        // Invalidar búsquedas relacionadas
        $this->delete_by_pattern('search_*');
        $this->delete_by_pattern('products_*');
    }

    /**
     * Obtener estadísticas del cache
     *
     * @return array
     */
    public function get_stats() {
        global $wpdb;

        // Contar transients de MPBM
        $total_entries = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM {$wpdb->options}
             WHERE option_name LIKE %s",
            '_transient_' . self::CACHE_PREFIX . '%'
        ));

        $compressed_entries = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM {$wpdb->options}
             WHERE option_name LIKE %s",
            '_transient_' . self::CACHE_GZ_PREFIX . '%'
        ));

        // Calcular tamaño total (aproximado)
        $total_size = $wpdb->get_var($wpdb->prepare(
            "SELECT SUM(LENGTH(option_value)) FROM {$wpdb->options}
             WHERE option_name LIKE %s",
            '_transient_' . self::CACHE_PREFIX . '%'
        ));

        return [
            'total_entries' => (int) $total_entries,
            'compressed_entries' => (int) $compressed_entries,
            'total_size_bytes' => (int) $total_size,
            'total_size_mb' => round($total_size / 1048576, 2),
            'memory_cache_entries' => count($this->memory_cache)
        ];
    }

    /**
     * Programar limpieza de cache
     */
    public function schedule_cleanup() {
        if (!wp_next_scheduled('mpbm_cache_cleanup')) {
            wp_schedule_event(time(), 'daily', 'mpbm_cache_cleanup');
        }
    }

    /**
     * Limpiar cache expirado y huérfano
     */
    public function cleanup_expired_cache() {
        global $wpdb;

        // WordPress ya limpia transients expirados, pero podemos optimizar
        $wpdb->query(
            "DELETE FROM {$wpdb->options}
             WHERE option_name LIKE '_transient_timeout_mpbm_%'
             AND option_value < UNIX_TIMESTAMP()"
        );

        // Limpiar transients huérfanos (sin timeout)
        $wpdb->query(
            "DELETE a FROM {$wpdb->options} a
             LEFT JOIN {$wpdb->options} b
             ON a.option_name = REPLACE(b.option_name, '_timeout', '')
             WHERE a.option_name LIKE '_transient_mpbm_%'
             AND a.option_name NOT LIKE '_transient_timeout_%'
             AND b.option_name IS NULL"
        );

        error_log('MPBM: Cache cleanup completed');
    }

    /**
     * Limpiar todo el cache de MPBM
     */
    public function flush_all() {
        global $wpdb;

        $wpdb->query(
            "DELETE FROM {$wpdb->options}
             WHERE option_name LIKE '_transient_mpbm_%'
             OR option_name LIKE '_transient_timeout_mpbm_%'"
        );

        $this->memory_cache = [];

        return true;
    }

    /**
     * Warm up cache (precalentar)
     * Útil después de importaciones o actualizaciones masivas
     *
     * @param int $limit Límite de productos a cachear
     */
    public function warmup_product_cache($limit = 100) {
        $products = wc_get_products([
            'limit' => $limit,
            'orderby' => 'date',
            'order' => 'DESC',
            'return' => 'ids'
        ]);

        $cached = 0;

        foreach ($products as $product_id) {
            $this->get_product_cached($product_id);
            $cached++;
        }

        return $cached;
    }
}

// Inicializar
MPBM_Smart_Cache::get_instance();

/**
 * Helper functions para acceso rápido
 */
function mpbm_cache_set($key, $data, $expiration = 3600) {
    return MPBM_Smart_Cache::get_instance()->set($key, $data, $expiration);
}

function mpbm_cache_get($key) {
    return MPBM_Smart_Cache::get_instance()->get($key);
}

function mpbm_cache_delete($key) {
    return MPBM_Smart_Cache::get_instance()->delete($key);
}

function mpbm_cache_remember($key, $callback, $expiration = 3600) {
    return MPBM_Smart_Cache::get_instance()->remember($key, $callback, $expiration);
}
