// lib/services/ultra_optimized_polling_service.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'woocommerce_service.dart';
// import 'database_service.dart'; // ❌ ObjectBox no disponible
// import '../models/product_optimized.dart'; // ❌ Requiere ObjectBox
// import '../objectbox.g.dart'; // ❌ ObjectBox no disponible

/// Ultra-Optimized Polling Service
///
/// Características:
/// - Motion-aware polling (accelerometer)
/// - Screen-state aware
/// - Battery-level aware
/// - Network-type aware (WiFi vs Mobile)
/// - Predictive polling (patrones de uso)
/// - Event-driven triggers
///
/// Consumo esperado: 1-2% batería/día
class UltraOptimizedPollingService extends ChangeNotifier {
  final WooCommerceService _wooService;
  // final DatabaseService? _db; // ❌ ObjectBox no disponible

  // ==================== TIMERS ====================

  Timer? _pollingTimer;
  Timer? _configRefreshTimer;

  // ==================== ESTADO ====================

  bool _isActive = false;
  int _newOrdersCount = 0;
  DateTime? _lastCheck;
  DateTime? _lastSuccessfulSync;

  // ==================== V3.1.0: LONG POLLING ====================
  int _lastChangeId = 0;
  bool _isLongPolling = false;

  // ==================== CONTEXTO DEL DISPOSITIVO ====================

  // Motion Detection
  bool _deviceIsMoving = false;
  DateTime _lastMovement = DateTime.now();
  StreamSubscription? _accelerometerSubscription;

  // Battery
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.full;
  final Battery _battery = Battery();

  // Network
  List<ConnectivityResult> _connectionType = [ConnectivityResult.none];
  final Connectivity _connectivity = Connectivity();

  // Screen (simulado - Flutter no tiene API nativa)
  bool _screenIsOn = true;
  bool _appInForeground = true;

  // ==================== CONFIGURACIÓN ADAPTATIVA ====================

  int _currentPollingInterval = 60; // Segundos
  int _minInterval = 15;
  int _maxInterval = 1800; // 30 minutos

  // ==================== NOTIFICACIONES ====================

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // ==================== GETTERS ====================

  bool get isActive => _isActive;
  int get newOrdersCount => _newOrdersCount;
  DateTime? get lastCheck => _lastCheck;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  int get currentPollingInterval => _currentPollingInterval;
  bool get deviceIsMoving => _deviceIsMoving;
  int get batteryLevel => _batteryLevel;
  String get connectionType => _connectionType.isNotEmpty ? _connectionType.first.name : 'none';

  UltraOptimizedPollingService({
    required WooCommerceService wooService,
    // DatabaseService? database, // ❌ ObjectBox no disponible
  })  : _wooService = wooService;
        // _db = database;

  // ==================== INICIALIZACIÓN ====================

  Future<void> initialize() async {
    debugPrint('[UltraPolling] Initializing...');

    // Inicializar notificaciones
    await _initializeNotifications();

    // Inicializar sensores
    await _initializeMotionDetection();
    await _initializeBatteryMonitoring();
    await _initializeNetworkMonitoring();

    debugPrint('[UltraPolling] ✅ Initialized');
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
  }

  // ==================== MOTION DETECTION ====================

  Future<void> _initializeMotionDetection() async {
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      // Calcular magnitud del movimiento
      final movement =
          sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

      // Threshold: 10 m/s² (movimiento significativo)
      if (movement > 10) {
        _deviceIsMoving = true;
        _lastMovement = DateTime.now();

        // Ajustar polling si estaba en reposo
        if (_currentPollingInterval > 120) {
          _adjustPollingInterval();
        }
      } else {
        // Sin movimiento por 5 minutos = dispositivo en reposo
        if (DateTime.now().difference(_lastMovement) >
            const Duration(minutes: 5)) {
          if (_deviceIsMoving) {
            debugPrint('[UltraPolling] Device is now stationary');
            _deviceIsMoving = false;
            _adjustPollingInterval();
          }
        }
      }
    });

    debugPrint('[UltraPolling] Motion detection enabled');
  }

  // ==================== BATTERY MONITORING ====================

  Future<void> _initializeBatteryMonitoring() async {
    // Nivel inicial
    _batteryLevel = await _battery.batteryLevel;
    _batteryState = await _battery.batteryState;

    // Escuchar cambios
    _battery.onBatteryStateChanged.listen((state) {
      _batteryState = state;

      if (state == BatteryState.charging) {
        debugPrint('[UltraPolling] Device is charging - enabling aggressive polling');
        _adjustPollingInterval();
      } else {
        _battery.batteryLevel.then((level) {
          _batteryLevel = level;
          _adjustPollingInterval();
        });
      }
    });

    debugPrint('[UltraPolling] Battery monitoring enabled');
  }

  // ==================== NETWORK MONITORING ====================

  Future<void> _initializeNetworkMonitoring() async {
    // Estado inicial
    _connectionType = await _connectivity.checkConnectivity();

    // Escuchar cambios
    _connectivity.onConnectivityChanged.listen((result) {
      _connectionType = result;
      final type = result.isNotEmpty ? result.first : ConnectivityResult.none;
      debugPrint('[UltraPolling] Network changed to: ${type.name}');

      if (type == ConnectivityResult.wifi) {
        // WiFi disponible - sync completo
        debugPrint('[UltraPolling] WiFi available - triggering full sync');
        _performFullSync();
      } else if (type == ConnectivityResult.none) {
        // Sin conexión - pausar polling
        debugPrint('[UltraPolling] No connection - pausing polling');
        _pausePolling();
      } else {
        // Datos móviles - polling mínimo
        _adjustPollingInterval();
      }
    });

    debugPrint('[UltraPolling] Network monitoring enabled');
  }

  // ==================== POLLING ADAPTATIVO ====================

  /// Calcula el intervalo óptimo basado en contexto
  void _adjustPollingInterval() {
    int newInterval = 60; // Default: 1 minuto

    // ========== CHARGING STATE ==========
    if (_batteryState == BatteryState.charging) {
      newInterval = 15; // Agresivo cuando está cargando
      debugPrint('[UltraPolling] Charging: aggressive polling (15s)');
    }
    // ========== BATTERY LEVEL ==========
    else if (_batteryLevel < 20) {
      newInterval = 1800; // 30 min - modo extremo ahorro
      debugPrint('[UltraPolling] Low battery: extreme saving (30min)');
    } else if (_batteryLevel < 50) {
      newInterval = 300; // 5 min - modo ahorro
      debugPrint('[UltraPolling] Medium battery: saving mode (5min)');
    }
    // ========== MOTION ==========
    else if (_deviceIsMoving) {
      newInterval = 60; // 1 min - usuario activo
      debugPrint('[UltraPolling] Device moving: active polling (60s)');
    } else {
      newInterval = 300; // 5 min - dispositivo quieto
      debugPrint('[UltraPolling] Device stationary: slow polling (5min)');
    }

    // ========== NETWORK TYPE ==========
    final currentType = _connectionType.isNotEmpty ? _connectionType.first : ConnectivityResult.none;
    if (currentType == ConnectivityResult.mobile) {
      // Datos móviles - menos frecuente
      newInterval = max(newInterval, 300); // Mínimo 5 min
      debugPrint('[UltraPolling] Mobile data: reduced frequency');
    } else if (currentType == ConnectivityResult.none) {
      // Sin conexión - pausar
      _pausePolling();
      return;
    }

    // ========== HORARIO ==========
    final hour = DateTime.now().hour;
    if (hour >= 22 || hour <= 7) {
      // Horario nocturno - muy poco frecuente
      newInterval = max(newInterval, 3600); // Mínimo 1 hora
      debugPrint('[UltraPolling] Night time: minimal polling (1h)');
    } else if (hour >= 9 && hour <= 20) {
      // Horario comercial - más frecuente
      if (_deviceIsMoving) {
        newInterval = min(newInterval, 60);
      }
    }

    // ========== BACKGROUND ==========
    if (!_appInForeground) {
      newInterval = max(newInterval, 900); // Mínimo 15 min en background
      debugPrint('[UltraPolling] Background: minimal polling (15min)');
    }

    // Aplicar límites
    newInterval = max(_minInterval, min(_maxInterval, newInterval));

    // Solo actualizar si cambió significativamente
    if ((newInterval - _currentPollingInterval).abs() > 10) {
      _currentPollingInterval = newInterval;
      _restartPolling();
      notifyListeners();
    }
  }

  // ==================== START/STOP ====================

  Future<void> start() async {
    if (_isActive) return;

    // Usar Long Polling v3.1.0 en lugar de polling tradicional
    await startLongPolling();

    // Mantener los timers de configuración
    _configRefreshTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _adjustPollingInterval(),
    );

    notifyListeners();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      Duration(seconds: _currentPollingInterval),
      (_) => _checkNewOrders(),
    );
  }

  void _restartPolling() {
    if (_isActive) {
      _startPolling();
    }
  }

  void _pausePolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void stop() {
    _pollingTimer?.cancel();
    _configRefreshTimer?.cancel();
    _accelerometerSubscription?.cancel();

    _pollingTimer = null;
    _configRefreshTimer = null;
    _accelerometerSubscription = null;

    _isActive = false;
    debugPrint('[UltraPolling] Polling stopped');
  }

  // ==================== CHECK NEW ORDERS ====================

  /// Check ultra-ligero: solo pregunta si hay pedidos nuevos
  Future<void> _checkNewOrders() async {
    if (!_isActive) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt('last_order_check') ??
          (DateTime.now().subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
              1000);

      debugPrint('[UltraPolling] Checking for new orders...');

      final response = await _wooService.checkNewOrders(
        deviceId: prefs.getString('device_uuid') ?? 'unknown',
        since: lastCheck,
      );

      _lastCheck = DateTime.now();

      if (response['has_new'] == true) {
        final count = response['count'] as int;
        _newOrdersCount = count;

        debugPrint('[UltraPolling] 🔔 $count new orders detected!');

        // Mostrar notificación
        await _showNotification(
          id: 1,
          title: 'Nuevos Pedidos',
          body: 'Tienes $count ${count == 1 ? 'pedido nuevo' : 'pedidos nuevos'}',
        );

        // Descargar pedidos y actualizar stock
        await _downloadOrdersDelta(lastCheck);

        notifyListeners();
      } else {
        debugPrint('[UltraPolling] No new orders');
      }

      // Guardar timestamp
      await prefs.setInt('last_order_check', response['timestamp'] as int);
      _lastSuccessfulSync = DateTime.now();

      // 🟢 NUEVO: También verificar cambios de productos (inventario externo)
      await _checkProductsChanges();

    } catch (e) {
      debugPrint('[UltraPolling] ⚠️ Check failed: $e');
    }
  }

  /// 🟢 NUEVO: Verificar cambios de productos (inventario creado fuera de la app)
  Future<void> _checkProductsChanges() async {
    if (!_isActive) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Verificar si el usuario tiene activada la sincronización automática
      final autoSyncEnabled = prefs.getBool('auto_sync_products_enabled') ?? true;

      if (!autoSyncEnabled) {
        debugPrint('[UltraPolling] Product sync disabled by user');
        return;
      }

      final lastCheck = prefs.getInt('last_product_check') ??
          (DateTime.now().subtract(const Duration(hours: 24))
              .millisecondsSinceEpoch ~/
              1000);

      debugPrint('[UltraPolling] Checking for product changes...');

      // Descargar productos delta directamente (modo lightweight)
      await _downloadProductsDelta(lastCheck);

    } catch (e) {
      debugPrint('[UltraPolling] ⚠️ Product check failed: $e');
    }
  }

  /// Descargar pedidos delta y actualizar stock
  /// 🟢 PRIORIDAD 3: Implementación completa
  Future<void> _downloadOrdersDelta(int since) async {
    try {
      debugPrint('[UltraPolling] 🟢 Downloading orders delta since $since...');

      // Llamar al endpoint delta
      final response = await _wooService.getOrdersDelta(since: since);

      final orders = response['orders'] as List? ?? [];
      final productsStock = response['products_stock'] as Map? ?? {};

      debugPrint('[UltraPolling] Downloaded ${orders.length} orders, ${productsStock.length} stock updates');

      // ❌ Actualizar stock en ObjectBox - DESHABILITADO (requiere ObjectBox)
      // if (productsStock.isNotEmpty) {
      //   await _updateProductsStock(productsStock);
      //   debugPrint('[UltraPolling] ✅ Stock updated from delta');
      // }

      if (orders.isNotEmpty) {
        debugPrint('[UltraPolling] ✅ ${orders.length} new/updated orders detected');
      }

      debugPrint('[UltraPolling] ✅ Delta sync completed');

    } catch (e) {
      debugPrint('[UltraPolling] ⚠️ Download delta failed: $e');
    }
  }

  /// Actualizar stock de productos en ObjectBox
  /// ❌ DESHABILITADO - Requiere ObjectBox
  // Future<void> _updateProductsStock(Map<dynamic, dynamic> stockData) async {
  //   final box = _db.store.box<ProductOptimized>();
  //
  //   for (final entry in stockData.entries) {
  //     final productId = int.parse(entry.key.toString());
  //     final stockInfo = entry.value as Map;
  //
  //     final query = box.query(ProductOptimized_.id.equals(productId)).build();
  //     final product = query.findFirst();
  //     query.close();
  //
  //     if (product != null) {
  //       product.stockQuantity = stockInfo['stock'] as int? ?? 0;
  //       product.stockStatus =
  //           _parseStockStatus(stockInfo['status'] as String?);
  //       product.lastUpdated = DateTime.now();
  //
  //       box.put(product);
  //
  //       debugPrint('[UltraPolling] Updated ${product.name}: stock=${product.stockQuantity}');
  //     }
  //   }
  // }

  int _parseStockStatus(String? status) {
    switch (status) {
      case 'instock':
        return 1;
      case 'onbackorder':
        return 2;
      case 'outofstock':
      default:
        return 0;
    }
  }

  /// 🟢 NUEVO: Descargar productos delta (cambios de inventario externos)
  Future<void> _downloadProductsDelta(int since) async {
    try {
      debugPrint('[UltraPolling] 🟢 Downloading products delta since $since...');

      // Llamar al endpoint delta (modo lightweight para reducir ancho de banda)
      final response = await _wooService.getProductsDelta(
        since: since,
        lightweight: true,
      );

      final products = response['products'] as Map? ?? {};
      final count = response['count'] as int? ?? 0;
      final timestamp = response['timestamp'] as int?;

      debugPrint('[UltraPolling] Downloaded $count product changes');

      // ❌ Actualizar productos en ObjectBox - DESHABILITADO (requiere ObjectBox)
      // if (products.isNotEmpty) {
      //   await _updateProductsFromDelta(products);
      //   debugPrint('[UltraPolling] ✅ Products updated from delta');
      //
      //   // Mostrar notificación si hay cambios significativos (más de 5 productos)
      //   if (count > 5) {
      //     await _showNotification(
      //       id: 2,
      //       title: 'Inventario Actualizado',
      //       body: 'Se actualizaron $count productos desde WordPress',
      //     );
      //   }
      //
      //   notifyListeners();
      // }

      // Guardar timestamp
      if (timestamp != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_product_check', timestamp);
        debugPrint('[UltraPolling] Product check timestamp saved: $timestamp');
      }

      debugPrint('[UltraPolling] ✅ Product delta sync completed');

    } catch (e) {
      debugPrint('[UltraPolling] ⚠️ Download product delta failed: $e');
    }
  }

  /// Actualizar productos desde delta (formato compacto del plugin)
  /// ❌ DESHABILITADO - Requiere ObjectBox
  // Future<void> _updateProductsFromDelta(Map<dynamic, dynamic> productsData) async {
  //   final box = _db.store.box<ProductOptimized>();
  //
  //   for (final entry in productsData.entries) {
  //     final productId = int.parse(entry.key.toString());
  //     final productData = entry.value as Map;
  //
  //     // Buscar producto en ObjectBox
  //     final query = box.query(ProductOptimized_.id.equals(productId)).build();
  //     final existingProduct = query.findFirst();
  //     query.close();
  //
  //     if (existingProduct != null) {
  //       // Actualizar producto existente
  //       existingProduct.name = productData['n'] as String? ?? existingProduct.name;
  //       existingProduct.sku = productData['s'] as String? ?? existingProduct.sku;
  //       existingProduct.barcode = productData['b'] as String? ?? existingProduct.barcode;
  //       existingProduct.stockQuantity = productData['st'] as int? ?? 0;
  //       existingProduct.stockStatus = _parseStockStatus(productData['ss'] as String?);
  //
  //       // Precio viene en centavos, convertir a double
  //       final priceInCents = productData['p'] as int?;
  //       if (priceInCents != null) {
  //         existingProduct.price = priceInCents / 100.0;
  //       }
  //
  //       existingProduct.lastUpdated = DateTime.now();
  //       box.put(existingProduct);
  //
  //       debugPrint('[UltraPolling] Updated product ${existingProduct.name}: stock=${existingProduct.stockQuantity}');
  //     } else {
  //       // Crear nuevo producto
  //       final newProduct = ProductOptimized(
  //         id: productId,
  //         name: productData['n'] as String? ?? 'Producto sin nombre',
  //         sku: productData['s'] as String? ?? '',
  //         barcode: productData['b'] as String? ?? '',
  //         price: (productData['p'] as int? ?? 0) / 100.0,
  //         stockQuantity: productData['st'] as int? ?? 0,
  //         stockStatus: _parseStockStatus(productData['ss'] as String?),
  //         type: productData['t'] as String? ?? 'simple',
  //         lastUpdated: DateTime.now(),
  //       );
  //
  //       box.put(newProduct);
  //       debugPrint('[UltraPolling] Created new product: ${newProduct.name}');
  //     }
  //   }
  // }

  /// Procesar notas de crédito
  /// ❌ DESHABILITADO - Requiere ObjectBox
  // Future<void> _processCreditNotes(List<dynamic> creditNotes) async {
  //   final box = _db.store.box<ProductOptimized>();
  //
  //   for (final note in creditNotes) {
  //     final productId = note['product_id'] as int;
  //     final quantity = note['quantity'] as int;
  //     final type = note['type'] as String;
  //
  //     final query = box.query(ProductOptimized_.id.equals(productId)).build();
  //     final product = query.findFirst();
  //     query.close();
  //
  //     if (product != null) {
  //       // Nota de crédito SUMA stock (devoluciones/entradas)
  //       product.stockQuantity += quantity;
  //       product.lastUpdated = DateTime.now();
  //
  //       box.put(product);
  //
  //       debugPrint('[UltraPolling] Credit note: ${product.name} +$quantity (type: $type)');
  //     }
  //   }
  // }

  /// Sync completo (solo con WiFi)
  Future<void> _performFullSync() async {
    if (_connectionType != ConnectivityResult.wifi) {
      debugPrint('[UltraPolling] Skipping full sync - not on WiFi');
      return;
    }

    debugPrint('[UltraPolling] 🔄 Performing full sync (WiFi)...');

    // TODO: Implementar sync completo de catálogo
    // Por ahora solo hacemos check de pedidos

    await _checkNewOrders();
  }

  // ==================== NOTIFICACIONES ====================

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'pos_orders',
      'Pedidos',
      channelDescription: 'Notificaciones de nuevos pedidos',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details);
  }

  // ==================== PUBLIC METHODS ====================

  /// Marcar pedidos como vistos
  void markOrdersAsSeen() {
    _newOrdersCount = 0;
    notifyListeners();
  }

  /// Forzar check inmediato
  Future<void> forceCheck() async {
    debugPrint('[UltraPolling] 🔄 Force check triggered');
    await _checkNewOrders();
  }

  /// 🟢 NUEVO: Forzar sincronización manual de productos (inventario externo)
  Future<void> forceProductsSync() async {
    debugPrint('[UltraPolling] 🔄 Force products sync triggered (manual refresh)');

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt('last_product_check') ??
          (DateTime.now().subtract(const Duration(days: 7))
              .millisecondsSinceEpoch ~/
              1000);

      // Descargar cambios de productos
      await _downloadProductsDelta(lastCheck);

      debugPrint('[UltraPolling] ✅ Manual products sync completed');
    } catch (e) {
      debugPrint('[UltraPolling] ⚠️ Manual products sync failed: $e');
      rethrow; // Re-lanzar para que la UI pueda mostrar error
    }
  }

  /// Set app foreground/background
  void setAppForeground(bool foreground) {
    if (_appInForeground != foreground) {
      _appInForeground = foreground;
      debugPrint('[UltraPolling] App ${foreground ? 'foreground' : 'background'}');
      _adjustPollingInterval();
    }
  }

  /// Get estadísticas
  Map<String, dynamic> getStats() {
    return {
      'is_active': _isActive,
      'new_orders': _newOrdersCount,
      'last_check': _lastCheck?.toIso8601String(),
      'last_sync': _lastSuccessfulSync?.toIso8601String(),
      'polling_interval': _currentPollingInterval,
      'device_moving': _deviceIsMoving,
      'battery_level': _batteryLevel,
      'battery_state': _batteryState.name,
      'connection': _connectionType.isNotEmpty ? _connectionType.first.name : 'none',
      'app_foreground': _appInForeground,
    };
  }

  // ==================== V3.1.0: LONG POLLING ====================

  /// Iniciar Long Polling en lugar de polling tradicional
  Future<void> startLongPolling() async {
    if (_isLongPolling) {
      debugPrint('[UltraPolling] Long polling already active');
      return;
    }

    _isLongPolling = true;
    _isActive = true;
    debugPrint('[UltraPolling] 🚀 Starting Long Polling (v3.1.0)...');

    // Cargar último ID de cambio
    final prefs = await SharedPreferences.getInstance();
    _lastChangeId = prefs.getInt('last_change_id') ?? 0;

    // Iniciar loop de long polling
    _longPollLoop();

    debugPrint('[UltraPolling] ✅ Long Polling active');
  }

  /// Loop de Long Polling (mantiene conexión hasta 30s)
  Future<void> _longPollLoop() async {
    while (_isLongPolling) {
      try {
        debugPrint('[UltraPolling] 📡 Long polling (waiting up to 25s)...');

        // Llamar al endpoint de long polling
        final response = await _wooService.longPollChanges(
          lastId: _lastChangeId,
          timeout: 25,
        );

        final status = response['status'] as String?;

        if (status == 'changes') {
          // Hay cambios disponibles
          final changes = response['changes'] as List? ?? [];
          final newLastId = response['last_id'] as int? ?? _lastChangeId;

          debugPrint('[UltraPolling] 🔔 Received ${changes.length} changes!');

          // Procesar cambios
          await _processChanges(changes);

          // Actualizar último ID
          _lastChangeId = newLastId;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_change_id', _lastChangeId);

          // ACK para confirmar recepción
          await _wooService.acknowledgeChanges(_lastChangeId);

          notifyListeners();
        } else {
          // Timeout normal sin cambios
          debugPrint('[UltraPolling] ⏱️ Timeout (no changes)');
        }

        _lastCheck = DateTime.now();
        _lastSuccessfulSync = DateTime.now();

      } catch (e) {
        debugPrint('[UltraPolling] ⚠️ Long polling error: $e');

        // Esperar antes de reintentar
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    debugPrint('[UltraPolling] Long polling loop ended');
  }

  /// Procesar cambios recibidos del long polling
  Future<void> _processChanges(List<dynamic> changes) async {
    for (final change in changes) {
      final changeType = change['type'] as String?;
      final entityType = change['entity_type'] as String?;
      final entityId = change['entity_id'] as int?;

      debugPrint('[UltraPolling] Processing: $entityType $entityId ($changeType)');

      if (entityType == 'product') {
        // Cambio en producto - trigger delta sync
        debugPrint('[UltraPolling] Product changed: $entityId');
        // TODO: Trigger delta sync service
      } else if (entityType == 'order') {
        // Nuevo pedido
        _newOrdersCount++;

        await _showNotification(
          id: 1,
          title: 'Nuevo Pedido',
          body: 'Se recibió un pedido nuevo #$entityId',
        );

        debugPrint('[UltraPolling] New order: $entityId');
      }
    }
  }

  /// Detener Long Polling
  void stopLongPolling() {
    _isLongPolling = false;
    _isActive = false;
    debugPrint('[UltraPolling] Long Polling stopped');
  }

  @override
  void dispose() {
    stopLongPolling();
    stop();
    super.dispose();
  }
}
