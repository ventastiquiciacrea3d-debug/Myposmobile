-- MY POS BARCODE MOBIL - Delta Sync Tables
-- Crear tabla de tracking de cambios de productos
-- Version: 3.1.0

CREATE TABLE IF NOT EXISTS wp_mpbm_product_changes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  product_id BIGINT UNSIGNED NOT NULL,
  change_type VARCHAR(50) NOT NULL COMMENT 'stock_change, price_change, update, delete, new_product',
  priority TINYINT NOT NULL DEFAULT 2 COMMENT '0=critical, 1=high, 2=normal, 3=low',
  old_stock INT DEFAULT NULL,
  new_stock INT DEFAULT NULL,
  old_price DECIMAL(10,2) DEFAULT NULL,
  new_price DECIMAL(10,2) DEFAULT NULL,
  changed_at DATETIME NOT NULL,
  synced_at DATETIME DEFAULT NULL,

  INDEX idx_changed_at (changed_at),
  INDEX idx_product_id (product_id),
  INDEX idx_synced (synced_at),
  INDEX idx_priority_changed (priority, changed_at),
  INDEX idx_not_synced (synced_at, changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
