// lib/services/order_notification_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'woocommerce_service.dart';
import 'connectivity_service.dart';

/// Servicio para gestionar notificaciones de pedidos desde WooCommerce
/// Consulta periódicamente nuevos pedidos creados en WooCommerce (no desde la app)
class OrderNotificationService {
  final WooCommerceService _wooCommerceService;
  final ConnectivityService _connectivityService;

  Timer? _pollingTimer;
  bool _isPolling = false;

  // Stream para notificar nuevos pedidos
  final StreamController<Map<String, dynamic>> _newOrderController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewOrder => _newOrderController.stream;

  // Configuración de polling
  static const Duration _pollingInterval = Duration(minutes: 2);
  static const int _notificationsLimit = 10;

  OrderNotificationService({
    required WooCommerceService wooCommerceService,
    required ConnectivityService connectivityService,
  })  : _wooCommerceService = wooCommerceService,
        _connectivityService = connectivityService {
    debugPrint("[OrderNotificationService] Inicializado");
  }

  /// Iniciar polling de notificaciones
  void startPolling() {
    if (_isPolling) {
      debugPrint("[OrderNotificationService] Ya está en polling, skip");
      return;
    }

    debugPrint("[OrderNotificationService] 🔄 Iniciando polling de notificaciones (cada ${_pollingInterval.inMinutes} min)");
    _isPolling = true;

    // Primera consulta inmediata
    _checkForNewOrders();

    // Consultas periódicas
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (_isPolling) {
        _checkForNewOrders();
      }
    });
  }

  /// Detener polling
  void stopPolling() {
    if (!_isPolling) return;

    debugPrint("[OrderNotificationService] ⏸️ Deteniendo polling de notificaciones");
    _isPolling = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Consultar nuevos pedidos
  Future<void> _checkForNewOrders() async {
    if (!await _connectivityService.checkConnectivity()) {
      debugPrint("[OrderNotificationService] Sin conexión, skip polling");
      return;
    }

    try {
      debugPrint("[OrderNotificationService] 📡 Consultando nuevos pedidos...");

      final response = await _wooCommerceService.getOrderNotifications(
        limit: _notificationsLimit,
        markAsRead: true, // Marcar como leídas automáticamente
      );

      final int count = response['count'] ?? 0;
      final List notifications = response['notifications'] ?? [];

      if (count > 0) {
        debugPrint("[OrderNotificationService] 🔔 ¡${count} nuevos pedidos desde WooCommerce!");

        // Notificar cada pedido
        for (final notification in notifications) {
          if (notification is Map<String, dynamic>) {
            _newOrderController.add(notification);
          }
        }
      } else {
        debugPrint("[OrderNotificationService] ✅ No hay nuevos pedidos");
      }
    } catch (e) {
      debugPrint("[OrderNotificationService] ❌ Error consultando notificaciones: $e");
    }
  }

  /// Consultar manualmente (bajo demanda)
  Future<List<Map<String, dynamic>>> checkNowAndGetNotifications() async {
    if (!await _connectivityService.checkConnectivity()) {
      debugPrint("[OrderNotificationService] Sin conexión");
      return [];
    }

    try {
      final response = await _wooCommerceService.getOrderNotifications(
        limit: _notificationsLimit,
        markAsRead: false, // No marcar como leídas aún
      );

      final List notifications = response['notifications'] ?? [];
      return notifications.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("[OrderNotificationService] Error: $e");
      return [];
    }
  }

  /// Marcar notificaciones como leídas
  Future<void> markAsRead(List<int> notificationIds) async {
    try {
      await _wooCommerceService.markNotificationsAsRead(notificationIds);
      debugPrint("[OrderNotificationService] ✅ Marcadas ${notificationIds.length} notificaciones como leídas");
    } catch (e) {
      debugPrint("[OrderNotificationService] Error marcando como leídas: $e");
    }
  }

  /// Liberar recursos
  void dispose() {
    stopPolling();
    _newOrderController.close();
    debugPrint("[OrderNotificationService] Disposed");
  }
}
