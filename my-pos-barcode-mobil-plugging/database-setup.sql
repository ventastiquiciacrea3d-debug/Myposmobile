-- MY POS BARCODE MOBILE - Database Setup
-- Version: 3.1.0
-- Fecha: 2025-01-24
--
-- Este archivo contiene todas las tablas e índices necesarios
-- para las optimizaciones del plugin

-- ============================================
-- TABLA: Cola de Cambios para Real-Time Sync
-- ============================================
CREATE TABLE IF NOT EXISTS `wp_mpbm_changes_queue` (
    `id` bigint(20) NOT NULL AUTO_INCREMENT,
    `change_type` varchar(20) NOT NULL,
    `entity_type` varchar(20) NOT NULL,
    `entity_id` bigint(20) NOT NULL,
    `change_data` longtext,
    `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
    `device_notified` text,
    PRIMARY KEY (`id`),
    KEY `idx_created` (`created_at`),
    KEY `idx_entity` (`entity_type`, `entity_id`),
    KEY `idx_type` (`change_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- TABLA: Tracking de Cambios para Delta Sync
-- ============================================
CREATE TABLE IF NOT EXISTS `wp_mpbm_product_changes` (
    `id` bigint(20) NOT NULL AUTO_INCREMENT,
    `product_id` bigint(20) NOT NULL,
    `change_type` ENUM('created', 'updated', 'deleted') NOT NULL,
    `change_timestamp` int(11) NOT NULL,
    `change_data` longtext,
    `hash` varchar(32),
    PRIMARY KEY (`id`),
    KEY `idx_timestamp` (`change_timestamp`),
    KEY `idx_product_timestamp` (`product_id`, `change_timestamp`),
    KEY `idx_type_timestamp` (`change_type`, `change_timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- TABLA: Log de API para Monitoring
-- ============================================
CREATE TABLE IF NOT EXISTS `wp_mpbm_api_log` (
    `id` bigint(20) NOT NULL AUTO_INCREMENT,
    `endpoint` varchar(255) NOT NULL,
    `duration_ms` decimal(10,2) NOT NULL,
    `status_code` int(3) NOT NULL,
    `device_uuid` varchar(36),
    `timestamp` datetime NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_timestamp` (`timestamp`),
    KEY `idx_endpoint` (`endpoint`),
    KEY `idx_device` (`device_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- ÍNDICES OPTIMIZADOS: wp_mpbm_inventory_log
-- ============================================
-- Verificar si la tabla existe antes de agregar índices
SET @table_exists = (SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
    AND table_name = 'wp_mpbm_inventory_log');

-- Agregar índices solo si la tabla existe
SET @sql = IF(@table_exists > 0,
    'ALTER TABLE `wp_mpbm_inventory_log`
     ADD INDEX IF NOT EXISTS `idx_product_date` (`product_id`, `log_date` DESC),
     ADD INDEX IF NOT EXISTS `idx_user_date` (`user_id`, `log_date` DESC),
     ADD INDEX IF NOT EXISTS `idx_reason` (`reason`),
     ADD INDEX IF NOT EXISTS `idx_date_reason` (`log_date`, `reason`)',
    'SELECT "Table wp_mpbm_inventory_log does not exist, skipping indices"');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================
-- COLUMNA ADICIONAL: wp_mpbm_devices
-- ============================================
-- Agregar columnas para webhook local y última actividad
SET @table_exists = (SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
    AND table_name = 'wp_mpbm_devices');

SET @sql = IF(@table_exists > 0,
    'ALTER TABLE `wp_mpbm_devices`
     ADD COLUMN IF NOT EXISTS `local_ip` varchar(45) DEFAULT NULL,
     ADD COLUMN IF NOT EXISTS `local_port` int(5) DEFAULT NULL,
     ADD COLUMN IF NOT EXISTS `last_seen` datetime DEFAULT NULL,
     ADD INDEX IF NOT EXISTS `idx_last_seen` (`last_seen`)',
    'SELECT "Table wp_mpbm_devices does not exist, skipping columns"');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================
-- LIMPIEZA AUTOMÁTICA DE DATOS ANTIGUOS
-- ============================================
-- Los siguientes eventos programados se crean via PHP en el plugin
-- Aquí solo documentamos la estructura

-- Event: Limpiar changes_queue antiguos (>7 días)
-- Event: Limpiar product_changes antiguos (>30 días)
-- Event: Limpiar api_log antiguos (>90 días)

-- ============================================
-- VISTAS ÚTILES PARA DEBUGGING
-- ============================================

-- Vista: Cambios recientes (últimas 24 horas)
CREATE OR REPLACE VIEW `vw_mpbm_recent_changes` AS
SELECT
    c.id,
    c.change_type,
    c.entity_type,
    c.entity_id,
    c.created_at,
    COUNT(DISTINCT JSON_EXTRACT(c.device_notified, '$[*]')) as devices_notified
FROM `wp_mpbm_changes_queue` c
WHERE c.created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY c.id
ORDER BY c.created_at DESC;

-- Vista: Estadísticas de API (última hora)
CREATE OR REPLACE VIEW `vw_mpbm_api_stats_hourly` AS
SELECT
    endpoint,
    COUNT(*) as requests,
    AVG(duration_ms) as avg_duration_ms,
    MIN(duration_ms) as min_duration_ms,
    MAX(duration_ms) as max_duration_ms,
    SUM(CASE WHEN status_code >= 200 AND status_code < 300 THEN 1 ELSE 0 END) as success_count,
    SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) as error_count
FROM `wp_mpbm_api_log`
WHERE `timestamp` > DATE_SUB(NOW(), INTERVAL 1 HOUR)
GROUP BY endpoint
ORDER BY requests DESC;

-- Vista: Productos más actualizados (últimos 7 días)
CREATE OR REPLACE VIEW `vw_mpbm_top_updated_products` AS
SELECT
    pc.product_id,
    p.post_title as product_name,
    COUNT(*) as update_count,
    MAX(FROM_UNIXTIME(pc.change_timestamp)) as last_updated
FROM `wp_mpbm_product_changes` pc
LEFT JOIN `wp_posts` p ON pc.product_id = p.ID
WHERE FROM_UNIXTIME(pc.change_timestamp) > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY pc.product_id
ORDER BY update_count DESC
LIMIT 50;

-- ============================================
-- STORED PROCEDURES ÚTILES
-- ============================================

-- Procedure: Limpiar todos los cambios antiguos
DELIMITER $$

CREATE PROCEDURE IF NOT EXISTS `sp_mpbm_cleanup_old_data`(
    IN days_to_keep INT
)
BEGIN
    DECLARE deleted_changes INT;
    DECLARE deleted_product_changes INT;
    DECLARE deleted_logs INT;

    -- Limpiar changes_queue
    DELETE FROM `wp_mpbm_changes_queue`
    WHERE created_at < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
    SET deleted_changes = ROW_COUNT();

    -- Limpiar product_changes
    DELETE FROM `wp_mpbm_product_changes`
    WHERE FROM_UNIXTIME(change_timestamp) < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
    SET deleted_product_changes = ROW_COUNT();

    -- Limpiar api_log
    DELETE FROM `wp_mpbm_api_log`
    WHERE `timestamp` < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
    SET deleted_logs = ROW_COUNT();

    -- Retornar estadísticas
    SELECT
        deleted_changes as changes_queue_deleted,
        deleted_product_changes as product_changes_deleted,
        deleted_logs as api_logs_deleted,
        NOW() as cleanup_timestamp;
END$$

DELIMITER ;

-- Procedure: Obtener estadísticas del sistema
DELIMITER $$

CREATE PROCEDURE IF NOT EXISTS `sp_mpbm_get_system_stats`()
BEGIN
    SELECT
        'Changes Queue' as table_name,
        COUNT(*) as total_rows,
        COUNT(DISTINCT device_notified) as devices_tracking,
        MIN(created_at) as oldest_record,
        MAX(created_at) as newest_record
    FROM `wp_mpbm_changes_queue`

    UNION ALL

    SELECT
        'Product Changes' as table_name,
        COUNT(*) as total_rows,
        COUNT(DISTINCT product_id) as unique_products,
        FROM_UNIXTIME(MIN(change_timestamp)) as oldest_record,
        FROM_UNIXTIME(MAX(change_timestamp)) as newest_record
    FROM `wp_mpbm_product_changes`

    UNION ALL

    SELECT
        'API Log' as table_name,
        COUNT(*) as total_rows,
        COUNT(DISTINCT device_uuid) as active_devices,
        MIN(`timestamp`) as oldest_record,
        MAX(`timestamp`) as newest_record
    FROM `wp_mpbm_api_log`;
END$$

DELIMITER ;

-- ============================================
-- TRIGGERS PARA AUDITORÍA AUTOMÁTICA
-- ============================================

-- Trigger: Actualizar last_seen en devices cuando hay cambios
DELIMITER $$

CREATE TRIGGER IF NOT EXISTS `trg_mpbm_update_device_activity`
AFTER INSERT ON `wp_mpbm_changes_queue`
FOR EACH ROW
BEGIN
    IF NEW.device_notified IS NOT NULL THEN
        UPDATE `wp_mpbm_devices`
        SET last_seen = NOW()
        WHERE device_uuid IN (
            SELECT JSON_UNQUOTE(JSON_EXTRACT(NEW.device_notified, CONCAT('$[', idx, ']')))
            FROM (SELECT 0 as idx UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) as indices
            WHERE JSON_EXTRACT(NEW.device_notified, CONCAT('$[', idx, ']')) IS NOT NULL
        );
    END IF;
END$$

DELIMITER ;

-- ============================================
-- GRANTS Y PERMISOS (Opcional)
-- ============================================
-- Si tu hosting usa usuarios MySQL separados, asegúrate de dar permisos:
-- GRANT SELECT, INSERT, UPDATE, DELETE ON wp_mpbm_* TO 'tu_usuario'@'localhost';

-- ============================================
-- VERIFICACIÓN FINAL
-- ============================================
SELECT
    TABLE_NAME,
    TABLE_ROWS,
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS 'Size (MB)'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
AND TABLE_NAME LIKE 'wp_mpbm_%'
ORDER BY TABLE_NAME;

-- Mostrar índices creados
SELECT
    TABLE_NAME,
    INDEX_NAME,
    COLUMN_NAME,
    SEQ_IN_INDEX
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
AND TABLE_NAME LIKE 'wp_mpbm_%'
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;
