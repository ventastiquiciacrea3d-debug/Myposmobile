// lib/providers/order_notification_notifier.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/order_notification_service.dart';
import 'shared_providers.dart';

part 'order_notification_notifier.g.dart';

/// Estado de las notificaciones de pedidos
class OrderNotificationState {
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;
  final bool isPolling;
  final DateTime? lastChecked;

  const OrderNotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.isPolling = false,
    this.lastChecked,
  });

  OrderNotificationState copyWith({
    List<Map<String, dynamic>>? notifications,
    int? unreadCount,
    bool? isPolling,
    DateTime? lastChecked,
  }) {
    return OrderNotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isPolling: isPolling ?? this.isPolling,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

/// Notifier para gestionar las notificaciones de pedidos
@riverpod
class OrderNotificationNotifier extends _$OrderNotificationNotifier {
  OrderNotificationService? _service;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  @override
  OrderNotificationState build() {
    // Inicializar el servicio
    _initializeService();

    // Cleanup cuando se dispose
    ref.onDispose(() {
      _cleanup();
    });

    return const OrderNotificationState();
  }

  void _initializeService() async {
    try {
      _service = ref.read(orderNotificationServiceProvider);

      // Escuchar nuevos pedidos
      _subscription = _service!.onNewOrder.listen((notification) {
        _handleNewOrderNotification(notification);
      });

      // Iniciar polling
      _service!.startPolling();

      state = state.copyWith(isPolling: true);

      debugPrint("[OrderNotificationNotifier] Servicio inicializado y polling iniciado");
    } catch (e) {
      debugPrint("[OrderNotificationNotifier] Error inicializando servicio: $e");
    }
  }

  void _handleNewOrderNotification(Map<String, dynamic> notification) {
    debugPrint("[OrderNotificationNotifier] 🔔 Nueva notificación recibida: Pedido #${notification['order_number']}");

    // Agregar a la lista de notificaciones
    final updatedNotifications = [notification, ...state.notifications];

    state = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: state.unreadCount + 1,
      lastChecked: DateTime.now(),
    );
  }

  /// Marcar todas las notificaciones como leídas
  void markAllAsRead() {
    if (state.unreadCount > 0) {
      state = state.copyWith(unreadCount: 0);
      debugPrint("[OrderNotificationNotifier] Todas las notificaciones marcadas como leídas");
    }
  }

  /// Limpiar una notificación específica
  void dismissNotification(int index) {
    if (index >= 0 && index < state.notifications.length) {
      final updatedNotifications = List<Map<String, dynamic>>.from(state.notifications);
      updatedNotifications.removeAt(index);

      state = state.copyWith(
        notifications: updatedNotifications,
        unreadCount: state.unreadCount > 0 ? state.unreadCount - 1 : 0,
      );

      debugPrint("[OrderNotificationNotifier] Notificación $index eliminada");
    }
  }

  /// Limpiar todas las notificaciones
  void clearAll() {
    state = state.copyWith(
      notifications: [],
      unreadCount: 0,
    );
    debugPrint("[OrderNotificationNotifier] Todas las notificaciones eliminadas");
  }

  /// Iniciar polling manualmente
  void startPolling() {
    if (!state.isPolling && _service != null) {
      _service!.startPolling();
      state = state.copyWith(isPolling: true);
      debugPrint("[OrderNotificationNotifier] Polling iniciado manualmente");
    }
  }

  /// Detener polling
  void stopPolling() {
    if (state.isPolling && _service != null) {
      _service!.stopPolling();
      state = state.copyWith(isPolling: false);
      debugPrint("[OrderNotificationNotifier] Polling detenido");
    }
  }

  /// Consultar notificaciones manualmente
  Future<void> checkNow() async {
    if (_service != null) {
      try {
        final notifications = await _service!.checkNowAndGetNotifications();

        if (notifications.isNotEmpty) {
          debugPrint("[OrderNotificationNotifier] ${notifications.length} notificaciones obtenidas manualmente");

          for (final notification in notifications) {
            _handleNewOrderNotification(notification);
          }
        }
      } catch (e) {
        debugPrint("[OrderNotificationNotifier] Error consultando notificaciones: $e");
      }
    }
  }

  void _cleanup() {
    debugPrint("[OrderNotificationNotifier] Limpiando recursos...");
    _subscription?.cancel();
    _subscription = null;

    if (_service != null && state.isPolling) {
      _service!.stopPolling();
    }
  }
}
