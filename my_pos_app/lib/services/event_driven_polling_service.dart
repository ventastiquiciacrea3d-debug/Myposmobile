// lib/services/event_driven_polling_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'ultra_optimized_polling_service.dart';

/// Servicio de Polling Disparado por Eventos
///
/// Hace polling INMEDIATO cuando ocurren eventos específicos:
/// - App regresa a primer plano
/// - Usuario completa una venta
/// - Escaneo de producto sin stock
/// - Navegación a pantalla de pedidos/inventario
///
/// Reduce latencia percibida de 5 min a 5-10 segundos
class EventDrivenPollingService with WidgetsBindingObserver {
  final UltraOptimizedPollingService _pollingService;

  DateTime _lastImmediatePoll = DateTime.now();
  StreamSubscription? _saleCompletedSubscription;
  StreamSubscription? _outOfStockSubscription;
  StreamSubscription? _navigationSubscription;

  // Streams de eventos (deben ser inyectados desde fuera)
  Stream<void>? onSaleCompleted;
  Stream<String>? onOutOfStockScanned;
  Stream<String>? onNavigationChanged;

  EventDrivenPollingService({
    required UltraOptimizedPollingService pollingService,
  }) : _pollingService = pollingService;

  /// Inicializar servicio de eventos
  Future<void> initialize({
    Stream<void>? saleCompletedStream,
    Stream<String>? outOfStockStream,
    Stream<String>? navigationStream,
  }) async {
    debugPrint('[EventDrivenPolling] Initializing...');

    // Guardar referencias a streams
    onSaleCompleted = saleCompletedStream;
    onOutOfStockScanned = outOfStockStream;
    onNavigationChanged = navigationStream;

    // Registrar listener de ciclo de vida de la app
    WidgetsBinding.instance.addObserver(this);

    // Configurar listeners de eventos
    _setupEventTriggers();

    debugPrint('[EventDrivenPolling] ✅ Initialized');
  }

  /// Configurar triggers de eventos
  void _setupEventTriggers() {
    // Evento 1: Venta completada
    if (onSaleCompleted != null) {
      _saleCompletedSubscription = onSaleCompleted!.listen((_) {
        debugPrint('[EventDrivenPolling] 🛒 Sale completed - triggering immediate check');
        // Esperar 5 segundos para que el servidor procese
        Future.delayed(const Duration(seconds: 5), _performImmediateCheck);
      });
    }

    // Evento 2: Producto sin stock escaneado
    if (onOutOfStockScanned != null) {
      _outOfStockSubscription = onOutOfStockScanned!.listen((productId) {
        debugPrint('[EventDrivenPolling] ⚠️ Out-of-stock product scanned - checking stock updates');
        _checkStockUpdates();
      });
    }

    // Evento 3: Navegación a pantallas críticas
    if (onNavigationChanged != null) {
      _navigationSubscription = onNavigationChanged!.listen((route) {
        if (route == '/orders' || route == '/order-screen') {
          debugPrint('[EventDrivenPolling] 📦 Navigated to orders - triggering check');
          _performImmediateCheck();
        } else if (route == '/inventory' || route == '/inventory-screen') {
          debugPrint('[EventDrivenPolling] 📊 Navigated to inventory - checking inventory updates');
          _checkInventoryUpdates();
        }
      });
    }
  }

  /// Observer de ciclo de vida de la app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App regresó a primer plano
        final timeSinceLastPoll = DateTime.now().difference(_lastImmediatePoll);

        if (timeSinceLastPoll > const Duration(minutes: 5)) {
          debugPrint('[EventDrivenPolling] 📱 App resumed after ${timeSinceLastPoll.inMinutes} min - triggering check');
          _performImmediateCheck();
        } else {
          debugPrint('[EventDrivenPolling] App resumed but polled recently (${timeSinceLastPoll.inSeconds}s ago)');
        }

        // Notificar al polling service que la app está en foreground
        _pollingService.setAppForeground(true);
        break;

      case AppLifecycleState.paused:
        debugPrint('[EventDrivenPolling] App paused - reducing polling frequency');
        _pollingService.setAppForeground(false);
        break;

      case AppLifecycleState.inactive:
        // App en transición (ej: selector de apps)
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App siendo destruida o oculta
        break;
    }
  }

  /// Realizar check inmediato
  Future<void> _performImmediateCheck() async {
    _lastImmediatePoll = DateTime.now();
    await _pollingService.forceCheck();
  }

  /// Verificar actualizaciones de stock específicas
  Future<void> _checkStockUpdates() async {
    // Forzar check inmediato
    await _pollingService.forceCheck();
  }

  /// Verificar actualizaciones de inventario
  Future<void> _checkInventoryUpdates() async {
    // Forzar check inmediato
    await _pollingService.forceCheck();
  }

  /// Trigger manual para testing
  Future<void> triggerImmediateCheck() async {
    debugPrint('[EventDrivenPolling] 🔄 Manual trigger');
    await _performImmediateCheck();
  }

  /// Obtener estadísticas
  Map<String, dynamic> getStats() {
    return {
      'last_immediate_poll': _lastImmediatePoll.toIso8601String(),
      'time_since_last_poll': DateTime.now().difference(_lastImmediatePoll).inSeconds,
      'sale_listener_active': _saleCompletedSubscription != null,
      'stock_listener_active': _outOfStockSubscription != null,
      'navigation_listener_active': _navigationSubscription != null,
    };
  }

  /// Limpiar recursos
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saleCompletedSubscription?.cancel();
    _outOfStockSubscription?.cancel();
    _navigationSubscription?.cancel();

    debugPrint('[EventDrivenPolling] Disposed');
  }
}
