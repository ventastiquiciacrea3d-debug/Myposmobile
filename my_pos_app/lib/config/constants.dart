// lib/config/constants.dart

// --- SharedPreferences Keys ---
const String connectionModePrefKey = 'connection_mode';
const String manualScanModePrefKey = 'manual_scan_mode_enabled';
const String rapidScanModePrefKey = 'rapid_scan_mode_enabled';
const String searchOnlyAvailablePrefKey = 'search_only_available';
const String hideSearchImagePrefKey = 'hide_search_images';
const String offlineModeEnabledPrefKey = 'offline_mode_enabled';
const String offlineSyncFrequencyPrefKey = 'offline_sync_frequency';
const String defaultTaxRatePrefKey = 'default_tax_rate';
const String individualDiscountsEnabledPrefKey = 'allow_individual_discounts';
const String firstRunPrefKey = 'first_run';
const String useBiometricsPrefKey = 'use_biometrics';
const String autosyncPrefKey = 'autosync';
const String notifyLowStockPrefKey = 'notify_low_stock';
const String syncIntervalPrefKey = 'sync_interval';
const String scannerVibrationPrefKey = 'scanner_vibration';
const String scannerSoundPrefKey = 'scanner_sound';
const String labelSettingsPrefKey = 'label_settings';
const String lastConnectedPrinterPrefKey = 'last_connected_printer';

// --- Secure Storage Keys ---
const String secureApiUrlKey = 'api_url';
const String secureMyPosApiKey = 'mypos_api_key';
const String secureDeviceUuidKey = 'device_uuid';
const String secureAccessTokenKey = 'jwt_access_token'; // <-- MODIFICADO
const String secureRefreshTokenKey = 'jwt_refresh_token'; // <-- AÑADIDO

// Claves deprecadas pero mantenidas por si acaso
const String secureConsumerKeyKey = 'consumer_key';
const String secureConsumerSecretKey = 'consumer_secret';
const String secureJwtTokenKey = 'jwt_token'; // Clave antigua, se puede migrar

// --- Hive Keys & Box Names ---
const String hiveSettingsBoxName = 'settings';
const String hiveLastSyncKey = 'last_sync';
const String hiveProductsBoxName = 'products';
const String hiveBarcodeIndexBoxName = 'barcode_index';
const String hiveOrdersBoxName = 'orders';
const String hivePendingOrdersBoxName = 'pendingOrders';
const String hiveInventoryMovementsBoxName = 'inventoryMovements';
const String hiveLabelQueueBoxName = 'labelQueue';
const String hiveCurrentOrderPendingKey = '__current_order_pending__';
const String hiveInventoryAdjustmentCacheBoxName = 'inventoryAdjustmentCache';
const String hiveSyncQueueBoxName = 'syncQueue';